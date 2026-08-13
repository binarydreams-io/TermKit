//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoop.swift
//
//  Created by LAYERED.work
//  License: MIT  assembly, and status bar output.
//

/// Manages the full rendering pipeline for each frame.
///
/// `RenderLoop` is owned by `AppRunner` and called once per frame.
/// It orchestrates the complete render pass from `App.body` to
/// terminal output.
///
/// ## Pipeline steps (per frame)
///
/// ```
/// render()
///   1. Clear per-frame state (key handlers, preferences, focus)
///   2. Begin lifecycle tracking
///   3. Build EnvironmentValues from all subsystems
///   4. Create RenderContext with layout constraints
///   5. Evaluate App.body fresh → Scene (WindowGroup)
///      @State values bind to persistent storage at final structural identities
///   6. Call SceneRenderable.renderScene() → FrameBuffer
///   7. Convert FrameBuffer to terminal-ready output lines
///   8. Begin buffered frame (terminal.beginFrame())
///   9. Diff against previous frame, write only changed lines to buffer
///  10. Render status bar into same buffer (with its own diff tracking)
///  11. Flush the entire frame (normally one write() syscall)
///  12. End lifecycle tracking (fires onDisappear for removed views)
/// ```
///
/// ## Diff-Based Rendering
///
/// `RenderLoop` uses a `FrameDiffWriter` to compare each frame's output
/// with the previous frame. Only lines that actually changed are written
/// to the terminal, reducing I/O by ~94% for mostly-static UIs.
///
/// ## Output Buffering
///
/// All diff writes (content + status bar) are collected in `Terminal`'s
/// frame buffer and normally flushed as a single `write()` syscall via
/// `Terminal.beginFrame()` / `Terminal.endFrame()`. This reduces
/// per-frame syscalls from ~40+ to one unless the platform reports an
/// interruption or partial transfer that must be retried.
///
/// On terminal resize (SIGWINCH), the diff cache is invalidated to force
/// a full repaint.
///
/// ## Responsibilities
///
/// - Assembling ``EnvironmentValues`` from all subsystems
/// - Rendering the main scene content via `SceneRenderable`
/// - Rendering the status bar separately (never dimmed)
/// - Coordinating lifecycle tracking (appear/disappear)
/// - Diff-based terminal output via `FrameDiffWriter`
/// - Buffered frame output via `Terminal`
@MainActor
final class RenderLoop<A: App> {
  /// The user's app instance (provides `body`).
  let app: A

  /// The terminal for output and size queries.
  let terminal: any TerminalProtocol

  /// The status bar state (height, items, appearance).
  let statusBar: StatusBarState

  /// The app header state (content buffer, visibility).
  let appHeader: AppHeaderState

  /// The focus manager (cleared each frame).
  let focusManager: FocusManager

  /// The palette manager (current theme for environment).
  let paletteManager: ThemeManager

  /// The appearance manager (current border style for environment).
  let appearanceManager: ThemeManager

  /// The central dependency container (lifecycle, key dispatch, preferences).
  let tuiContext: TUIContext

  private let sceneRenderer: RenderSceneRenderer<A>

  init(
    app: A,
    terminal: any TerminalProtocol,
    statusBar: StatusBarState,
    appHeader: AppHeaderState,
    focusManager: FocusManager,
    paletteManager: ThemeManager,
    appearanceManager: ThemeManager,
    tuiContext: TUIContext
  ) {
    self.app = app
    self.terminal = terminal
    self.statusBar = statusBar
    self.appHeader = appHeader
    self.focusManager = focusManager
    self.paletteManager = paletteManager
    self.appearanceManager = appearanceManager
    self.tuiContext = tuiContext
    self.sceneRenderer = RenderSceneRenderer(
      app: app,
      terminal: terminal,
      statusBar: statusBar,
      appHeader: appHeader,
      focusManager: focusManager,
      tuiContext: tuiContext
    )
  }
}

extension RenderLoop {
  /// Performs a full render pass: scene content + status bar.
  ///
  /// See the class-level documentation for the complete pipeline steps.
  ///
  /// - Parameters:
  ///   - pulsePhase: The current breathing indicator phase (0–1).
  ///     Passed from `PulseTimer` via `AppRunner`.
  ///   - cursorTimer: The cursor timer for TextField/SecureField animations.
  func render(pulsePhase: Double = 0, cursorTimer: CursorTimer? = nil) {
    sceneRenderer.render(pulsePhase: pulsePhase, cursorTimer: cursorTimer)
  }

  /// Invalidates the diff cache, forcing a full repaint on the next render.
  ///
  /// Call this when the terminal is resized (SIGWINCH).
  func invalidateDiffCache() {
    sceneRenderer.invalidateDiffCache()
  }
}
