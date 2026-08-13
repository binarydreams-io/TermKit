//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TUIContext+Runtime.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal API

extension TUIContext {
  /// Creates a runtime backed by the user's persistent configuration.
  static func production() -> TUIContext {
    TUIContext(
      storageBackend: StorageDefaults.runtimeBackend,
      localizationService: LocalizationService()
    )
  }

  /// Starts a complete view render pass for this runtime.
  func beginRenderPass() {
    keyEventDispatcher.clearHandlers()
    interactionDispatcher.beginRenderPass()
    preferences.beginRenderPass()
    focusManager.beginRenderPass()
    statusBar.clearSectionItems()
    appHeader.beginRenderPass()
    statusBar.focusManager = focusManager
    lifecycle.beginRenderPass()
    stateStorage.beginRenderPass()
    observationRegistry.beginRenderPass()
    renderCache.beginRenderPass()
    applyPendingRenderInvalidations()
  }

  /// Finishes lifecycle, state, and cache tracking for a render pass.
  func endRenderPass() {
    lifecycle.endRenderPass()
    stateStorage.endRenderPass()
    observationRegistry.endRenderPass()
    renderCache.removeInactive()
    renderCache.logFrameStats()
  }

  /// Builds complete environment values for this runtime.
  func environmentValues(
    extending base: EnvironmentValues = EnvironmentValues()
  ) -> EnvironmentValues {
    var environment = base
    environment.stateStorage = stateStorage
    environment.observationRegistry = observationRegistry
    environment.lifecycle = lifecycle
    environment.keyEventDispatcher = keyEventDispatcher
    environment.interactionDispatcher = interactionDispatcher
    environment.renderCache = renderCache
    environment.renderInvalidationSink = appState
    environment.preferenceStorage = preferences
    environment.localizationService = localizationService
    environment.notificationService = notificationService
    environment.storageBackend = storageBackend
    environment.runtimeClock = clock
    environment.focusManager = focusManager
    environment.selectionMode = selectionMode
    environment.paletteManager = paletteManager
    environment.appearanceManager = appearanceManager
    environment.statusBar = statusBar
    environment.appHeader = appHeader
    environment.imageLoader = imageLoader
    environment.imageCache = imageCache

    if let palette = paletteManager.currentPalette {
      environment.palette = palette
    }
    if let appearance = appearanceManager.currentAppearance {
      environment.appearance = appearance
    }
    return environment
  }

  /// Applies cache invalidations queued by state producers.
  ///
  /// This method runs on the render owner before a frame, keeping the
  /// non-thread-safe render cache away from background state tasks.
  func applyPendingRenderInvalidations() {
    for invalidation in appState.consumePendingCacheInvalidations() {
      switch invalidation {
      case .renderOnly:
        break
      case let .subtree(identity):
        renderCache.clearAffected(by: identity)
      case .all:
        renderCache.clearAll()
      }
    }
  }

  /// Resets all services to their initial state.
  func reset() {
    appState.reset()
    lifecycle.reset()
    keyEventDispatcher.clearHandlers()
    interactionDispatcher.reset()
    preferences.reset()
    stateStorage.reset()
    observationRegistry.reset()
    renderCache.reset()
    notificationService.clear()
    focusManager.clear()
    imageCache.removeAll()
    storageBackend.synchronize()
  }
}
