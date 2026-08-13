//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App+EventLoop.swift
//
//  Created by LAYERED.work
//  License: MIT

@MainActor
final class AppEventLoop<A: App> {
  private let appState: AppState
  private let focusManager: FocusManager
  private let terminal: any TerminalProtocol
  private let eventChannel: RuntimeEventChannel
  private var inputRetryTask: Task<Void, Never>?
  private var isInputRenderPending = false

  /// Runs after each handled input event, before the frame it may request.
  ///
  /// Terminal mode changes belong here rather than in the render pass:
  /// they are session state, not frame content.
  var onInputHandled: (() -> Void)?

  init(
    appState: AppState,
    focusManager: FocusManager,
    terminal: any TerminalProtocol,
    eventChannel: RuntimeEventChannel
  ) {
    self.appState = appState
    self.focusManager = focusManager
    self.terminal = terminal
    self.eventChannel = eventChannel
  }

  /// Serially consumes state, input, signal, and animation events.
  func processEvents(
    using inputHandler: InputHandler,
    renderer: RenderLoop<A>,
    pulseTimer: PulseTimer,
    cursorTimer: CursorTimer,
    animationScheduler: RuntimeAnimationScheduler
  ) async throws {
    try await withTaskCancellationHandler {
      var iterator = eventChannel.events.makeAsyncIterator()
      while let event = await iterator.next() {
        eventChannel.didConsume(event)
        switch event {
        case .renderRequested:
          guard appState.needsRender else { continue }
          try render(
            using: renderer,
            pulseTimer: pulseTimer,
            cursorTimer: cursorTimer,
            animationScheduler: animationScheduler
          )
        case .inputAvailable:
          if isInputRenderPending {
            eventChannel.send(.inputAvailable)
            continue
          }
          if try processNextInput(using: inputHandler), appState.needsRender {
            isInputRenderPending = true
          }
        case .terminalResized:
          renderer.invalidateDiffCache()
          try render(
            using: renderer,
            pulseTimer: pulseTimer,
            cursorTimer: cursorTimer,
            animationScheduler: animationScheduler
          )
        case .animationDeadline:
          try render(
            using: renderer,
            pulseTimer: pulseTimer,
            cursorTimer: cursorTimer,
            animationScheduler: animationScheduler
          )
        case .shutdownRequested:
          return
        }
      }
    } onCancel: { [eventChannel] in
      eventChannel.send(.shutdownRequested)
    }
  }

  /// Renders one frame and schedules only the animation work it exposes.
  func render(
    using renderer: RenderLoop<A>,
    pulseTimer: PulseTimer,
    cursorTimer: CursorTimer,
    animationScheduler: RuntimeAnimationScheduler
  ) throws {
    isInputRenderPending = false
    appState.didRender()
    renderer.render(pulsePhase: pulseTimer.phase, cursorTimer: cursorTimer)
    try throwPendingTerminalFailure()
    animationScheduler.schedule(after: nextAnimationInterval)
  }

  func cancelPendingInputRetry() {
    inputRetryTask?.cancel()
    inputRetryTask = nil
  }

  /// Throws the first terminal I/O failure exposed by the concrete terminal.
  func throwPendingTerminalFailure() throws {
    guard let failureReporter = terminal as? any TerminalFailureReporting,
          let failure = failureReporter.takeIOFailure()
    else {
      return
    }
    throw failure
  }

  /// Returns the cadence required by currently visible focus animations.
  private var nextAnimationInterval: Double? {
    if focusManager.hasTextInputFocus {
      return 0.05
    }
    if focusManager.currentFocused != nil || focusManager.activeSectionIdentifier != nil {
      return 0.1
    }
    return nil
  }

  /// Processes one event so rendering can run between repeated inputs.
  private func processNextInput(using inputHandler: InputHandler) throws -> Bool {
    cancelPendingInputRetry()

    let inputEvent = terminal.readInputEvent()
    try throwPendingTerminalFailure()
    guard let inputEvent else {
      schedulePendingInputRetry()
      return false
    }
    inputHandler.handle(inputEvent)
    onInputHandled?()

    if let scheduling = terminal as? any TerminalInputScheduling,
       scheduling.hasBufferedInput
    {
      eventChannel.send(.inputAvailable)
    }
    return true
  }

  /// Schedules one retry for an ambiguous input prefix.
  private func schedulePendingInputRetry() {
    guard let scheduling = terminal as? any TerminalInputScheduling,
          let delay = scheduling.pendingInputRetryDelay
    else {
      return
    }

    inputRetryTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self else { return }
      inputRetryTask = nil
      eventChannel.send(.inputAvailable)
    }
  }
}
