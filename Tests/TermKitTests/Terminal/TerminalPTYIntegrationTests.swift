@testable import TermKit
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)
struct TerminalPTYIntegrationTests {
  private let activation = Array(
    "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?1004h".utf8
  )
  private let deactivation = Array(
    ("\u{1B}[?1004l"
      + "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
      + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
      + "\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l").utf8
  )
  private let titleSave = Array("\u{1B}[22;2t".utf8)
  private let titleRestore = Array("\u{1B}[23;2t".utf8)

  @Test
  func `PTY session sets raw mode and restores every activation cycle`() throws {
    let pty = try PTYPair()
    let originalAttributes = try pty.attributesSnapshot()
    let session = makeSession(pty: pty)

    let start = try pty.captureOutput(exactByteCount: activation.count) {
      try session.start()
    }
    #expect(try start.result.get() == .started)
    #expect(start.output == activation)
    try expectRawAttributes(pty.attributes())

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
    try expectRawAttributes(pty.attributes())

    let stop = try pty.captureOutput(exactByteCount: deactivation.count) {
      try session.stop()
    }
    #expect(try stop.result.get() == .stopped)
    #expect(stop.output == deactivation)
    #expect(try pty.attributesSnapshot() == originalAttributes)
  }

  @Test
  func `PTY scoped session restores modes after an error`() throws {
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

  @Test
  func `PTY title override is reapplied after resume and restored on exit`() throws {
    let pty = try PTYPair()
    let title = Array("\u{1B}]2;PTY title\u{07}".utf8)
    let clear = Array("\u{1B}]2;\u{07}".utf8)
    let session = makeSession(pty: pty, terminalTitle: true)

    let start = try pty.captureOutput(exactByteCount: activation.count) {
      try session.start()
    }
    #expect(try start.result.get() == .started)
    #expect(start.output == activation)

    let setTitle = try pty.captureOutput(exactByteCount: titleSave.count + title.count) {
      try session.setTitle("PTY title")
    }
    try setTitle.result.get()
    #expect(setTitle.output == titleSave + title)

    let suspend = try pty.captureOutput(exactByteCount: deactivation.count + titleRestore.count) {
      try session.suspend()
    }
    #expect(try suspend.result.get() == .suspended)
    #expect(suspend.output == deactivation + titleRestore)

    let resume = try pty.captureOutput(exactByteCount: titleSave.count + activation.count + title.count) {
      try session.resume()
    }
    #expect(try resume.result.get() == .resumed(requiresFullRepaint: true))
    #expect(resume.output == activation + titleSave + title)

    let clearTitle = try pty.captureOutput(exactByteCount: clear.count) {
      try session.clearTitle()
    }
    try clearTitle.result.get()
    #expect(clearTitle.output == clear)

    let stop = try pty.captureOutput(exactByteCount: deactivation.count + titleRestore.count) {
      try session.stop()
    }
    #expect(try stop.result.get() == .stopped)
    #expect(stop.output == deactivation + titleRestore)
  }

  @Test(.timeLimit(.minutes(1)))
  func `PTY async session restores modes after cancellation`() async throws {
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

  private func makeSession(pty: PTYPair, terminalTitle: Bool = false) -> TerminalSession {
    var capabilities = TerminalCapabilities()
    capabilities.supportsTerminalTitle = terminalTitle
    return TerminalSession(
      transport: TerminalTransport(
        inputFileDescriptor: pty.slaveFileDescriptor,
        outputFileDescriptor: pty.slaveFileDescriptor
      ),
      capabilities: capabilities
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
