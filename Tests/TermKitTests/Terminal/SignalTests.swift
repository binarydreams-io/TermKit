@testable import TermKit
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct SignalTests {
  @Test(
    arguments: [
      (SIGINT, TerminalSignalEvent.interrupt),
      (SIGTERM, TerminalSignalEvent.terminate),
      (SIGQUIT, TerminalSignalEvent.quit),
      (SIGHUP, TerminalSignalEvent.hangup),
      (SIGTSTP, TerminalSignalEvent.suspend),
      (SIGCONT, TerminalSignalEvent.resume),
      (SIGWINCH, TerminalSignalEvent.windowChanged)
    ]
  )
  func `Known platform signals map to typed events`(signalNumber: Int32, expected: TerminalSignalEvent) {
    #expect(TerminalSignalEvent(signalNumber: signalNumber) == expected)
  }

  @Test
  func `Unknown signal is ignored`() {
    #expect(TerminalSignalEvent(signalNumber: Int32.max) == nil)
  }
}
