//  TUIKit - Terminal UI Kit for Swift
//  Stepper+Configuration.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Stepper Initializers (Value Binding)

extension Stepper where Label == Text {
  /// Creates a stepper with a title and value binding.
  ///
  /// - Parameters:
  ///   - title: The title of the stepper.
  ///   - value: The binding to the current value.
  ///   - step: The step size. Defaults to `1`.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init(
    _ title: some StringProtocol,
    value: Binding<Int>,
    step: Int = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.value = value
    self.bounds = nil
    self.step = step
    self.label = Text(String(title))
    self.onIncrement = nil
    self.onDecrement = nil
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }

  /// Creates a stepper with a title, value binding, and range.
  ///
  /// - Parameters:
  ///   - title: The title of the stepper.
  ///   - value: The binding to the current value.
  ///   - bounds: The range of valid values.
  ///   - step: The step size. Defaults to `1`.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init(
    _ title: some StringProtocol,
    value: Binding<Int>,
    in bounds: ClosedRange<Int>,
    step: Int = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.value = value
    self.bounds = bounds
    self.step = step
    self.label = Text(String(title))
    self.onIncrement = nil
    self.onDecrement = nil
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }
}

// MARK: - Stepper Initializers (Custom Callbacks)

extension Stepper where Label == Text {
  /// Creates a stepper with a title and custom increment/decrement callbacks.
  ///
  /// - Parameters:
  ///   - title: The title of the stepper.
  ///   - onIncrement: Callback when increment is requested.
  ///   - onDecrement: Callback when decrement is requested.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init(
    _ title: some StringProtocol,
    onIncrement: (() -> Void)?,
    onDecrement: (() -> Void)?,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    var dummy = 0
    self.value = Binding(get: { dummy }, set: { dummy = $0 })
    self.bounds = nil
    self.step = 1
    self.label = Text(String(title))
    self.onIncrement = onIncrement
    self.onDecrement = onDecrement
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }
}

// MARK: - Stepper Initializers (ViewBuilder Label)

extension Stepper {
  /// Creates a stepper with a custom label and value binding.
  ///
  /// - Parameters:
  ///   - value: The binding to the current value.
  ///   - step: The step size. Defaults to `1`.
  ///   - label: A view describing the purpose of the stepper.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init(
    value: Binding<Int>,
    step: Int = 1,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.value = value
    self.bounds = nil
    self.step = step
    self.label = label()
    self.onIncrement = nil
    self.onDecrement = nil
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }

  /// Creates a stepper with a custom label, value binding, and range.
  ///
  /// - Parameters:
  ///   - value: The binding to the current value.
  ///   - bounds: The range of valid values.
  ///   - step: The step size. Defaults to `1`.
  ///   - label: A view describing the purpose of the stepper.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init(
    value: Binding<Int>,
    in bounds: ClosedRange<Int>,
    step: Int = 1,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.value = value
    self.bounds = bounds
    self.step = step
    self.label = label()
    self.onIncrement = nil
    self.onDecrement = nil
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }

  /// Creates a stepper with a custom label and increment/decrement callbacks.
  ///
  /// - Parameters:
  ///   - label: A view describing the purpose of the stepper.
  ///   - onIncrement: Callback when increment is requested.
  ///   - onDecrement: Callback when decrement is requested.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init(
    @ViewBuilder label: () -> Label,
    onIncrement: (() -> Void)?,
    onDecrement: (() -> Void)?,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    var dummy = 0
    self.value = Binding(get: { dummy }, set: { dummy = $0 })
    self.bounds = nil
    self.step = 1
    self.label = label()
    self.onIncrement = onIncrement
    self.onDecrement = onDecrement
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }
}

// MARK: - Stepper Modifiers

extension Stepper {
  /// Creates a disabled version of this stepper.
  ///
  /// - Parameter disabled: Whether the stepper is disabled.
  /// - Returns: A new stepper with the disabled state.
  public func disabled(_ disabled: Bool = true) -> Stepper {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }

  /// Sets a custom focus identifier for this stepper.
  ///
  /// - Parameter id: The unique focus identifier.
  /// - Returns: A stepper with the specified focus identifier.
  public func focusID(_ id: String) -> Stepper {
    var copy = self
    copy.focusID = id
    return copy
  }
}
