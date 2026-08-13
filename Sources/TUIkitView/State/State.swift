//  🖥️ TUIKit — Terminal UI Kit for Swift
//  State.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - App State

/// Application state that triggers re-renders when modified.
///
/// `AppState` is thread-safe: ``setNeedsRender()`` can be called from any thread.
/// Internal state is protected by an `NSLock`.
///
/// The `AppRunner` subscribes to state changes and re-renders when notified.
/// Property wrappers route changes to the runtime-owned instance through
/// ``RenderInvalidationSink``.
///
/// - Important: This is framework infrastructure. Prefer using ``State`` for reactive state
///   management in your views. Direct use of `AppState` is only necessary in advanced scenarios
///   where you manage state outside the view hierarchy.
public final class AppState: Sendable {
  /// Internal state protected by a lock.
  private struct StateData: Sendable {
    var needsRender = false
    var invalidatesAllCachedOutput = false
    var invalidatedSubtrees: Set<ViewIdentity> = []
    var observers: [@Sendable () -> Void] = []
  }

  /// Lock protecting all mutable state.
  private let lock = Lock(initialState: StateData())

  /// Creates a new app state instance.
  public init() {}
}

// MARK: - Public API

extension AppState {
  /// Marks state as changed and notifies observers.
  ///
  /// This method is thread-safe and can be called from any thread.
  ///
  /// Callers that change visual output (theme, palette, appearance) do
  /// **not** need to manually clear the render cache. `RenderLoop`
  /// automatically detects environment changes via `EnvironmentSnapshot`
  /// comparison and clears the cache when needed.
  public func setNeedsRender() {
    invalidate(.renderOnly)
  }

  /// Marks state as changed and requests a full cache clear on next render.
  ///
  /// Called by `withObservationTracking` when an `@Observable` property
  /// changes. Unlike ``setNeedsRender()``, this also sets a flag that tells
  /// the render loop to clear the entire render cache, ensuring cached
  /// `EquatableView` subtrees re-render with the new model data.
  ///
  /// Thread-safe: can be called from any thread.
  public func setNeedsRenderWithCacheClear() {
    invalidate(.all)
  }
}

// MARK: - Internal API

extension AppState {
  /// Whether state has changed since last render.
  public var needsRender: Bool {
    lock.withLock { $0.needsRender }
  }

  /// Registers an observer to be notified of state changes.
  ///
  /// - Parameter callback: The callback to invoke on state change.
  public func observe(_ callback: @escaping @Sendable () -> Void) {
    lock.withLock { state in
      state.observers.append(callback)
    }
  }

  /// Clears all observers.
  public func clearObservers() {
    lock.withLock { state in
      state.observers.removeAll()
    }
  }

  /// Resets the needs render flag.
  public func didRender() {
    lock.withLock { state in
      state.needsRender = false
    }
  }

  /// Consumes pending cache invalidations.
  ///
  /// Called by the render loop at the start of each frame. Returns `true`
  /// The returned invalidations are applied by the owning runtime on the
  /// main actor before rendering. Render-only requests are represented by
  /// an empty array because they do not affect cached output.
  public func consumePendingCacheInvalidations() -> [RenderInvalidation] {
    lock.withLock { state in
      if state.invalidatesAllCachedOutput {
        state.invalidatesAllCachedOutput = false
        state.invalidatedSubtrees.removeAll(keepingCapacity: true)
        return [.all]
      }

      let invalidations = state.invalidatedSubtrees.map(RenderInvalidation.subtree)
      state.invalidatedSubtrees.removeAll(keepingCapacity: true)
      return invalidations
    }
  }

  /// Consumes pending invalidations and reports whether a full cache clear was requested.
  ///
  /// Prefer ``consumePendingCacheInvalidations()`` when subtree invalidations
  /// must be preserved.
  public func consumeNeedsCacheClear() -> Bool {
    consumePendingCacheInvalidations().contains { invalidation in
      if case .all = invalidation {
        return true
      }
      return false
    }
  }

  /// Clears render flags, pending invalidations, and observers.
  public func reset() {
    lock.withLock { state in
      state.needsRender = false
      state.invalidatesAllCachedOutput = false
      state.invalidatedSubtrees.removeAll()
      state.observers.removeAll()
    }
  }
}

// MARK: - Render Invalidation Sink

extension AppState: RenderInvalidationSink {
  public func invalidate(_ invalidation: RenderInvalidation) {
    let observers = lock.withLock { state -> [@Sendable () -> Void] in
      state.needsRender = true

      switch invalidation {
      case .renderOnly:
        break
      case let .subtree(identity):
        if !state.invalidatesAllCachedOutput {
          state.invalidatedSubtrees.insert(identity)
        }
      case .all:
        state.invalidatesAllCachedOutput = true
        state.invalidatedSubtrees.removeAll(keepingCapacity: true)
      }

      return state.observers
    }

    // Call observers outside the lock to avoid potential deadlocks.
    for observer in observers {
      observer()
    }
  }
}
