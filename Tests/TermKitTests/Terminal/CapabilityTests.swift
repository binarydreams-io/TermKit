@testable import TermKit
import Testing

struct CapabilityTests {
  @Test
  func `Legacy explicit OSC 52 policy preserves clipboard support`() {
    let capabilities = TerminalCapabilities(allowsOSC52: true)

    #expect(capabilities.supportsOSC52)
    #expect(capabilities.allowsOSC52)
  }

  @Test
  func `Environment hints stay bounded and do not prove synchronized output`() {
    let environment = TerminalEnvironment(
      values: [
        "COLORTERM": "truecolor",
        "KITTY_WINDOW_ID": "1",
        "TERM": "xterm-kitty",
        "UNRECOGNIZED": "ignored",
        "TMUX": String(repeating: "x", count: 20)
      ],
      maximumValueByteCount: 10
    )

    let capabilities = TerminalCapabilityDetector.capabilities(from: environment, allowsOSC52: true)

    #expect(environment["UNRECOGNIZED"] == nil)
    #expect(environment["TMUX"] == nil)
    #expect(capabilities.color == .trueColor)
    #expect(capabilities.supportsKittyKeyboard)
    #expect(capabilities.synchronizedOutput == .unknown)
    #expect(capabilities.supportsOSC52)
    #expect(capabilities.allowsOSC52)
    #expect(capabilities.supportsTerminalTitle)
  }

  @Test
  func `OSC 52 support is conservative and independent from policy`() {
    let unknown = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(values: ["TERM": "xterm-256color"]),
      allowsOSC52: true
    )
    let kitty = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(values: ["KITTY_WINDOW_ID": "1", "TERM": "xterm-kitty"])
    )
    let multiplexedKitty = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(
        values: ["KITTY_WINDOW_ID": "1", "TERM": "xterm-kitty", "TMUX": "/tmp/tmux"]
      )
    )

    #expect(unknown.supportsOSC52 == false)
    #expect(unknown.allowsOSC52)
    #expect(kitty.supportsOSC52)
    #expect(kitty.allowsOSC52 == false)
    #expect(multiplexedKitty.supportsOSC52 == false)
  }

  @Test
  func `Multiplexers do not inherit direct terminal OSC or title support`() {
    let screen = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(
        values: ["TERM": "screen-256color", "TERM_PROGRAM": "WezTerm"]
      )
    )

    #expect(screen.supportsOSC52 == false)
    #expect(screen.supportsTerminalTitle == false)
  }

  @Test(
    arguments: [
      ["GHOSTTY_RESOURCES_DIR": "/tmp/ghostty", "TERM": "xterm-ghostty"],
      ["TERM_PROGRAM": "iTerm.app", "TERM": "xterm-256color"],
      ["TERM_PROGRAM": "WezTerm", "TERM": "xterm-256color"],
      ["WT_SESSION": "session", "TERM": "xterm-256color"]
    ]
  )
  func `Known direct terminals support OSC 52`(values: [String: String]) {
    let capabilities = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(values: values)
    )

    #expect(capabilities.supportsOSC52)
  }

  @Test
  func `Dumb terminals do not support terminal titles`() {
    let dumb = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(values: ["TERM": "dumb"])
    )
    let xterm = TerminalCapabilityDetector.capabilities(
      from: TerminalEnvironment(values: ["TERM": "xterm-256color"])
    )

    #expect(dumb.supportsTerminalTitle == false)
    #expect(xterm.supportsTerminalTitle)
  }

  @Test
  func `Terminfo hints influence color and input features`() {
    let environment = TerminalEnvironment(values: ["TERM": "dumb"])
    let provider = StaticTerminfoHintProvider(
      record: Array("test|bounded fixture,colors#256,BE,XM,focus,kitty_keyboard,".utf8)
    )

    let result = TerminalCapabilityDetector.detection(
      from: environment,
      terminfoHintProvider: provider
    )

    #expect(result.terminfoDiagnostic == nil)
    #expect(result.capabilities.color == .ansi256)
    #expect(result.capabilities.supportsBracketedPaste)
    #expect(result.capabilities.supportsSGRMouse)
    #expect(result.capabilities.supportsFocusReporting)
    #expect(result.capabilities.supportsKittyKeyboard)
  }

  @Test
  func `Malformed terminfo falls back to environment capabilities`() {
    let environment = TerminalEnvironment(values: ["TERM": "xterm-256color"])
    let provider = StaticTerminfoHintProvider(record: Array("test,colors#many,kitty_keyboard,".utf8))

    let result = TerminalCapabilityDetector.detection(
      from: environment,
      terminfoHintProvider: provider
    )

    #expect(result.terminfoDiagnostic == .malformedField(index: 1))
    #expect(result.capabilities.color == .ansi256)
    #expect(!result.capabilities.supportsKittyKeyboard)
  }

  @Test
  func `Oversized terminfo falls back with a typed diagnostic`() {
    let environment = TerminalEnvironment(values: ["TERM": "dumb"])
    let provider = StaticTerminfoHintProvider(record: Array(repeating: 0x61, count: 65))

    let result = TerminalCapabilityDetector.detection(
      from: environment,
      terminfoHintProvider: provider,
      terminfoHintPolicy: TerminfoHintPolicy(maximumRecordByteCount: 64)
    )

    #expect(result.terminfoDiagnostic == .recordTooLarge(limit: 64))
    #expect(result.capabilities.color == .monochrome)
  }

  @Test
  func `Terminfo cannot prove synchronized output`() {
    let provider = StaticTerminfoHintProvider(
      record: Array("test,synchronized_output,sync,Sync=\\E[?2026h,".utf8)
    )

    let result = TerminalCapabilityDetector.detection(
      from: TerminalEnvironment(values: ["TERM": "xterm"]),
      terminfoHintProvider: provider
    )

    #expect(result.terminfoDiagnostic == nil)
    #expect(result.capabilities.synchronizedOutput == .unknown)
  }

  @Test
  func `Probe policy clamps untrusted limits`() {
    let low = TerminalProbePolicy(timeout: .zero, maximumResponseByteCount: 0)
    let high = TerminalProbePolicy(timeout: .seconds(20), maximumResponseByteCount: Int.max)

    #expect(low.timeout == .milliseconds(10))
    #expect(low.maximumResponseByteCount == 32)
    #expect(high.timeout == .seconds(1))
    #expect(high.maximumResponseByteCount == 4096)
    #expect(low.timeoutRequirement == .optional)
    #expect(TerminalProbePolicy(timeoutRequirement: .mandatory).timeoutRequirement == .mandatory)
  }

  @Test
  func `Production terminfo provider rejects unsafe terminal names`() {
    let provider = InfocmpTerminfoHintProvider(executablePath: "/does/not/exist")

    #expect(provider.capabilityRecord(for: "xterm;touch-pwned") == nil)
    #expect(provider.capabilityRecord(for: String(repeating: "x", count: 257)) == nil)
  }

  @Test
  func `Production terminfo provider bounds execution time`() {
    let provider = InfocmpTerminfoHintProvider(
      executablePath: "/usr/bin/yes",
      timeoutMilliseconds: 10
    )

    #expect(provider.capabilityRecord(for: "1") == nil)
  }

  @Test
  func `Synchronized output report parses across chunks`() {
    var parser = SynchronizedOutputQueryParser()

    #expect(parser.append(Array("noise\u{1B}[?202".utf8)) == nil)
    #expect(parser.append(Array("6;1$y".utf8)) == .supported)
  }

  @Test
  func `Synchronized output permanent reset is unsupported`() {
    var parser = SynchronizedOutputQueryParser()

    #expect(parser.append(Array("\u{1B}[?2026;4$y".utf8)) == .unsupported)
  }

  @Test
  func `Probe start does not read or wait`() {
    var probe = SynchronizedOutputProbe(
      policy: TerminalProbePolicy(timeout: .milliseconds(50), maximumResponseByteCount: 32)
    )

    #expect(probe.start() == SynchronizedOutputProbe.query)
    #expect(probe.start().isEmpty)
    #expect(probe.checkTimeout(elapsed: .milliseconds(49)) == nil)
    #expect(probe.checkTimeout(elapsed: .milliseconds(50)) == .timedOut)
  }

  @Test
  func `Probe response size is bounded`() {
    var parser = SynchronizedOutputQueryParser(maximumResponseByteCount: 32)

    #expect(parser.append(Array(repeating: 0x61, count: 33)) == .responseTooLarge(limit: 32))
  }
}
