//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App+Runner.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Runs an App.
///
/// `AppRunner` is the main coordinator that owns the run loop and
/// delegates to specialized managers:
/// - `SignalManager` - POSIX signal handling (SIGINT, SIGWINCH)
/// - `InputHandler` - Key event dispatch (status bar, views, defaults)
/// - `RenderLoop` — Rendering pipeline (scene + status bar)
@MainActor
final class AppRunner<A: App> {
  private let app: A
  private let appearanceManager: ThemeManager
  private let appHeader: AppHeaderState
  private let appState: AppState
  private let focusManager: FocusManager
  private let paletteManager: ThemeManager
  private let statusBar: StatusBarState
  private let terminal: any TerminalProtocol
  private let tuiContext: TUIContext
  private let eventChannel: RuntimeEventChannel
  private let inputSource: TerminalInputSource?
  private let signals: SignalManager?

  init(
    app: A,
    terminal: (any TerminalProtocol)? = nil,
    tuiContext: TUIContext? = nil,
    eventChannel: RuntimeEventChannel = RuntimeEventChannel(),
    inputSource: TerminalInputSource? = TerminalInputSource(),
    signals: SignalManager? = SignalManager()
  ) {
    let tuiContext = tuiContext ?? TUIContext.production()
    self.app = app
    self.appState = tuiContext.appState
    self.appearanceManager = tuiContext.appearanceManager
    self.appHeader = tuiContext.appHeader
    self.focusManager = tuiContext.focusManager
    self.paletteManager = tuiContext.paletteManager
    self.statusBar = tuiContext.statusBar
    statusBar.style = .bordered
    self.terminal = terminal ?? Terminal()
    self.tuiContext = tuiContext
    self.eventChannel = eventChannel
    self.inputSource = inputSource
    self.signals = signals
  }
}

extension AppRunner {
  func run() async throws {
    let runtime = AppRuntime(
      app: app,
      appearanceManager: appearanceManager,
      appHeader: appHeader,
      appState: appState,
      focusManager: focusManager,
      paletteManager: paletteManager,
      statusBar: statusBar,
      terminal: terminal,
      tuiContext: tuiContext,
      eventChannel: eventChannel,
      inputSource: inputSource,
      signals: signals
    )
    try await runtime.run()
  }
}
