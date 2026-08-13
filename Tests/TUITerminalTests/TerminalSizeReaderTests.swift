import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import TUITerminal

struct TerminalSizeReaderTests {
    #if canImport(Darwin) || canImport(Glibc)
    @Test("PTY window size is read through ioctl")
    func readsPTYWindowSize() throws {
        let pty = try PTYPair()
        try pty.setWindowSize(columns: 137, rows: 41)

        let size = try TerminalSizeReader(fileDescriptor: pty.slaveFileDescriptor).read()

        #expect(size == TerminalSize(columns: 137, rows: 41))
    }
    #endif

    @Test("Injected ioctl returns a terminal size")
    func readsInjectedSize() throws {
        let reader = TerminalSizeReader(
            fileDescriptor: 42,
            systemCalls: TerminalSizeSystemCalls(
                getWindowSize: { fileDescriptor, size in
                    guard fileDescriptor == 42 else { return -1 }
                    size.pointee.ws_col = 132
                    size.pointee.ws_row = 43
                    return 0
                },
                errorCode: { EIO }
            )
        )

        #expect(try reader.read() == TerminalSize(columns: 132, rows: 43))
    }

    @Test("Non-positive dimensions are rejected")
    func rejectsInvalidSize() {
        let reader = TerminalSizeReader(
            fileDescriptor: STDOUT_FILENO,
            systemCalls: TerminalSizeSystemCalls(
                getWindowSize: { _, size in
                    size.pointee.ws_col = 0
                    size.pointee.ws_row = 24
                    return 0
                },
                errorCode: { EIO }
            )
        )

        #expect(throws: TerminalSizeReaderError.invalidSize(columns: 0, rows: 24)) {
            try reader.read()
        }
    }

    @Test("Ioctl failures preserve errno")
    func reportsIoctlFailure() {
        let reader = TerminalSizeReader(
            fileDescriptor: STDOUT_FILENO,
            systemCalls: TerminalSizeSystemCalls(
                getWindowSize: { _, _ in -1 },
                errorCode: { ENOTTY }
            )
        )

        #expect(throws: TerminalSizeReaderError.ioctlFailed(errorCode: ENOTTY)) {
            try reader.read()
        }
    }

    @Test("Ioctl retries after interruption")
    func retriesInterruptedIoctl() throws {
        /// Protects the test counter with an initialized POSIX mutex.
        final class AttemptCounter: @unchecked Sendable {
            private var value = 0
            private var mutex = pthread_mutex_t()

            init() {
                precondition(pthread_mutex_init(&mutex, nil) == 0)
            }

            deinit {
                precondition(pthread_mutex_destroy(&mutex) == 0)
            }

            func next() -> Int {
                precondition(pthread_mutex_lock(&mutex) == 0)
                defer { precondition(pthread_mutex_unlock(&mutex) == 0) }
                value += 1
                return value
            }
        }

        let attempts = AttemptCounter()
        let reader = TerminalSizeReader(
            fileDescriptor: STDOUT_FILENO,
            systemCalls: TerminalSizeSystemCalls(
                getWindowSize: { _, size in
                    guard attempts.next() > 1 else { return -1 }
                    size.pointee.ws_col = 80
                    size.pointee.ws_row = 24
                    return 0
                },
                errorCode: { EINTR }
            )
        )

        #expect(try reader.read() == TerminalSize(columns: 80, rows: 24))
    }
}
