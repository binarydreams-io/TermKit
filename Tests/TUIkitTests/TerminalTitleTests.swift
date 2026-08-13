//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalTitleTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context sized for the terminal title tests.
private func testContext(width: Int = 40, height: Int = 10) -> RenderContext {
  RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIkit.TUIContext())
}

/// An app that declares a terminal title and quits on the first key.
@MainActor
private struct TitledApp: App {
  init() {}

  var body: some Scene {
    WindowGroup {
      Text("Content")
        .terminalTitle("Rig")
    }
  }
}

// MARK: - Terminal Title Tests

@MainActor
@Suite("Terminal Title Tests")
struct TerminalTitleTests {

  // MARK: Escape Sequences

  @Test("setWindowTitle emits the OSC 0 sequence")
  func oscSequence() {
    #expect(ANSIRenderer.setWindowTitle("Rig") == "\u{1B}]0;Rig\u{07}")
  }

  @Test("The title stack constants use the XTerm save and restore sequences")
  func titleStackConstants() {
    #expect(ANSIRenderer.pushWindowTitle == "\u{1B}[22;0t")
    #expect(ANSIRenderer.popWindowTitle == "\u{1B}[23;0t")
  }

  @Test("A terminal writes the OSC sequence for the requested title")
  func terminalWritesTheSequence() {
    let terminal = MockTerminal()
    terminal.setWindowTitle("Rig")

    #expect(terminal.writtenOutput == ["\u{1B}]0;Rig\u{07}"])
  }

  // MARK: Preference Collection

  @Test("terminalTitle preference carries the last declared title")
  func titlePreferenceWins() {
    var title: String?
    let view = VStack {
      Text("x").terminalTitle("first")
      Text("y").terminalTitle("second")
    }
    .onPreferenceChange(TerminalTitleKey.self) { title = $0 }
    _ = renderToBuffer(view, context: testContext())

    #expect(title == "second")
  }

  @Test("A view tree without a declared title reduces to no title")
  func absentTitleReducesToNil() {
    var title: String? = "stale"
    let view = VStack { Text("x") }
      .onPreferenceChange(TerminalTitleKey.self) { title = $0 }
    _ = renderToBuffer(view, context: testContext())

    #expect(title == nil)
  }

  @Test("A measurement-only render pass does not declare a title")
  func measurementPassSkipsTheTitle() {
    var title: String?
    let view = Text("x").terminalTitle("first")
      .onPreferenceChange(TerminalTitleKey.self) { title = $0 }
    var context = testContext()
    context.isMeasuring = true
    _ = renderToBuffer(view, context: context)

    #expect(title == nil)
  }

  // MARK: Per-Frame Synchronization

  @Test("The title synchronizer writes each changed value exactly once")
  func syncWritesChangedValuesOnce() {
    let terminal = MockTerminal()
    let preferences = PreferenceStorage()
    let sync = WindowTitleSync()

    declare("Rig", in: preferences, sync: sync, terminal: terminal)
    #expect(terminal.writtenOutput == [ANSIRenderer.setWindowTitle("Rig")])

    declare("Rig", in: preferences, sync: sync, terminal: terminal)
    #expect(terminal.writtenOutput == [ANSIRenderer.setWindowTitle("Rig")])

    declare("Rig — Projects", in: preferences, sync: sync, terminal: terminal)
    #expect(
      terminal.writtenOutput == [
        ANSIRenderer.setWindowTitle("Rig"),
        ANSIRenderer.setWindowTitle("Rig — Projects"),
      ]
    )
  }

  @Test("A frame that declares no title leaves the current one in place")
  func syncKeepsTitleWhenNoneDeclared() {
    let terminal = MockTerminal()
    let preferences = PreferenceStorage()
    let sync = WindowTitleSync()

    declare("Rig", in: preferences, sync: sync, terminal: terminal)
    declare(nil, in: preferences, sync: sync, terminal: terminal)

    #expect(terminal.writtenOutput == [ANSIRenderer.setWindowTitle("Rig")])
  }

  /// Runs one synchronizer frame that optionally declares a title.
  private func declare(
    _ title: String?,
    in preferences: PreferenceStorage,
    sync: WindowTitleSync,
    terminal: MockTerminal
  ) {
    preferences.beginRenderPass()
    sync.beginFrame(preferences: preferences)
    if let title {
      preferences.setValue(title, forKey: TerminalTitleKey.self)
    }
    sync.commit(to: terminal)
  }

  // MARK: Runtime

  @Test("The runtime pushes the title stack, sets the title, and pops on exit")
  func runtimePushesAndPopsTheTitle() async throws {
    let eventChannel = RuntimeEventChannel()
    let terminal = MockTerminal()
    terminal.inputEventQueue = [.key(KeyEvent(character: "q"))]
    eventChannel.send(.inputAvailable)
    let runner = AppRunner(
      app: TitledApp(),
      terminal: terminal,
      tuiContext: TUIContext(),
      eventChannel: eventChannel,
      inputSource: nil,
      signals: nil
    )

    try await runner.run()

    let output = terminal.writtenOutput
    let enter = try #require(output.firstIndex(of: ANSIRenderer.enterAlternateScreen))
    let push = try #require(output.firstIndex(of: ANSIRenderer.pushWindowTitle))
    let title = try #require(output.firstIndex(of: ANSIRenderer.setWindowTitle("Rig")))
    let pop = try #require(output.firstIndex(of: ANSIRenderer.popWindowTitle))
    let exit = try #require(output.firstIndex(of: ANSIRenderer.exitAlternateScreen))

    #expect(enter < push)
    #expect(push < title)
    #expect(title < pop)
    #expect(pop < exit)
  }
}
