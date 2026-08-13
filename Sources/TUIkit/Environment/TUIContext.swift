//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TUIContext.swift
//
//  Created by LAYERED.work
//  License: MIT  Owned by AppRunner and threaded through RenderContext.
//

import Foundation

// MARK: - TUI Context

/// Central dependency container for TUIkit runtime services.
///
/// `TUIContext` bundles all framework-internal services into a single
/// object owned by `AppRunner`. It is threaded through `RenderContext`
/// so that view modifiers can access services during rendering.
///
/// ## Services
///
/// - ``lifecycle``: View lifecycle tracking (appear/disappear/task)
/// - ``keyEventDispatcher``: Key event handler registration and dispatch
/// - ``interactionDispatcher``: Mouse interaction registration and dispatch
/// - ``preferences``: Preference value collection during rendering
/// - ``stateStorage``: Persistent `@State` value storage indexed by view identity
///
/// ## Usage
///
/// View modifiers access services through `RenderContext.environment`:
///
/// ```swift
/// extension MyModifier: Renderable {
///     func renderToBuffer(context: RenderContext) -> FrameBuffer {
///         context.environment.keyEventDispatcher!.addHandler { event in
///             // handle key
///         }
///         return TUIkit.renderToBuffer(content, context: context)
///     }
/// }
/// ```
@MainActor
final class TUIContext {
  /// Thread-safe render state and invalidation sink owned by this runtime.
  let appState: AppState

  /// View lifecycle tracking (appear, disappear, task management).
  let lifecycle: LifecycleManager

  /// Key event handler registration and dispatch.
  let keyEventDispatcher: KeyEventDispatcher

  /// Mouse interaction registration and dispatch.
  let interactionDispatcher: InteractionDispatcher

  /// Preference value collection during rendering.
  let preferences: PreferenceStorage

  /// Persistent `@State` value storage indexed by `ViewIdentity`.
  let stateStorage: StateStorage

  /// Identity-bound Observation registrations for this runtime.
  let observationRegistry: ObservationRegistry

  /// Cache for memoized subtree rendering results.
  ///
  /// Stores rendered ``FrameBuffer`` output for ``EquatableView`` instances,
  /// keyed by `ViewIdentity`. Cleared on every `@State` change; entries
  /// for removed views are garbage-collected at the end of each render pass.
  let renderCache: RenderCache

  /// Localization state owned by this runtime.
  let localizationService: LocalizationService

  /// Notification queue owned by this runtime.
  let notificationService: NotificationService

  /// Persistent application storage owned by this runtime.
  let storageBackend: StorageBackend

  /// Clock used by time-based views and services.
  let clock: RuntimeClock

  /// Keyboard focus state owned by this runtime.
  let focusManager: FocusManager

  /// Whether the terminal owns the mouse instead of this runtime.
  let selectionMode = SelectionModeState()

  /// Color palette selection owned by this runtime.
  let paletteManager: ThemeManager

  /// Border appearance selection owned by this runtime.
  let appearanceManager: ThemeManager

  /// Status bar state owned by this runtime.
  let statusBar: StatusBarState

  /// Application header state owned by this runtime.
  let appHeader: AppHeaderState

  /// Image loader used by this runtime.
  let imageLoader: any ImageLoader

  /// URL image cache owned by this runtime.
  let imageCache: URLImageCache

  /// Creates a new isolated TUI context with injectable services.
  ///
  /// Every omitted service is created fresh, so contexts do not share state,
  /// caches, or service instances. Tests can inject deterministic substitutes.
  ///
  /// - Parameters:
  ///   - appState: The render state and invalidation sink to use.
  ///   - lifecycle: The lifecycle manager to use.
  ///   - keyEventDispatcher: The key event dispatcher to use.
  ///   - interactionDispatcher: The mouse interaction dispatcher to use.
  ///   - preferences: The preference storage to use.
  ///   - stateStorage: The state storage to use.
  ///   - observationRegistry: The Observation registry to use.
  ///   - renderCache: The render cache to use.
  ///   - storageBackend: The AppStorage backend to use.
  ///   - localizationService: Optional localization service to adopt.
  ///   - notificationService: Optional notification service to adopt.
  ///   - clock: Clock used by time-based services.
  ///   - focusManager: Focus state to use.
  ///   - appHeader: Application header state to use.
  ///   - imageLoader: Loader for file and URL image requests.
  ///   - imageCache: Cache for URL image results.
  nonisolated init(
    appState: AppState = AppState(),
    lifecycle: LifecycleManager = LifecycleManager(),
    keyEventDispatcher: KeyEventDispatcher = KeyEventDispatcher(),
    interactionDispatcher: InteractionDispatcher = InteractionDispatcher(),
    preferences: PreferenceStorage = PreferenceStorage(),
    stateStorage: StateStorage = StateStorage(),
    observationRegistry: ObservationRegistry = ObservationRegistry(),
    renderCache: RenderCache = RenderCache(),
    storageBackend: StorageBackend = VolatileStorageBackend(),
    localizationService: LocalizationService? = nil,
    notificationService: NotificationService? = nil,
    clock: RuntimeClock = .system,
    focusManager: FocusManager = FocusManager(),
    appHeader: AppHeaderState = AppHeaderState(),
    imageLoader: any ImageLoader = PlatformImageLoader(),
    imageCache: URLImageCache = URLImageCache()
  ) {
    let localizationService = localizationService ?? LocalizationService.transient()
    let notificationService = notificationService ?? NotificationService()

    localizationService.setInvalidationSink(appState)
    notificationService.setRuntimeDependencies(
      clock: clock,
      invalidationSink: appState
    )
    stateStorage.setInvalidationSink(appState)
    let existingFocusChangeHandler = focusManager.onFocusChange
    focusManager.onFocusChange = { [appState] in
      existingFocusChangeHandler?()
      appState.setNeedsRender()
    }

    self.appState = appState
    self.lifecycle = lifecycle
    self.keyEventDispatcher = keyEventDispatcher
    self.interactionDispatcher = interactionDispatcher
    self.preferences = preferences
    self.stateStorage = stateStorage
    self.observationRegistry = observationRegistry
    self.renderCache = renderCache
    self.localizationService = localizationService
    self.notificationService = notificationService
    self.storageBackend = storageBackend
    self.clock = clock
    self.focusManager = focusManager
    self.paletteManager = ThemeManager(
      items: PaletteRegistry.all,
      renderTrigger: { [appState] in appState.setNeedsRender() }
    )
    self.appearanceManager = ThemeManager(
      items: AppearanceRegistry.all,
      renderTrigger: { [appState] in appState.setNeedsRender() }
    )
    self.statusBar = StatusBarState(appState: appState)
    self.appHeader = appHeader
    self.imageLoader = imageLoader
    self.imageCache = imageCache
  }
}
