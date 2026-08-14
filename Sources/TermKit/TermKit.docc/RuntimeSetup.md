# Runtime Setup

Configure the objects that a TermKit application needs at startup.

Create one terminal session, frame presenter, event source, and runtime in an asynchronous entry point.

```swift
import TermKit

@main
@MainActor
struct TerminalApp {
    static func main() async throws {
        let transport = TerminalTransport()
        let capabilities = TerminalCapabilityDetector.capabilities(from: TerminalEnvironment.makeCurrent())
        let session = TerminalSession(transport: transport, capabilities: capabilities)
        let size = try TerminalSizeReader(fileDescriptor: transport.outputFileDescriptor).read()
        let events = try TerminalEventSource(inputFileDescriptor: transport.inputFileDescriptor)
        let runtime = Runtime(
            view: Text("Hello, terminal"),
            presenter: FramePresenter(session: session),
            terminalSize: CellSize(width: size.columns, height: size.rows),
            eventSource: events
        )
        try await runtime.run()
    }
}
```

The `run()` method requires an event source. The runtime owns raw mode, the alternate screen, signal handling, suspension, resumption, and cleanup.

The runtime probes synchronized output when its support is unknown. If the probe does not confirm support, presentation uses ordinary ANSI output.

Pass `onInput` to the initializer for application commands. Call ``Runtime/stop()`` to restore the terminal and end the event loop.
