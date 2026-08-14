@testable import TermKit
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct SessionTests {
  @Test
  func `Session owns raw mode and protocol cleanup`() throws {
    let script = TerminalPOSIXScript()
    let session = makeSession(script: script, kittyKeyboard: true)

    #expect(try session.start() == .started)
    #expect(session.state == .active)

    let raw = try #require(script.capturedAttributes.first)
    #expect(raw.input & tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON) == 0)
    #expect(raw.output & tcflag_t(OPOST) == 0)
    #expect(raw.local & tcflag_t(ECHO | ICANON | IEXTEN | ISIG) == 0)
    #expect(raw.control & tcflag_t(CS8) != 0)
    #expect(script.writtenText.contains("\u{1B}[?1049h\u{1B}[?25l"))
    #expect(script.writtenText.contains("\u{1B}[?2004h"))
    #expect(script.writtenText.contains("\u{1B}[?1002h\u{1B}[?1006h"))
    #expect(script.writtenText.contains("\u{1B}[?1004h"))
    #expect(script.writtenText.contains("\u{1B}[>5u"))

    #expect(try session.stop() == .stopped)
    #expect(session.state == .inactive)
    #expect(script.writtenText.contains("\u{1B}[?1006l"))
    #expect(script.writtenText.contains("\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l"))
    #expect(script.setAttributesCallCount == 2)
  }

  @Test
  func `Suspend and resume restore modes and request repaint`() throws {
    let script = TerminalPOSIXScript()
    let session = makeSession(script: script)
    try session.start()

    #expect(try session.suspend() == .suspended)
    #expect(session.state == .suspended)
    #expect(try session.resume() == .resumed(requiresFullRepaint: true))
    #expect(session.state == .active)
    #expect(script.getAttributesCallCount == 2)
    #expect(script.setAttributesCallCount == 3)

    try session.stop()
  }

  @Test
  func `Presentation uses synchronized output only after probe proof`() throws {
    let script = TerminalPOSIXScript()
    let session = makeSession(script: script)
    try session.start()
    session.applySynchronizedOutputProbeResult(.supported)

    try session.present(Array("frame".utf8))

    #expect(script.writtenText.contains("\u{1B}[?2026hframe\u{1B}[?2026l"))
    try session.stop()
  }

  @Test
  func `Terminal title is sanitized and restored across lifecycle transitions`() throws {
    let script = TerminalPOSIXScript()
    var capabilities = TerminalCapabilities()
    capabilities.supportsTerminalTitle = true
    let session = TerminalSession(
      transport: TerminalTransport(systemCalls: script.calls),
      capabilities: capabilities
    )

    try session.start()
    try session.setTitle("Term\u{1B}]2;bad\u{07}\nTitle\u{009C}")
    try session.suspend()
    try session.resume()
    try session.clearTitle()
    try session.stop()

    #expect(script.writtenText.hasPrefix("\u{1B}[?1049h"))
    #expect(script.writtenText.contains("\u{1B}[22;2t\u{1B}]2;Term]2;badTitle\u{07}"))
    #expect(script.writtenText.contains("\u{1B}[23;2t\u{1B}[?1049h"))
    #expect(script.writtenText.contains("\u{1B}[?1004h\u{1B}[22;2t\u{1B}]2;Term]2;badTitle\u{07}"))
    #expect(script.writtenText.contains("\u{1B}]2;\u{07}"))
    #expect(script.writtenText.hasSuffix("\u{1B}[?1049l\u{1B}[23;2t"))
  }

  @Test
  func `Unsupported terminal title operations are no-ops`() throws {
    let script = TerminalPOSIXScript()
    let session = makeSession(script: script)

    try session.setTitle("ignored")
    try session.clearTitle()

    #expect(session.state == .inactive)
    #expect(script.writtenBytes.isEmpty)
  }

  @Test
  func `Failed title resume restores and rebuilds the title stack`() throws {
    let script = TerminalPOSIXScript(writeSteps: [
      .all, .all, .all, .all, .all, .all,
      .failure(EIO),
      .all, .all, .all, .all, .all
    ])
    var capabilities = TerminalCapabilities()
    capabilities.supportsTerminalTitle = true
    let session = TerminalSession(
      transport: TerminalTransport(systemCalls: script.calls),
      capabilities: capabilities
    )

    try session.start()
    try session.setTitle("App")
    try session.suspend()
    #expect(throws: TerminalSessionError.self) {
      try session.resume()
    }
    #expect(try session.resume() == .resumed(requiresFullRepaint: true))
    try session.stop()

    #expect(script.writtenText.components(separatedBy: "\u{1B}[22;2t").count - 1 == 3)
    #expect(script.writtenText.components(separatedBy: "\u{1B}[23;2t").count - 1 == 3)
  }

  @Test
  func `Permanent presentation failure restores terminal state`() throws {
    let script = TerminalPOSIXScript(writeSteps: [.all, .failure(EIO), .all])
    let session = makeSession(script: script)
    try session.start()

    #expect(
      throws: TerminalSessionError.transport(
        .posix(operation: .write, errorCode: EIO, remainingByteCount: 5)
      )
    ) {
      try session.present(Array("frame".utf8))
    }
    #expect(session.state == .inactive)
    #expect(script.setAttributesCallCount == 2)
    #expect(script.writtenText.contains("\u{1B}[?1049l"))
  }

  @Test
  func `Scoped session restores after thrown work`() {
    enum TestError: Error { case expected }

    let script = TerminalPOSIXScript()
    let session = makeSession(script: script)

    #expect(throws: TestError.expected) {
      try session.withActiveSession { _ in
        throw TestError.expected
      }
    }
    #expect(session.state == .inactive)
    #expect(script.setAttributesCallCount == 2)
  }

  @Test
  func `Non-terminal input fails before termios changes`() {
    let script = TerminalPOSIXScript()
    script.isTerminalResult = 0
    let session = makeSession(script: script)

    #expect(throws: TerminalSessionError.notTerminal(fileDescriptor: 0)) {
      try session.start()
    }
    #expect(script.getAttributesCallCount == 0)
    #expect(script.writtenBytes.isEmpty)
  }

  @Test
  func `Signal events drive suspend and resume outside handlers`() throws {
    let script = TerminalPOSIXScript()
    let session = makeSession(script: script)
    try session.start()

    #expect(try session.handleSignalEvent(.suspend) == .suspendProcess)
    #expect(session.state == .suspended)
    #expect(try session.handleSignalEvent(.resume) == .resumed(requiresFullRepaint: true))
    #expect(session.state == .active)
    #expect(try session.handleSignalEvent(.windowChanged) == .readSize)
    #expect(try session.handleSignalEvent(.terminate) == .terminate)
    #expect(session.state == .inactive)
  }

  private func makeSession(script: TerminalPOSIXScript, kittyKeyboard: Bool = false) -> TerminalSession {
    var capabilities = TerminalCapabilities()
    capabilities.supportsKittyKeyboard = kittyKeyboard
    return TerminalSession(
      transport: TerminalTransport(systemCalls: script.calls),
      capabilities: capabilities,
      configuration: TerminalSessionConfiguration(enablesKittyKeyboard: kittyKeyboard)
    )
  }
}
