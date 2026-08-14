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

## Optional input and clipboard features

Enable Kitty keyboard support in both the session and the input parser. ``TerminalKeyEvent/normalizedText`` uses a reported base-layout key when available.
It falls back to the JCUKEN table and does not change text sent to focused controls.

The capability detector reports OSC 52 support from conservative environment hints. This result does not grant clipboard access.
Set the `allowsOSC52` argument only when the application permits clipboard writes.

Pass ``TextSelectionConfiguration`` to opt in to grid-aware selection and copy on release.
The runtime copies only when support and application policy are both enabled.

Create a ``ViewOverlayHost`` and pass it to the declarative runtime initializer. Present dialogs or custom views through the host.
Use ``OverlayHost/present(_:zIndex:)`` for a toast that expires on the runtime timeline.
