//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App+Runtime.swift
//
//  Created by LAYERED.work
//  License: MIT

@MainActor
final class AppRuntime<A: App> {
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

  /// Whether the terminal currently reports mouse events to this runtime.
  ///
  /// `enableRawMode()` turns capture on at startup, so the session starts
  /// captured.
  private var isMouseCaptureEnabled = true

  init(
    app: A,
    appearanceManager: ThemeManager,
    appHeader: AppHeaderState,
    appState: AppState,
    focusManager: FocusManager,
    paletteManager: ThemeManager,
    statusBar: StatusBarState,
    terminal: any TerminalProtocol,
    tuiContext: TUIContext,
    eventChannel: RuntimeEventChannel,
    inputSource: TerminalInputSource?,
    signals: SignalManager?
  ) {
    self.app = app
    self.appearanceManager = appearanceManager
    self.appHeader = appHeader
    self.appState = appState
    self.focusManager = focusManager
    self.paletteManager = paletteManager
    self.statusBar = statusBar
    self.terminal = terminal
    self.tuiContext = tuiContext
    self.eventChannel = eventChannel
    self.inputSource = inputSource
    self.signals = signals
  }

  func run() async throws {
    let inputHandler = makeInputHandler()
    let renderer = makeRenderer()
    let pulseTimer = PulseTimer(clock: tuiContext.clock)
    let cursorTimer = CursorTimer(clock: tuiContext.clock)
    let animationScheduler = RuntimeAnimationScheduler(
      clock: tuiContext.clock,
      eventChannel: eventChannel
    )
    let eventLoop = AppEventLoop<A>(
      appState: appState,
      focusManager: focusManager,
      terminal: terminal,
      eventChannel: eventChannel
    )
    eventLoop.onInputHandled = { [weak self] in
      self?.syncMouseCapture()
    }

    await startRuntime(pulseTimer: pulseTimer, cursorTimer: cursorTimer)
    do {
      try eventLoop.throwPendingTerminalFailure()
      try eventLoop.render(
        using: renderer,
        pulseTimer: pulseTimer,
        cursorTimer: cursorTimer,
        animationScheduler: animationScheduler
      )
      try await eventLoop.processEvents(
        using: inputHandler,
        renderer: renderer,
        pulseTimer: pulseTimer,
        cursorTimer: cursorTimer,
        animationScheduler: animationScheduler
      )
    } catch {
      stopRuntime(
        pulseTimer: pulseTimer,
        cursorTimer: cursorTimer,
        animationScheduler: animationScheduler,
        eventLoop: eventLoop
      )
      throw error
    }

    stopRuntime(
      pulseTimer: pulseTimer,
      cursorTimer: cursorTimer,
      animationScheduler: animationScheduler,
      eventLoop: eventLoop
    )
    try eventLoop.throwPendingTerminalFailure()
  }

  /// Creates the runtime's input dispatcher.
  private func makeInputHandler() -> InputHandler {
    InputHandler(
      statusBar: statusBar,
      keyEventDispatcher: tuiContext.keyEventDispatcher,
      interactionDispatcher: tuiContext.interactionDispatcher,
      focusManager: focusManager,
      paletteManager: paletteManager,
      appearanceManager: appearanceManager,
      onQuit: { [eventChannel] in
        eventChannel.send(.shutdownRequested)
      }
    )
  }

  /// Creates the runtime's renderer.
  private func makeRenderer() -> RenderLoop<A> {
    RenderLoop(
      app: app,
      terminal: terminal,
      statusBar: statusBar,
      appHeader: appHeader,
      focusManager: focusManager,
      paletteManager: paletteManager,
      appearanceManager: appearanceManager,
      tuiContext: tuiContext
    )
  }

  /// Installs event sources and prepares the terminal session.
  private func startRuntime(pulseTimer: PulseTimer, cursorTimer: CursorTimer) async {
    if let signals {
      await signals.install(sendingTo: eventChannel)
    }
    inputSource?.start(sendingTo: eventChannel)
    terminal.enterAlternateScreen()
    // Save the terminal's own title before any view declares one, so
    // `cleanup()` can restore it even when the app exits through an error.
    terminal.write(ANSIRenderer.pushWindowTitle)
    terminal.hideCursor()
    terminal.enableRawMode()

    appState.observe { [eventChannel] in
      eventChannel.send(.renderRequested)
    }
    let runtimeFocusChangeHandler = focusManager.onFocusChange
    focusManager.onFocusChange = { [weak pulseTimer] in
      pulseTimer?.reset()
      runtimeFocusChangeHandler?()
    }
    pulseTimer.start()
    cursorTimer.start()
  }

  /// Matches terminal mouse capture to the current selection mode.
  ///
  /// Runs after input handling instead of during a render pass: capture is
  /// terminal session state, and its escape sequence must not interleave
  /// with the diffed frame. `cleanup()` restores the terminal through
  /// `disableRawMode()`, so an active selection mode cannot survive exit.
  private func syncMouseCapture() {
    let shouldCapture = !tuiContext.selectionMode.isActive
    guard shouldCapture != isMouseCaptureEnabled else { return }

    isMouseCaptureEnabled = shouldCapture
    terminal.setMouseCaptureEnabled(shouldCapture)
  }

  /// Cancels runtime work and restores the terminal deterministically.
  private func stopRuntime(
    pulseTimer: PulseTimer,
    cursorTimer: CursorTimer,
    animationScheduler: RuntimeAnimationScheduler,
    eventLoop: AppEventLoop<A>
  ) {
    animationScheduler.stop()
    pulseTimer.stop()
    cursorTimer.stop()
    eventLoop.cancelPendingInputRetry()
    inputSource?.stop()
    signals?.stop()
    eventChannel.finish()
    cleanup()
  }

  private func cleanup() {
    terminal.disableRawMode()
    terminal.showCursor()
    terminal.write(ANSIRenderer.popWindowTitle)
    terminal.exitAlternateScreen()
    appState.clearObservers()
    focusManager.clear()
    tuiContext.reset()
  }
}
