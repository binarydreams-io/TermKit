//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoop+Scene.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

@MainActor
final class RenderSceneRenderer<A: App> {
  private let app: A
  private let terminal: any TerminalProtocol
  private let statusBar: StatusBarState
  private let appHeader: AppHeaderState
  private let focusManager: FocusManager
  private let tuiContext: TUIContext
  private let frameWriter: RenderFrameWriter
  private var environmentTracker = RenderEnvironmentTracker()
  private let windowTitle = WindowTitleSync()
  private let clipboard: OSC52Clipboard

  /// Whether the first frame has been rendered.
  ///
  /// On the first frame, we perform a "measurement pass" to determine
  /// the actual header height before outputting anything. This prevents
  /// visible content jumping when the estimated header height differs
  /// from the actual height.
  private var isFirstFrame = true

  init(
    app: A,
    terminal: any TerminalProtocol,
    statusBar: StatusBarState,
    appHeader: AppHeaderState,
    focusManager: FocusManager,
    tuiContext: TUIContext
  ) {
    self.app = app
    self.terminal = terminal
    self.statusBar = statusBar
    self.appHeader = appHeader
    self.focusManager = focusManager
    self.tuiContext = tuiContext
    self.clipboard = OSC52Clipboard(terminal: terminal)
    self.frameWriter = RenderFrameWriter(
      terminal: terminal,
      statusBar: statusBar,
      appHeader: appHeader
    )
  }

  func render(pulsePhase: Double, cursorTimer: CursorTimer?) {
    beginRenderPass()

    // Terminal size: single getSize() call avoids 2 ioctl syscalls per frame.
    let terminalSize = terminal.getSize()
    let statusBarHeight = statusBar.height
    let terminalWidth = terminalSize.width
    let terminalHeight = terminalSize.height

    // Create render context with environment
    var environment = buildEnvironment()
    environment.pulsePhase = pulsePhase
    environment.cursorTimer = cursorTimer

    let scene = evaluateAppBody(environment: environment)
    if let paletteOverrideScene = scene as? any RootPaletteOverrideProvidingScene,
       let paletteOverride = paletteOverrideScene.rootPaletteOverride()
    {
      environment.palette = paletteOverride
    }
    environmentTracker.invalidateCacheIfChanged(environment: environment, tuiContext: tuiContext)

    // Determine header height. On the first frame, we perform a measurement
    // pass to discover the actual header height before outputting anything.
    // This prevents visible content jumping.
    let appHeaderHeight: Int
    if isFirstFrame {
      let measureContext = RenderContext(
        availableWidth: terminalWidth,
        availableHeight: terminalHeight - statusBarHeight,
        environment: environment
      )
      _ = renderScene(scene, context: measureContext.withChildIdentity(type: type(of: scene)))
      appHeaderHeight = appHeader.height
      isFirstFrame = false
    } else {
      appHeaderHeight = appHeader.estimatedHeight
    }

    let contentHeight = terminalHeight - statusBarHeight - appHeaderHeight

    var context = RenderContext(
      availableWidth: terminalWidth,
      availableHeight: contentHeight,
      environment: environment
    )
    context.hasExplicitWidth = true
    context.hasExplicitHeight = true

    var buffer = renderScene(scene, context: context.withChildIdentity(type: type(of: scene)))

    // If the header height changed after rendering, re-render with the
    // correct height so centering is accurate.
    let actualHeaderHeight = appHeader.height
    if actualHeaderHeight != appHeaderHeight {
      frameWriter.invalidate()
      let actualContentHeight = terminalHeight - statusBarHeight - actualHeaderHeight
      var correctedContext = RenderContext(
        availableWidth: terminalWidth,
        availableHeight: actualContentHeight,
        environment: environment
      )
      correctedContext.hasExplicitWidth = true
      correctedContext.hasExplicitHeight = true
      buffer = renderScene(scene, context: correctedContext.withChildIdentity(type: type(of: scene)))
    }

    focusManager.endRenderPass()

    let headerRegions = appHeader.contentBuffer?.regions ?? []
    let contentRegions = buffer.regions.map {
      InteractionRegion(
        id: $0.id,
        rect: $0.rect.translatedBy(x: 0, y: appHeader.height)
      )
    }
    tuiContext.interactionDispatcher.activate(regions: headerRegions + contentRegions)

    frameWriter.writeFrame(
      buffer: buffer,
      environment: environment,
      terminalWidth: terminalWidth,
      terminalHeight: terminalHeight,
      statusBarHeight: statusBarHeight,
      headerHeight: appHeader.height
    )

    // After the frame flush: the OSC sequence bypasses the frame buffer, so
    // writing it here keeps it out of the middle of the diffed content.
    windowTitle.commit(to: terminal)

    endRenderPass()
  }

  func invalidateDiffCache() {
    frameWriter.invalidate()
  }

  /// Clears all per-frame state and begins lifecycle/state/cache tracking.
  private func beginRenderPass() {
    tuiContext.beginRenderPass()
    windowTitle.beginFrame(preferences: tuiContext.preferences)
  }

  /// Evaluates `App.body` with hydration and environment context active.
  ///
  /// Binds the app's dynamic properties to its root identity and makes the
  /// current environment available while evaluating `body`.
  ///
  /// The evaluation runs under observation tracking, the way `renderToBuffer`
  /// tracks every `View.body`: a `WindowGroup` builds its content inside
  /// `App.body`, so an `@Observable` property the content closure reads —
  /// a root screen switch, a presented route — must request a frame when it
  /// changes. SwiftUI tracks these reads, so the parity holds here too.
  private func evaluateAppBody(environment: EnvironmentValues) -> A.Body {
    let rootIdentity = ViewIdentity(rootType: A.self)
    let context = RenderContext(
      availableWidth: 0,
      availableHeight: 0,
      environment: environment,
      identity: rootIdentity
    )
    let invalidationSink = environment.renderInvalidationSink

    let scene = StateRegistration.withHydration(of: app, context: context) {
      if let observationRegistry = environment.observationRegistry {
        observationRegistry.track(
          identity: rootIdentity,
          invalidationSink: invalidationSink
        ) {
          app.body
        }
      } else {
        withObservationTracking {
          app.body
        } onChange: {
          invalidationSink?.invalidate(.all)
        }
      }
    }
    tuiContext.stateStorage.markActive(rootIdentity)

    return scene
  }

  /// Builds a complete ``EnvironmentValues`` with all managed subsystems.
  ///
  /// The clipboard is added here, not in `TUIContext`, because it copies
  /// through this renderer's terminal.
  private func buildEnvironment() -> EnvironmentValues {
    var environment = tuiContext.environmentValues()
    environment.clipboard = clipboard
    return environment
  }

  /// Ends lifecycle, state, and cache tracking for this render pass.
  ///
  /// Fires `onDisappear` for removed views and removes state/cache
  /// entries for views no longer in the tree.
  private func endRenderPass() {
    tuiContext.endRenderPass()
  }

  /// Renders a scene by delegating to `SceneRenderable`.
  private func renderScene(_ scene: some Scene, context: RenderContext) -> FrameBuffer {
    if let renderable = scene as? SceneRenderable {
      return renderable.renderScene(context: context)
    }
    return FrameBuffer()
  }
}
