import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import TUITerminal

#if canImport(Darwin) || canImport(Glibc)
struct TerminalPTYIntegrationTests {
    private let activation = Array(
        "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1000h\u{1B}[?1006h\u{1B}[?1004h".utf8
    )
    private let deactivation = Array(
        (
            "\u{1B}[?1004l"
                + "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
                + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
                + "\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l"
        ).utf8
    )

    @Test("PTY session sets raw mode and restores every activation cycle")
    func sessionLifecycle() throws {
        let pty = try PTYPair()
        let originalAttributes = try pty.attributesSnapshot()
        let session = makeSession(pty: pty)

        let start = try pty.captureOutput(exactByteCount: activation.count) {
            try session.start()
        }
        #expect(try start.result.get() == .started)
        #expect(start.output == activation)
        try expectRawAttributes(try pty.attributes())

        let suspend = try pty.captureOutput(exactByteCount: deactivation.count) {
            try session.suspend()
        }
        #expect(try suspend.result.get() == .suspended)
        #expect(suspend.output == deactivation)
        #expect(try pty.attributesSnapshot() == originalAttributes)

        let resume = try pty.captureOutput(exactByteCount: activation.count) {
            try session.resume()
        }
        #expect(try resume.result.get() == .resumed(requiresFullRepaint: true))
        #expect(resume.output == activation)
        try expectRawAttributes(try pty.attributes())

        let stop = try pty.captureOutput(exactByteCount: deactivation.count) {
            try session.stop()
        }
        #expect(try stop.result.get() == .stopped)
        #expect(stop.output == deactivation)
        #expect(try pty.attributesSnapshot() == originalAttributes)
    }

    @Test("PTY scoped session restores modes after an error")
    func scopedSessionErrorCleanup() throws {
        enum TestError: Error { case expected }

        let pty = try PTYPair()
        let originalAttributes = try pty.attributesSnapshot()
        let session = makeSession(pty: pty)

        let operation = try pty.captureOutput(
            exactByteCount: activation.count + deactivation.count
        ) {
            try session.withActiveSession { _ in
                throw TestError.expected
            }
        }

        #expect(throws: TestError.expected) {
            try operation.result.get()
        }
        #expect(operation.output == activation + deactivation)
        #expect(session.state == .inactive)
        #expect(try pty.attributesSnapshot() == originalAttributes)
    }

    @Test("PTY async session restores modes after cancellation", .timeLimit(.minutes(1)))
    func asyncSessionCancellationCleanup() async throws {
        let pty = try PTYPair()
        let originalAttributes = try pty.attributesSnapshot()

        let start = try pty.captureOutput(exactByteCount: activation.count) {
            Task {
                let session = makeSession(pty: pty)
                try await session.withActiveSession { _ in
                    try await Task.sleep(for: .seconds(60))
                }
            }
        }
        let task = try start.result.get()
        #expect(start.output == activation)

        let cancellation = try pty.captureOutput(exactByteCount: deactivation.count) {
            task.cancel()
        }
        _ = try cancellation.result.get()
        #expect(cancellation.output == deactivation)
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(try pty.attributesSnapshot() == originalAttributes)
    }

    private func makeSession(pty: PTYPair) -> TerminalSession {
        TerminalSession(
            transport: TerminalTransport(
                inputFileDescriptor: pty.slaveFileDescriptor,
                outputFileDescriptor: pty.slaveFileDescriptor
            )
        )
    }

    private func expectRawAttributes(_ value: termios) throws {
        var attributes = value
        #expect(attributes.c_iflag & tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON) == 0)
        #expect(attributes.c_oflag & tcflag_t(OPOST) == 0)
        #expect(attributes.c_cflag & tcflag_t(CS8) != 0)
        #expect(attributes.c_lflag & tcflag_t(ECHO | ICANON | IEXTEN | ISIG) == 0)
        #expect(terminalControlCharacter(VMIN, in: &attributes) == 0)
        #expect(terminalControlCharacter(VTIME, in: &attributes) == 0)
    }
}
#endif
