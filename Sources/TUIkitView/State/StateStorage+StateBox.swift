//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StateStorage+StateBox.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - State Box

/// Type-erased reference container for a single state value.
///
/// `StateBox` is the persistent storage backing a `@State` property.
/// It is a reference type so that mutations are visible across all copies
/// of the `@State` struct (which uses `nonmutating set`).
///
/// On value change, signals a re-render through its owning runtime.
/// Cache invalidation is identity-aware: only the affected subtree is
/// cleared instead of the entire cache.
public final class StateBox<Value>: @unchecked Sendable {
  /// The identity of the view that owns this state property.
  ///
  /// Set during hydration from ``StateStorage``. Used for targeted
  /// cache invalidation via ``RenderCache/clearAffected(by:)``.
  private var identity: ViewIdentity?

  /// Runtime receiving invalidations when the value changes.
  private var invalidationSink: (any RenderInvalidationSink)?

  /// The current value.
  public var value: Value {
    didSet {
      guard let invalidationSink else { return }
      if let identity {
        invalidationSink.invalidate(.subtree(identity))
      } else {
        invalidationSink.invalidate(.all)
      }
    }
  }

  /// Creates a state box with an initial value.
  ///
  /// - Parameters:
  ///   - value: The initial value.
  ///   - identity: The identity owning this value, if known.
  ///   - invalidationSink: Runtime receiving invalidations.
  public init(
    _ value: Value,
    identity: ViewIdentity? = nil,
    invalidationSink: (any RenderInvalidationSink)? = nil
  ) {
    self.value = value
    self.identity = identity
    self.invalidationSink = invalidationSink
  }
}

// MARK: - Internal API

extension StateBox {
  /// Associates this box with the runtime and identity owning it.
  func bind(
    identity: ViewIdentity,
    invalidationSink: (any RenderInvalidationSink)?
  ) {
    self.identity = identity
    self.invalidationSink = invalidationSink
  }
}
