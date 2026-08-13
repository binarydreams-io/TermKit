//  🖥️ TUIKit — Terminal UI Kit for Swift
//  State+Registration.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Hydration Context

/// The render context used to bind dynamic properties to runtime storage.
///
/// Created by `renderToBuffer(_:context:)` after a view reaches its final
/// structural position and before evaluating that view's `body`.
public struct HydrationContext: Sendable {
  /// The current view's structural identity.
  public let identity: ViewIdentity

  /// The persistent state storage.
  public let storage: StateStorage

  /// The runtime that owns state created in this context.
  public let invalidationSink: (any RenderInvalidationSink)?

  /// Creates a new hydration context.
  public init(
    identity: ViewIdentity,
    storage: StateStorage,
    invalidationSink: (any RenderInvalidationSink)? = nil
  ) {
    self.identity = identity
    self.storage = storage
    self.invalidationSink = invalidationSink
  }
}

// MARK: - Runtime Dynamic Property

/// Internal binding contract for property wrappers that need their committed
/// view identity before `body` is evaluated.
package protocol RuntimeDynamicProperty {
  /// Binds the property to one stable slot on the final structural identity.
  func bind(to context: HydrationContext, propertyIndex: Int)
}

// MARK: - State Registration

/// Framework-internal context for dynamic-property and environment evaluation.
///
/// The renderer first reflects the owning view's dynamic properties and binds
/// them to its final structural identity. Ambient context remains available
/// while evaluating `body` for environment-backed construction APIs.
public enum StateRegistration {
  /// Dynamically scoped hydration context used by production rendering.
  @TaskLocal package static var runtimeContext: HydrationContext?

  /// Dynamically scoped environment used by production rendering.
  @TaskLocal package static var runtimeEnvironment: EnvironmentValues?

  /// The active hydration context, set during composite view body evaluation.
  ///
  /// Legacy mutable fallback retained for source compatibility. Production
  /// rendering uses `runtimeContext` instead.
  public nonisolated(unsafe) static var activeContext: HydrationContext?

  /// Legacy ambient property counter retained for source compatibility.
  ///
  /// Runtime `State` binding derives indices from reflected property order and
  /// does not use this value.
  public nonisolated(unsafe) static var counter: Int = 0

  /// The active environment values, set during composite view body evaluation.
  ///
  /// Used by `@Environment` to read environment values during `body` evaluation.
  /// Legacy mutable fallback retained for source compatibility. Production
  /// rendering uses `runtimeEnvironment` instead.
  public nonisolated(unsafe) static var activeEnvironment: EnvironmentValues?

  /// Current dynamically scoped context, including the compatibility fallback.
  package static var currentContext: HydrationContext? {
    runtimeContext ?? activeContext
  }

  /// Current dynamically scoped environment, including the compatibility fallback.
  package static var currentEnvironment: EnvironmentValues? {
    runtimeEnvironment ?? activeEnvironment
  }

  /// Evaluates a closure with a hydration context active.
  ///
  /// Installs task-local runtime context and environment values while
  /// calling the closure, then restores the enclosing scope. This pattern
  /// is needed whenever `view.body` is evaluated outside the normal
  /// `renderToBuffer` dispatch (e.g., in `measureChild`).
  ///
  /// - Parameters:
  ///   - context: The render context providing identity and environment.
  ///   - block: The closure to execute with hydration active.
  /// - Returns: The result of the closure.
  public static func withHydration<R>(
    context: RenderContext,
    _ block: () -> R
  ) -> R {
    withHydration(owner: nil, context: context, block)
  }

  /// Evaluates a view or app body after binding its dynamic properties to
  /// the final structural identity supplied by the renderer.
  package static func withHydration<R>(
    of owner: some Any,
    context: RenderContext,
    _ block: () -> R
  ) -> R {
    withHydration(owner: owner, context: context, block)
  }

  /// Binds direct dynamic-property fields for tests and specialized runtime paths.
  package static func bindDynamicProperties(
    in owner: some Any,
    context: HydrationContext
  ) {
    var propertyIndex = 0
    var mirror: Mirror? = Mirror(reflecting: owner)

    while let currentMirror = mirror {
      for child in currentMirror.children {
        guard let property = child.value as? any RuntimeDynamicProperty else { continue }
        property.bind(to: context, propertyIndex: propertyIndex)
        propertyIndex += 1
      }
      mirror = currentMirror.superclassMirror
    }
  }

  private static func withHydration<R>(
    owner: Any?,
    context: RenderContext,
    _ block: () -> R
  ) -> R {
    let hydrationContext = context.environment.stateStorage.map {
      HydrationContext(
        identity: context.identity,
        storage: $0,
        invalidationSink: context.environment.renderInvalidationSink
      )
    }

    return $runtimeContext.withValue(hydrationContext) {
      $runtimeEnvironment.withValue(context.environment) {
        if let owner, let hydrationContext {
          bindDynamicProperties(in: owner, context: hydrationContext)
        }
        return block()
      }
    }
  }
}
