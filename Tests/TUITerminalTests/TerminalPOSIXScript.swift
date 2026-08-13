import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import TUITerminal

final class TerminalPOSIXScript: @unchecked Sendable {
    enum WriteStep {
        case interrupted
        case failure(Int32)
        case count(Int)
        case all
        case zero
    }

    enum ReadStep {
        case interrupted
        case failure(Int32)
        case bytes([UInt8])
    }

    private let lock = NSLock()
    private var writeSteps: [WriteStep]
    private var readSteps: [ReadStep]
    private var currentErrorCode: Int32 = 0
    private var storedWrittenBytes: [UInt8] = []
    private var storedWriteCallCount = 0
    private var storedReadCallCount = 0
    private var storedGetAttributesCallCount = 0
    private var storedSetAttributesCallCount = 0
    private var storedAttributes: [(input: tcflag_t, output: tcflag_t, control: tcflag_t, local: tcflag_t)] = []

    var isTerminalResult: Int32 = 1
    var getAttributesResult: Int32 = 0
    var setAttributesResults: [Int32] = []
    var originalAttributes = termios()

    init(writeSteps: [WriteStep] = [], readSteps: [ReadStep] = []) {
        self.writeSteps = writeSteps
        self.readSteps = readSteps
        originalAttributes.c_iflag = tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        originalAttributes.c_oflag = tcflag_t(OPOST)
        originalAttributes.c_cflag = tcflag_t(CS8)
        originalAttributes.c_lflag = tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
    }

    var calls: TerminalPOSIXCalls {
        TerminalPOSIXCalls(
            read: { [self] descriptor, buffer, count in
                performRead(descriptor: descriptor, buffer: buffer, count: count)
            },
            write: { [self] descriptor, buffer, count in
                performWrite(descriptor: descriptor, buffer: buffer, count: count)
            },
            getAttributes: { [self] _, attributes in
                withLock {
                    storedGetAttributesCallCount += 1
                    attributes.pointee = originalAttributes
                    return getAttributesResult
                }
            },
            setAttributes: { [self] _, _, attributes in
                withLock {
                    storedSetAttributesCallCount += 1
                    let value = attributes.pointee
                    storedAttributes.append((value.c_iflag, value.c_oflag, value.c_cflag, value.c_lflag))
                    return setAttributesResults.isEmpty ? 0 : setAttributesResults.removeFirst()
                }
            },
            isTerminal: { [self] _ in withLock { isTerminalResult } },
            errorCode: { [self] in withLock { currentErrorCode } }
        )
    }

    var writtenBytes: [UInt8] {
        withLock { storedWrittenBytes }
    }

    var writtenText: String {
        String(decoding: writtenBytes, as: UTF8.self)
    }

    var writeCallCount: Int {
        withLock { storedWriteCallCount }
    }

    var readCallCount: Int {
        withLock { storedReadCallCount }
    }

    var getAttributesCallCount: Int {
        withLock { storedGetAttributesCallCount }
    }

    var setAttributesCallCount: Int {
        withLock { storedSetAttributesCallCount }
    }

    var capturedAttributes: [(input: tcflag_t, output: tcflag_t, control: tcflag_t, local: tcflag_t)] {
        withLock { storedAttributes }
    }

    private func performWrite(
        descriptor _: Int32,
        buffer: UnsafeRawPointer?,
        count: Int
    ) -> Int {
        withLock {
            storedWriteCallCount += 1
            let step = writeSteps.isEmpty ? .all : writeSteps.removeFirst()
            switch step {
            case .interrupted:
                currentErrorCode = EINTR
                return -1
            case let .failure(errorCode):
                currentErrorCode = errorCode
                return -1
            case let .count(requestedCount):
                currentErrorCode = 0
                return capture(buffer: buffer, count: min(requestedCount, count))
            case .all:
                currentErrorCode = 0
                return capture(buffer: buffer, count: count)
            case .zero:
                currentErrorCode = 0
                return 0
            }
        }
    }

    private func performRead(
        descriptor _: Int32,
        buffer: UnsafeMutableRawPointer?,
        count: Int
    ) -> Int {
        withLock {
            storedReadCallCount += 1
            let step = readSteps.isEmpty ? .bytes([]) : readSteps.removeFirst()
            switch step {
            case .interrupted:
                currentErrorCode = EINTR
                return -1
            case let .failure(errorCode):
                currentErrorCode = errorCode
                return -1
            case let .bytes(bytes):
                currentErrorCode = 0
                let byteCount = min(bytes.count, count)
                guard let buffer else { return 0 }
                for index in 0 ..< byteCount {
                    buffer.storeBytes(of: bytes[index], toByteOffset: index, as: UInt8.self)
                }
                return byteCount
            }
        }
    }

    private func capture(buffer: UnsafeRawPointer?, count: Int) -> Int {
        guard let buffer, count > 0 else { return 0 }
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        storedWrittenBytes.append(contentsOf: UnsafeBufferPointer(start: bytes, count: count))
        return count
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
