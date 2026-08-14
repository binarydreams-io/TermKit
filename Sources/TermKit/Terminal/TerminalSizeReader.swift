#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A failure while reading the terminal dimensions.
public enum TerminalSizeReaderError: Error, Equatable, Sendable {
    /// The platform `ioctl` call failed.
    case ioctlFailed(errorCode: Int32)

    /// The terminal returned a non-positive dimension.
    case invalidSize(columns: Int, rows: Int)
}

struct TerminalSizeSystemCalls: Sendable {
    var getWindowSize: @Sendable (Int32, UnsafeMutablePointer<winsize>) -> Int32
    var errorCode: @Sendable () -> Int32

    static let system = Self(
        getWindowSize: platformGetWindowSize,
        errorCode: { errno }
    )
}

/// Reads terminal dimensions from a file descriptor.
public struct TerminalSizeReader: Sendable {
    /// The terminal descriptor queried by the reader.
    public let fileDescriptor: Int32
    private let systemCalls: TerminalSizeSystemCalls

    /// Creates a reader for the supplied terminal descriptor.
    public init(fileDescriptor: Int32 = STDOUT_FILENO) {
        self.init(fileDescriptor: fileDescriptor, systemCalls: .system)
    }

    init(fileDescriptor: Int32, systemCalls: TerminalSizeSystemCalls) {
        self.fileDescriptor = fileDescriptor
        self.systemCalls = systemCalls
    }

    /// Returns the current terminal size in cells.
    public func read() throws -> TerminalSize {
        var windowSize = winsize()
        while systemCalls.getWindowSize(fileDescriptor, &windowSize) != 0 {
            let errorCode = systemCalls.errorCode()
            if errorCode == EINTR { continue }
            throw TerminalSizeReaderError.ioctlFailed(errorCode: errorCode)
        }

        let columns = Int(windowSize.ws_col)
        let rows = Int(windowSize.ws_row)
        guard columns > 0, rows > 0 else {
            throw TerminalSizeReaderError.invalidSize(columns: columns, rows: rows)
        }
        return TerminalSize(columns: columns, rows: rows)
    }
}

private func platformGetWindowSize(
    _ fileDescriptor: Int32,
    _ windowSize: UnsafeMutablePointer<winsize>
) -> Int32 {
    #if canImport(Darwin)
        Darwin.ioctl(fileDescriptor, TIOCGWINSZ, windowSize)
    #else
        Glibc.ioctl(fileDescriptor, UInt(TIOCGWINSZ), windowSize)
    #endif
}
