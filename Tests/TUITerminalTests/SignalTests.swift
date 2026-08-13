import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import TUITerminal

struct SignalTests {
    @Test("Known platform signals map to typed events", arguments: [
        (SIGINT, TerminalSignalEvent.interrupt),
        (SIGTERM, TerminalSignalEvent.terminate),
        (SIGQUIT, TerminalSignalEvent.quit),
        (SIGHUP, TerminalSignalEvent.hangup),
        (SIGTSTP, TerminalSignalEvent.suspend),
        (SIGCONT, TerminalSignalEvent.resume),
        (SIGWINCH, TerminalSignalEvent.windowChanged),
    ])
    func mapsSignal(signalNumber: Int32, expected: TerminalSignalEvent) {
        #expect(TerminalSignalEvent(signalNumber: signalNumber) == expected)
    }

    @Test("Unknown signal is ignored")
    func ignoresUnknownSignal() {
        #expect(TerminalSignalEvent(signalNumber: Int32.max) == nil)
    }
}
