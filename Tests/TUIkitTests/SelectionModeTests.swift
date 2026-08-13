//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SelectionModeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// A clipboard that records copied text instead of writing to a terminal.
@MainActor
private final class RecordingClipboard: ClipboardWriting {
  private(set) var copied: [String] = []

  func copy(_ text: String) {
    copied.append(text)
  }
}

/// Creates a render context that resolves services from `tuiContext`.
@MainActor
private func testContext(
  _ tuiContext: TUIContext,
  clipboard: (any ClipboardWriting)? = nil
) -> RenderContext {
  var environment = tuiContext.environmentValues()
  if let clipboard {
    environment.clipboard = clipboard
  }
  return RenderContext(availableWidth: 40, availableHeight: 10, environment: environment)
}

/// Presses and releases the left button over a region's origin.
@MainActor
private func click(_ region: InteractionRegion, dispatcher: InteractionDispatcher) {
  _ = dispatcher.dispatch(
    MouseEvent(action: .press(.left), column: region.rect.x, row: region.rect.y)
  )
  _ = dispatcher.dispatch(
    MouseEvent(action: .release(.left), column: region.rect.x, row: region.rect.y)
  )
}

/// A view that toggles selection mode from the environment on "s".
private struct SelectionToggleView: View {
  @Environment(\.selectionMode) private var selectionMode

  var body: some View {
    Text("Content")
      .onKeyPress { [selectionMode] event in
        guard event.key == .character("s") else { return false }
        selectionMode.isActive.toggle()
        return true
      }
  }
}

/// An app whose content can switch the runtime into selection mode.
@MainActor
private struct SelectionApp: App {
  init() {}

  var body: some Scene {
    WindowGroup {
      SelectionToggleView()
    }
  }
}

// MARK: - Selection Mode Tests

@MainActor
@Suite("Selection Mode Tests")
struct SelectionModeTests {

  // MARK: Mouse Capture

  @Test("Mouse capture toggle writes the enable and disable sequences")
  func captureToggleWritesSequences() {
    let terminal = MockTerminal()
    terminal.enableRawMode()

    terminal.setMouseCaptureEnabled(false)
    #expect(terminal.writtenOutput.contains("\u{1B}[?1000l\u{1B}[?1006l"))

    terminal.setMouseCaptureEnabled(true)
    #expect(terminal.writtenOutput.contains("\u{1B}[?1000h\u{1B}[?1006h"))
  }

  @Test("Selection mode starts inactive")
  func selectionModeStartsInactive() {
    #expect(SelectionModeState().isActive == false)
  }

  @Test("The runtime releases mouse capture while selection mode is active")
  func runtimeReleasesCaptureForSelectionMode() async throws {
    let eventChannel = RuntimeEventChannel()
    let terminal = MockTerminal()
    terminal.inputEventQueue = [
      .key(KeyEvent(character: "s")),
      .key(KeyEvent(character: "q")),
    ]
    eventChannel.send(.inputAvailable)
    let runner = AppRunner(
      app: SelectionApp(),
      terminal: terminal,
      tuiContext: TUIContext(),
      eventChannel: eventChannel,
      inputSource: nil,
      signals: nil
    )

    try await runner.run()

    #expect(terminal.writtenOutput.contains(ANSIRenderer.disableMouseCapture))
  }

  @Test("An input event that leaves selection mode unchanged writes no capture sequence")
  func unchangedSelectionModeWritesNoCaptureSequence() async throws {
    let eventChannel = RuntimeEventChannel()
    let terminal = MockTerminal()
    terminal.inputEventQueue = [.key(KeyEvent(character: "q"))]
    eventChannel.send(.inputAvailable)
    let runner = AppRunner(
      app: SelectionApp(),
      terminal: terminal,
      tuiContext: TUIContext(),
      eventChannel: eventChannel,
      inputSource: nil,
      signals: nil
    )

    try await runner.run()

    #expect(terminal.writtenOutput.contains(ANSIRenderer.enableMouseCapture) == false)
    #expect(terminal.writtenOutput.contains(ANSIRenderer.disableMouseCapture) == false)
  }

  @Test("Turning selection mode off restores mouse capture")
  func selectionModeOffRestoresCapture() async throws {
    let eventChannel = RuntimeEventChannel()
    let terminal = MockTerminal()
    terminal.inputEventQueue = [
      .key(KeyEvent(character: "s")),
      .key(KeyEvent(character: "s")),
      .key(KeyEvent(character: "q")),
    ]
    eventChannel.send(.inputAvailable)
    let runner = AppRunner(
      app: SelectionApp(),
      terminal: terminal,
      tuiContext: TUIContext(),
      eventChannel: eventChannel,
      inputSource: nil,
      signals: nil
    )

    try await runner.run()

    #expect(terminal.writtenOutput.contains(ANSIRenderer.disableMouseCapture))
    #expect(terminal.writtenOutput.contains(ANSIRenderer.enableMouseCapture))
  }

  // MARK: OSC 52 Clipboard

  @Test("OSC 52 clipboard encodes the payload as base64")
  func clipboardEncodesBase64() {
    let terminal = MockTerminal()

    OSC52Clipboard(terminal: terminal).copy("path")

    #expect(terminal.writtenOutput.contains { $0.contains("]52;c;cGF0aA==") })
  }

  @Test("OSC 52 clipboard encodes the UTF-8 bytes of the text")
  func clipboardEncodesUTF8Bytes() {
    let terminal = MockTerminal()

    OSC52Clipboard(terminal: terminal).copy("café")

    #expect(terminal.writtenOutput == ["\u{1B}]52;c;Y2Fmw6k=\u{07}"])
  }

  // MARK: Copy On Click

  @Test("copyOnClick registers a click region")
  func copyOnClickRegistersRegion() {
    let tuiContext = TUIContext()
    tuiContext.beginRenderPass()

    let buffer = renderToBuffer(Text("~/x").copyOnClick("~/x"), context: testContext(tuiContext))

    #expect(buffer.regions.contains { $0.id.hasPrefix("copy-on-click-") })
  }

  @Test("A click on copyOnClick content copies the text and posts a toast")
  func copyOnClickClickCopiesText() throws {
    let tuiContext = TUIContext()
    let clipboard = RecordingClipboard()
    tuiContext.beginRenderPass()
    let buffer = renderToBuffer(
      Text("~/x").copyOnClick("~/Projects/Rig"),
      context: testContext(tuiContext, clipboard: clipboard)
    )
    tuiContext.interactionDispatcher.activate(regions: buffer.regions)
    let region = try #require(buffer.regions.first { $0.id.hasPrefix("copy-on-click-") })

    click(region, dispatcher: tuiContext.interactionDispatcher)

    #expect(clipboard.copied == ["~/Projects/Rig"])
    #expect(tuiContext.notificationService.activeEntries().map(\.message) == ["Copied"])
  }

  @Test("A measurement-only render pass registers no copy region")
  func copyOnClickSkipsMeasurementPass() {
    let tuiContext = TUIContext()
    tuiContext.beginRenderPass()
    var context = testContext(tuiContext)
    context.isMeasuring = true

    let buffer = renderToBuffer(Text("~/x").copyOnClick("~/x"), context: context)

    #expect(buffer.regions.isEmpty)
  }

  @Test("A click on an interactive child wins over the surrounding copy region")
  func copyOnClickYieldsToInteractiveChildren() throws {
    let tuiContext = TUIContext()
    let clipboard = RecordingClipboard()
    var openCount = 0
    tuiContext.beginRenderPass()
    let buffer = renderToBuffer(
      HStack {
        Button("Open") { openCount += 1 }.focusID("open")
        Text(" ~/Projects/Rig")
      }
      .copyOnClick("~/Projects/Rig"),
      context: testContext(tuiContext, clipboard: clipboard)
    )
    tuiContext.focusManager.endRenderPass()
    tuiContext.interactionDispatcher.activate(regions: buffer.regions)
    let buttonRegion = try #require(buffer.regions.first { $0.id.contains("open") })

    // A click on the button hits the button, not the copy region behind it.
    click(buttonRegion, dispatcher: tuiContext.interactionDispatcher)
    #expect(openCount == 1)
    #expect(clipboard.copied.isEmpty)

    // A click past the button but still inside the content copies as usual.
    let outsideColumn = buttonRegion.rect.maxX
    _ = tuiContext.interactionDispatcher.dispatch(
      MouseEvent(action: .press(.left), column: outsideColumn, row: buttonRegion.rect.y)
    )
    _ = tuiContext.interactionDispatcher.dispatch(
      MouseEvent(action: .release(.left), column: outsideColumn, row: buttonRegion.rect.y)
    )
    #expect(clipboard.copied == ["~/Projects/Rig"])
  }
}
