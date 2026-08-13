//  🖥️ TUIKit — Terminal UI Kit for Swift
//  State+PropertyWrappers.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Binding

/// A two-way connection to a mutable value.
///
/// `Binding` provides read and write access to a value owned elsewhere.
/// Use bindings to connect interactive views to state.
///
/// # Example
///
/// ```swift
/// struct ContentView: View {
///     @State var selectedIndex = 0
///
///     var body: some View {
///         Menu(items: menuItems, selection: $selectedIndex)
///     }
/// }
/// ```
@propertyWrapper
public struct Binding<Value> {
  /// The getter for the value.
  private let getValue: () -> Value

  /// The setter for the value.
  private let setValue: (Value) -> Void

  /// The current value.
  public var wrappedValue: Value {
    get { getValue() }
    nonmutating set { setValue(newValue) }
  }

  /// The binding itself (for projectedValue access).
  public var projectedValue: Binding<Value> {
    self
  }

  /// Creates a binding with custom getter and setter.
  ///
  /// - Parameters:
  ///   - get: The getter closure.
  ///   - set: The setter closure.
  public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
    self.getValue = get
    self.setValue = set
  }

  /// Creates a constant binding that never changes.
  ///
  /// - Parameter value: The constant value.
  /// - Returns: A binding that always returns the given value.
  public static func constant(_ value: Value) -> Binding<Value> {
    Self(get: { value }, set: { _ in })
  }
}

// MARK: - State Property Wrapper

/// A property wrapper that stores mutable state for a view.
///
/// When the value changes, the view hierarchy is re-rendered.
/// Use `@State` for simple value types owned by a single view.
///
/// # Example
///
/// ```swift
/// struct CounterView: View {
///     @State var count = 0
///
///     var body: some View {
///         VStack {
///             Text("Count: \(count)")
///             // When count changes, view re-renders
///         }
///     }
/// }
/// ```
///
/// # Accessing the Binding
///
/// Use the `$` prefix to get a `Binding` to the state:
///
/// ```swift
/// Menu(selection: $selectedIndex)
/// ```
///
/// # Render Integration
///
/// Immediately before a view's `body` is evaluated, the renderer binds each
/// `@State` property to a persistent `StateBox` using the view's final
/// structural identity and the property's declaration slot.
///
/// Binding after structural traversal prevents a child constructed in its
/// parent's body from claiming the parent's identity. State therefore survives
/// reconstruction while independent siblings retain independent storage.
///
/// Mutations signal re-renders through the owning runtime's invalidation sink.
@propertyWrapper
public struct State<Value> {
  /// Stable indirection that can adopt the box for the committed view identity.
  private let location: StateLocation<Value>

  /// The default value provided at init time.
  ///
  /// Used by `StateStorage` to create a new entry when no persistent
  /// value exists for this property yet.
  let defaultValue: Value

  /// The current state value.
  public var wrappedValue: Value {
    get { location.box.value }
    nonmutating set {
      location.box.value = newValue
    }
  }

  /// A binding to the state value.
  public var projectedValue: Binding<Value> {
    Binding(
      get: { location.box.value },
      set: { location.box.value = $0 }
    )
  }

  /// Creates a state with an initial value.
  ///
  /// The wrapper starts with local storage. The renderer replaces that storage
  /// with the persistent box for the committed view identity before `body`
  /// evaluation.
  ///
  /// - Parameter wrappedValue: The initial/default value.
  public init(wrappedValue: Value) {
    self.defaultValue = wrappedValue
    self.location = StateLocation(defaultValue: wrappedValue)
  }
}

// MARK: - Runtime Binding

extension State: RuntimeDynamicProperty {
  package func bind(to context: HydrationContext, propertyIndex: Int) {
    location.bind(to: context, propertyIndex: propertyIndex)
  }
}

// MARK: - State Location

private final class StateLocation<Value> {
  let defaultValue: Value
  var box: StateBox<Value>
  private weak var storage: StateStorage?
  private var key: StateStorage.StateKey?

  init(defaultValue: Value) {
    self.defaultValue = defaultValue
    self.box = StateBox(defaultValue)
  }

  func bind(to context: HydrationContext, propertyIndex: Int) {
    let key = StateStorage.StateKey(
      identity: context.identity,
      propertyIndex: propertyIndex
    )

    if self.key != key || storage !== context.storage {
      box = context.storage.storage(for: key, default: defaultValue)
      storage = context.storage
      self.key = key
    }
    box.bind(identity: context.identity, invalidationSink: context.invalidationSink)
  }
}
