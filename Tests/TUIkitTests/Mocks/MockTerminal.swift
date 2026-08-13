//  TUIKit - Terminal UI Kit for Swift
//  MockTerminal.swift
//
//  Created by LAYERED.work
//  License: MIT

@testable import TUIkit

/// A mock terminal for testing that captures output and simulates input.
///
/// `MockTerminal` implements ``TerminalProtocol`` without performing actual
/// terminal I/O. Use it to:
/// - Capture rendered output for verification
/// - Simulate key events for testing input handling
/// - Control terminal size for layout tests
///
/// ## Example
///
/// ```swift
/// @Test func rendersCorrectOutput() async {
///     let terminal = MockTerminal()
///     terminal.size = (80, 24)
///
///     // ... render something using terminal ...
///
///     #expect(terminal.writtenOutput.contains("Expected text"))
/// }
///
/// @Test func handlesKeyPress() async {
///     let terminal = MockTerminal()
///     terminal.keyEventQueue = [KeyEvent(key: .enter)]
///
///     let event = terminal.readKeyEvent()
///     #expect(event?.key == .enter)
/// }
/// ```
@MainActor
final class MockTerminal: TerminalProtocol, TerminalFailureReporting, TerminalInputScheduling {
    /// The simulated terminal size.
    var size: (width: Int, height: Int) = (80, 24)

    /// All strings written via ``write(_:)``.
    private(set) var writtenOutput: [String] = []

    /// Key events to return from ``readKeyEvent()``.
    ///
    /// Events are removed from the front of the queue as they are read.
    var keyEventQueue: [KeyEvent] = []

    /// Keyboard and mouse events returned before ``keyEventQueue``.
    var inputEventQueue: [InputEvent] = []

    /// Empty reads to return before queued input becomes available.
    var deferredInputReadCount = 0

    /// Retry delay exposed while an input read is deferred.
    var inputRetryDelay: Duration?

    /// Called before each input read to coordinate runtime-event tests.
    var onReadInputEvent: (() -> Void)?

    /// Whether raw mode is currently enabled.
    private(set) var isRawModeEnabled = false

    /// Whether mouse reporting is currently enabled.
    private(set) var isMouseCaptureEnabled = false

    /// Whether the cursor is currently hidden.
    private(set) var isCursorHidden = false

    /// Whether we are in the alternate screen buffer.
    private(set) var isInAlternateScreen = false

    /// The current cursor position (row, column), 1-based.
    private(set) var cursorPosition: (row: Int, column: Int) = (1, 1)

    /// Whether frame buffering is active.
    private var isBuffering = false

    /// A terminal I/O failure waiting for the runtime to consume it.
    var pendingIOFailure: TerminalIOFailure?

    /// Buffer for collecting writes during a frame.
    private var frameBuffer: [String] = []

    /// Creates a new mock terminal with default settings.
    init() {}
}

// MARK: - TerminalProtocol

extension MockTerminal {
    func getSize() -> (width: Int, height: Int) {
        size
    }

    func write(_ string: String) {
        if isBuffering {
            frameBuffer.append(string)
        } else {
            writtenOutput.append(string)
        }
    }

    func readKeyEvent() -> KeyEvent? {
        guard !keyEventQueue.isEmpty else { return nil }
        return keyEventQueue.removeFirst()
    }

    func readInputEvent() -> InputEvent? {
        onReadInputEvent?()
        if deferredInputReadCount > 0 {
            deferredInputReadCount -= 1
            return nil
        }
        if inputEventQueue.isEmpty == false {
            inputRetryDelay = nil
            return inputEventQueue.removeFirst()
        }
        let event = readKeyEvent().map(InputEvent.key)
        if event != nil {
            inputRetryDelay = nil
        }
        return event
    }

    func enableRawMode() {
        isRawModeEnabled = true
        isMouseCaptureEnabled = true
    }

    func disableRawMode() {
        isRawModeEnabled = false
        isMouseCaptureEnabled = false
    }

    func beginFrame() {
        guard !isBuffering else { return }
        isBuffering = true
        frameBuffer.removeAll()
    }

    func endFrame() {
        guard isBuffering else { return }
        isBuffering = false
        writtenOutput.append(contentsOf: frameBuffer)
        frameBuffer.removeAll()
    }

    func moveCursor(toRow row: Int, column: Int) {
        cursorPosition = (row, column)
        write(ANSIRenderer.moveCursor(toRow: row, column: column))
    }

    func hideCursor() {
        isCursorHidden = true
        write(ANSIRenderer.hideCursor)
    }

    func showCursor() {
        isCursorHidden = false
        write(ANSIRenderer.showCursor)
    }

    func enterAlternateScreen() {
        isInAlternateScreen = true
        write(ANSIRenderer.enterAlternateScreen)
    }

    func exitAlternateScreen() {
        isInAlternateScreen = false
        write(ANSIRenderer.exitAlternateScreen)
    }

    func setWindowTitle(_ title: String) {
        // Mirrors `Terminal.setWindowTitle`, which writes immediately and
        // therefore never lands in the frame buffer.
        writtenOutput.append(ANSIRenderer.setWindowTitle(title))
    }

    func setMouseCaptureEnabled(_ enabled: Bool) {
        // Recorded unconditionally: unlike the real terminal, the mock has
        // no raw session to gate on, so tests see every requested change.
        isMouseCaptureEnabled = enabled
        writtenOutput.append(
            enabled ? ANSIRenderer.enableMouseCapture : ANSIRenderer.disableMouseCapture
        )
    }

    func takeIOFailure() -> TerminalIOFailure? {
        defer { pendingIOFailure = nil }
        return pendingIOFailure
    }

    var hasBufferedInput: Bool {
        inputEventQueue.isEmpty == false || keyEventQueue.isEmpty == false
    }

    var pendingInputRetryDelay: Duration? {
        inputRetryDelay
    }
}

// MARK: - Test Helpers

extension MockTerminal {
    /// Resets all state to defaults.
    func reset() {
        writtenOutput.removeAll()
        keyEventQueue.removeAll()
        inputEventQueue.removeAll()
        deferredInputReadCount = 0
        inputRetryDelay = nil
        onReadInputEvent = nil
        frameBuffer.removeAll()
        isRawModeEnabled = false
        isMouseCaptureEnabled = false
        isCursorHidden = false
        isInAlternateScreen = false
        isBuffering = false
        pendingIOFailure = nil
        cursorPosition = (1, 1)
        size = (80, 24)
    }

    /// Returns all written output joined as a single string.
    var allOutput: String {
        writtenOutput.joined()
    }

    /// Checks if any written output contains the given substring.
    func outputContains(_ substring: String) -> Bool {
        writtenOutput.contains { $0.contains(substring) }
    }
}
