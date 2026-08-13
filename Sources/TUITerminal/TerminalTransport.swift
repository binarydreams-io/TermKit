#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The POSIX operation that failed.
public enum TerminalPOSIXOperation: Equatable, Sendable {
    case read
    case write
    case getAttributes
    case setAttributes
    case checkTerminal
}

/// A terminal transport failure.
public enum TerminalTransportError: Error, Equatable, Sendable {
    /// A POSIX call failed.
    case posix(operation: TerminalPOSIXOperation, errorCode: Int32, remainingByteCount: Int)

    /// A write returned zero before it consumed all bytes.
    case stalledWrite(remainingByteCount: Int)

    /// A buffered frame was already active.
    case frameAlreadyActive

    /// No buffered frame was active.
    case noActiveFrame

    /// The configured frame limit was exceeded.
    case frameTooLarge(limit: Int)
}

/// Injectable POSIX calls for terminal I/O and termios state.
public struct TerminalPOSIXCalls: Sendable {
    public var read: @Sendable (Int32, UnsafeMutableRawPointer?, Int) -> Int
    public var write: @Sendable (Int32, UnsafeRawPointer?, Int) -> Int
    public var getAttributes: @Sendable (Int32, UnsafeMutablePointer<termios>) -> Int32
    public var setAttributes: @Sendable (Int32, Int32, UnsafePointer<termios>) -> Int32
    public var isTerminal: @Sendable (Int32) -> Int32
    public var errorCode: @Sendable () -> Int32

    /// Creates an injectable POSIX call table.
    public init(
        read: @escaping @Sendable (Int32, UnsafeMutableRawPointer?, Int) -> Int,
        write: @escaping @Sendable (Int32, UnsafeRawPointer?, Int) -> Int,
        getAttributes: @escaping @Sendable (Int32, UnsafeMutablePointer<termios>) -> Int32,
        setAttributes: @escaping @Sendable (Int32, Int32, UnsafePointer<termios>) -> Int32,
        isTerminal: @escaping @Sendable (Int32) -> Int32,
        errorCode: @escaping @Sendable () -> Int32
    ) {
        self.read = read
        self.write = write
        self.getAttributes = getAttributes
        self.setAttributes = setAttributes
        self.isTerminal = isTerminal
        self.errorCode = errorCode
    }

    /// The active platform's POSIX calls.
    public static let system = Self(
        read: platformRead,
        write: platformWrite,
        getAttributes: platformGetAttributes,
        setAttributes: platformSetAttributes,
        isTerminal: platformIsTerminal,
        errorCode: { errno }
    )
}

/// A robust terminal byte transport with bounded frame buffering.
public final class TerminalTransport {
    /// The standard synchronized-output begin sequence.
    public static let beginSynchronizedOutput = Array("\u{1B}[?2026h".utf8)

    /// The standard synchronized-output end sequence.
    public static let endSynchronizedOutput = Array("\u{1B}[?2026l".utf8)

    public let inputFileDescriptor: Int32
    public let outputFileDescriptor: Int32
    public let systemCalls: TerminalPOSIXCalls
    public let maximumFrameByteCount: Int

    private var frameBuffer: [UInt8]?

    /// Creates a terminal transport.
    public init(
        inputFileDescriptor: Int32 = STDIN_FILENO,
        outputFileDescriptor: Int32 = STDOUT_FILENO,
        maximumFrameByteCount: Int = 4_194_304,
        systemCalls: TerminalPOSIXCalls = .system
    ) {
        self.inputFileDescriptor = inputFileDescriptor
        self.outputFileDescriptor = outputFileDescriptor
        self.maximumFrameByteCount = min(max(maximumFrameByteCount, 1_024), 67_108_864)
        self.systemCalls = systemCalls
    }

    #if DEBUG
    deinit {
        assert(frameBuffer == nil, "Terminal transport deinitialized with an active frame.")
    }
    #endif

    /// Reads at most the specified number of bytes.
    ///
    /// The file descriptor determines whether the call can block.
    public func read(maximumByteCount: Int = 4_096) throws -> [UInt8] {
        let count = min(max(maximumByteCount, 1), 1_048_576)
        var bytes = [UInt8](repeating: 0, count: count)
        while true {
            let bytesRead = bytes.withUnsafeMutableBytes { buffer in
                systemCalls.read(inputFileDescriptor, buffer.baseAddress, buffer.count)
            }
            if bytesRead >= 0 {
                bytes.removeSubrange(bytesRead...)
                return bytes
            }
            let errorCode = systemCalls.errorCode()
            if errorCode == EINTR { continue }
            throw TerminalTransportError.posix(
                operation: .read,
                errorCode: errorCode,
                remainingByteCount: count
            )
        }
    }

    /// Writes all bytes, including after interruptions and partial writes.
    public func writeAll(_ bytes: [UInt8]) throws {
        guard bytes.isEmpty == false else { return }
        try bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var writtenByteCount = 0
            while writtenByteCount < buffer.count {
                let result = systemCalls.write(
                    outputFileDescriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    buffer.count - writtenByteCount
                )
                if result > 0 {
                    writtenByteCount += min(result, buffer.count - writtenByteCount)
                    continue
                }
                if result == 0 {
                    throw TerminalTransportError.stalledWrite(
                        remainingByteCount: buffer.count - writtenByteCount
                    )
                }
                let errorCode = systemCalls.errorCode()
                if errorCode == EINTR { continue }
                throw TerminalTransportError.posix(
                    operation: .write,
                    errorCode: errorCode,
                    remainingByteCount: buffer.count - writtenByteCount
                )
            }
        }
    }

    /// Starts a bounded logical frame.
    public func beginFrame() throws {
        guard frameBuffer == nil else { throw TerminalTransportError.frameAlreadyActive }
        frameBuffer = []
        frameBuffer?.reserveCapacity(min(maximumFrameByteCount, 16_384))
    }

    /// Appends bytes to the active logical frame.
    public func appendToFrame(_ bytes: [UInt8]) throws {
        guard var frameBuffer else { throw TerminalTransportError.noActiveFrame }
        guard bytes.count <= maximumFrameByteCount - frameBuffer.count else {
            self.frameBuffer = nil
            throw TerminalTransportError.frameTooLarge(limit: maximumFrameByteCount)
        }
        frameBuffer.append(contentsOf: bytes)
        self.frameBuffer = frameBuffer
    }

    /// Completes and writes one logical frame.
    public func endFrame(synchronized: Bool) throws {
        guard var frameBuffer else { throw TerminalTransportError.noActiveFrame }
        self.frameBuffer = nil
        guard frameBuffer.isEmpty == false else { return }

        if synchronized {
            let envelopeByteCount = Self.beginSynchronizedOutput.count + Self.endSynchronizedOutput.count
            guard frameBuffer.count <= maximumFrameByteCount - envelopeByteCount else {
                throw TerminalTransportError.frameTooLarge(limit: maximumFrameByteCount)
            }
            frameBuffer.insert(contentsOf: Self.beginSynchronizedOutput, at: 0)
            frameBuffer.append(contentsOf: Self.endSynchronizedOutput)
        }
        try writeAll(frameBuffer)
    }

    /// Drops the active frame without writing it.
    public func cancelFrame() {
        frameBuffer = nil
    }

    func withFrame<Result>(
        synchronized: Bool,
        _ body: () throws -> Result
    ) throws -> Result {
        #if DEBUG
        assert(frameBuffer == nil, "Terminal frame scope started while another frame was active.")
        #endif
        try beginFrame()
        do {
            let result = try body()
            try endFrame(synchronized: synchronized)
            #if DEBUG
            assert(frameBuffer == nil, "Terminal frame scope ended with an active frame.")
            #endif
            return result
        } catch {
            cancelFrame()
            #if DEBUG
            assert(frameBuffer == nil, "Terminal frame scope failed to cancel its frame.")
            #endif
            throw error
        }
    }
}

private func platformRead(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.read(descriptor, buffer, count)
    #else
    Glibc.read(descriptor, buffer, count)
    #endif
}

private func platformWrite(_ descriptor: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.write(descriptor, buffer, count)
    #else
    Glibc.write(descriptor, buffer, count)
    #endif
}

private func platformGetAttributes(_ descriptor: Int32, _ attributes: UnsafeMutablePointer<termios>) -> Int32 {
    tcgetattr(descriptor, attributes)
}

private func platformSetAttributes(_ descriptor: Int32, _ action: Int32, _ attributes: UnsafePointer<termios>) -> Int32 {
    tcsetattr(descriptor, action, attributes)
}

private func platformIsTerminal(_ descriptor: Int32) -> Int32 {
    isatty(descriptor)
}
