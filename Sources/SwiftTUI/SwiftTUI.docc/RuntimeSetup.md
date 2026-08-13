# Runtime Setup

Create one terminal session, presenter, event source, and runtime in an asynchronous entry point.

```swift
import SwiftTUI

@main
@MainActor
struct TerminalApp {
    static func main() async throws {
        let transport = TerminalTransport()
        let capabilities = TerminalCapabilityDetector.capabilities(from: .current())
        let session = TerminalSession(transport: transport, capabilities: capabilities)
        let size = try TerminalSizeReader(fileDescriptor: transport.outputFileDescriptor).read()
        let events = try TerminalEventSource(inputFileDescriptor: transport.inputFileDescriptor)
        let runtime = TUIRuntime(
            view: Text("Hello, terminal"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: size.columns, height: size.rows),
            eventSource: events
        )
        try await runtime.run()
    }
}
```

`run()` requires an event source. The runtime owns raw mode, alternate-screen state, signal handling, suspend and resume, and cleanup. A terminal capability probe can enable synchronized output. Probe failure keeps the ordinary ANSI fallback.

Supply `onInput` for application commands. Call ``TUIRuntime/stop()`` to restore the terminal and end the event loop.
