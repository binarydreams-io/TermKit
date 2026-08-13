//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AppStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Storage Backend Protocol

/// Protocol for persistent storage backends.
public protocol StorageBackend: Sendable {
  /// Retrieves a value for the given key.
  func value<T: Codable>(forKey key: String) -> T?

  /// Stores a value for the given key.
  func setValue(_ value: some Codable, forKey key: String)

  /// Removes the value for the given key.
  func removeValue(forKey key: String)

  /// Synchronizes changes to disk.
  func synchronize()
}

// MARK: - Storage Defaults

/// Provides the default storage backend for ``AppStorage``.
///
/// This global compatibility hook is deprecated. `@AppStorage` properties
/// rendered inside an app bind to that app's runtime backend. Pass an explicit
/// backend to the property wrapper when code outside a runtime needs one.
///
/// ```swift
/// @AppStorage("token", storage: MyCustomBackend()) var token = ""
/// ```
public enum StorageDefaults {
  /// Backing storage retained until issue #15 removes the global fallback.
  private nonisolated(unsafe) static var configuredBackend: StorageBackend = JSONFileStorage()

  /// The default storage backend used by ``AppStorage``.
  ///
  /// Defaults to a ``JSONFileStorage`` instance that persists to
  /// `$XDG_CONFIG_HOME/[appName]/settings.json`.
  @available(*, deprecated, message: "Pass a StorageBackend to the AppStorage initializer instead")
  public static var backend: StorageBackend {
    get { configuredBackend }
    set { configuredBackend = newValue }
  }

  /// Legacy fallback used only when AppStorage is accessed outside a runtime.
  static var runtimeBackend: StorageBackend {
    configuredBackend
  }
}

// MARK: - AppStorage Property Wrapper

/// A property wrapper that reads and writes to persistent storage.
///
/// Use `@AppStorage` to persist simple values across app launches.
/// Values must conform to `Codable`.
///
/// # Example
///
/// ```swift
/// struct SettingsView: View {
///     @AppStorage("username") var username = "Guest"
///     @AppStorage("darkMode") var darkMode = false
///     @AppStorage("fontSize") var fontSize = 14
///
///     var body: some View {
///         VStack {
///             Text("User: \(username)")
///             Text("Dark Mode: \(darkMode ? "On" : "Off")")
///         }
///     }
/// }
/// ```
///
/// # Supported Types
///
/// Any type that conforms to `Codable`:
/// - String, Int, Double, Bool
/// - Date, Data, URL
/// - Arrays and Dictionaries of Codable types
/// - Custom Codable structs and enums
@propertyWrapper
public struct AppStorage<Value: Codable>: @unchecked Sendable {
  /// Reference storage that captures the first runtime owning this property.
  private let box: AppStorageBox<Value>

  /// Creates an AppStorage with the default storage backend.
  ///
  /// - Parameters:
  ///   - wrappedValue: The default value.
  ///   - key: The key to use for storage.
  public init(wrappedValue: Value, _ key: String) {
    self.box = AppStorageBox(
      key: key,
      defaultValue: wrappedValue,
      explicitStorage: nil
    )
  }

  /// Creates an AppStorage with a custom storage backend.
  ///
  /// - Parameters:
  ///   - wrappedValue: The default value.
  ///   - key: The key to use for storage.
  ///   - storage: The storage backend to use.
  public init(wrappedValue: Value, _ key: String, storage: StorageBackend) {
    self.box = AppStorageBox(
      key: key,
      defaultValue: wrappedValue,
      explicitStorage: storage
    )
  }

  /// The current value.
  public var wrappedValue: Value {
    get {
      box.value
    }
    nonmutating set {
      box.value = newValue
    }
  }

  /// A binding to the stored value.
  public var projectedValue: Binding<Value> {
    box.binding
  }
}

// MARK: - App Storage Box

/// Reference storage that binds AppStorage to its first rendering runtime.
private final class AppStorageBox<Value: Codable>: @unchecked Sendable {
  /// Persistent key.
  private let key: String

  /// Value returned when the backend contains no entry.
  private let defaultValue: Value

  /// Explicit backend supplied by the property-wrapper initializer.
  private let explicitStorage: StorageBackend?

  /// Backend captured from the owning runtime.
  private var runtimeStorage: StorageBackend?

  /// Runtime receiving changes made through this property.
  private var invalidationSink: (any RenderInvalidationSink)?

  /// Structural identity owning this property.
  private var identity: ViewIdentity?

  /// Lock protecting dependency binding.
  private let lock = NSLock()

  /// Creates reference storage for one AppStorage property.
  init(
    key: String,
    defaultValue: Value,
    explicitStorage: StorageBackend?
  ) {
    self.key = key
    self.defaultValue = defaultValue
    self.explicitStorage = explicitStorage
  }

  /// Current persisted value.
  var value: Value {
    get {
      let storage = resolvedDependencies().storage
      return storage.value(forKey: key) ?? defaultValue
    }
    set {
      let dependencies = resolvedDependencies()
      dependencies.storage.setValue(newValue, forKey: key)

      if let identity = dependencies.identity {
        dependencies.invalidationSink?.invalidate(.subtree(identity))
      } else {
        dependencies.invalidationSink?.invalidate(.all)
      }
    }
  }

  /// Binding captured while the property wrapper is hydrated by its runtime.
  var binding: Binding<Value> {
    bindToActiveRuntimeIfNeeded()
    return Binding(
      get: { self.value },
      set: { self.value = $0 }
    )
  }
}

// MARK: - Private Helpers

extension AppStorageBox {
  fileprivate typealias Dependencies = (
    storage: StorageBackend,
    invalidationSink: (any RenderInvalidationSink)?,
    identity: ViewIdentity?
  )

  private func resolvedDependencies() -> Dependencies {
    bindToActiveRuntimeIfNeeded()

    lock.lock()
    let storage = explicitStorage ?? runtimeStorage ?? StorageDefaults.runtimeBackend
    let invalidationSink = invalidationSink
    let identity = identity
    lock.unlock()
    return (storage, invalidationSink, identity)
  }

  private func bindToActiveRuntimeIfNeeded() {
    guard let environment = StateRegistration.currentEnvironment else { return }

    lock.lock()
    if runtimeStorage == nil {
      runtimeStorage = environment.storageBackend
      invalidationSink = environment.renderInvalidationSink
      identity = StateRegistration.currentContext?.identity
    }
    lock.unlock()
  }
}
