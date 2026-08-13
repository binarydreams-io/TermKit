//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButton.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Radio Button Orientation

/// Defines the layout direction of a radio button group.
public enum RadioButtonOrientation: Sendable {
  /// Items stacked vertically (default).
  case vertical

  /// Items arranged horizontally.
  case horizontal
}

// MARK: - Radio Button Item

/// A single option in a radio button group.
///
/// Contains a value (for selection binding) and a label view.
public struct RadioButtonItem<Value: Hashable> {
  /// The value associated with this option.
  let value: Value

  /// The label view builder.
  let labelBuilder: @MainActor () -> AnyView

  /// Creates a radio button item with a view label.
  ///
  /// - Parameters:
  ///   - value: The value for this option.
  ///   - label: A view builder closure that returns the label.
  @MainActor
  public init(
    _ value: Value,
    @ViewBuilder label: @escaping () -> some View
  ) {
    self.value = value
    self.labelBuilder = { AnyView(label()) }
  }

  /// Creates a radio button item with a string label.
  ///
  /// - Parameters:
  ///   - value: The value for this option.
  ///   - label: The label text.
  @MainActor
  public init(
    _ value: Value,
    _ label: String
  ) {
    self.value = value
    self.labelBuilder = { AnyView(Text(label)) }
  }
}

// MARK: - Radio Button Group Builder

/// A result builder that constructs arrays of radio button items for use in ``RadioButtonGroup``.
///
/// `RadioButtonGroupBuilder` enables the declarative syntax for defining multiple
/// options within a ``RadioButtonGroup``. You don't use this type directly; instead,
/// the `@RadioButtonGroupBuilder` attribute is applied to the trailing closure of
/// ``RadioButtonGroup/init(selection:orientation:isDisabled:builder:)``.
///
/// ## Overview
///
/// When you write:
///
/// ```swift
/// RadioButtonGroup(selection: $choice) {
///     RadioButtonItem(.option1, "First Option")
///     RadioButtonItem(.option2, "Second Option")
///     RadioButtonItem(.option3, "Third Option")
/// }
/// ```
///
/// The `@RadioButtonGroupBuilder` attribute transforms this closure into an array
/// of ``RadioButtonItem`` instances that the group can render and manage.
///
/// ## Supported Control Flow
///
/// The builder supports:
/// - Multiple item expressions
/// - `if`/`else` conditionals
/// - `if let` optional binding
/// - `for`...`in` loops
@resultBuilder
public enum RadioButtonGroupBuilder<Value: Hashable> {
  public static func buildBlock(_ items: RadioButtonItem<Value>...) -> [RadioButtonItem<Value>] {
    Array(items)
  }

  public static func buildOptional(_ items: [RadioButtonItem<Value>]?) -> [RadioButtonItem<Value>] {
    items ?? []
  }

  public static func buildEither(first items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
    items
  }

  public static func buildEither(second items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
    items
  }

  public static func buildArray(_ itemGroups: [[RadioButtonItem<Value>]]) -> [RadioButtonItem<Value>] {
    itemGroups.flatMap(\.self)
  }
}

// MARK: - Radio Button Group

/// An interactive radio button group for single-selection from multiple options.
///
/// Radio buttons can be arranged vertically or horizontally. Each option is focusable
/// and supports keyboard navigation with arrow keys. Selection can be changed with Enter or Space.
///
/// ## Rendering
///
/// Vertical layout:
/// ```
/// ◯ Option 1
/// ● Option 2  (selected)
/// ◯ Option 3
/// ```
///
/// Horizontal layout:
/// ```
/// ◯ Option 1  ● Option 2  ◯ Option 3
/// ```
///
/// # Basic Example
///
/// ```swift
/// @State var selection: String = "option1"
///
/// RadioButtonGroup(selection: $selection) {
///     RadioButtonItem("option1") { Text("First Choice") }
///     RadioButtonItem("option2") { Text("Second Choice") }
///     RadioButtonItem("option3") { Text("Third Choice") }
/// }
/// ```
public struct RadioButtonGroup<Value: Hashable>: View {
  /// The binding to the selected value.
  let selection: Binding<Value>

  /// The items in the group.
  let items: [RadioButtonItem<Value>]

  /// The layout orientation.
  let orientation: RadioButtonOrientation

  /// The unique focus identifier for the group.
  /// Auto-generated if not provided, but must be stable across renders.
  var focusID: String?

  /// Whether the group is disabled.
  var isDisabled: Bool

  /// Creates a radio button group with items and a selection binding.
  ///
  /// - Parameters:
  ///   - selection: A binding to the selected value.
  ///   - orientation: The layout orientation (default: `.vertical`).
  ///   - isDisabled: Whether the group is disabled (default: false).
  ///   - builder: A builder closure that returns radio button items.
  public init(
    selection: Binding<Value>,
    orientation: RadioButtonOrientation = .vertical,
    isDisabled: Bool = false,
    @RadioButtonGroupBuilder<Value> builder: () -> [RadioButtonItem<Value>]
  ) {
    self.selection = selection
    self.items = builder()
    self.orientation = orientation
    self.focusID = nil
    self.isDisabled = isDisabled
  }

  public var body: some View {
    _RadioButtonGroupCore(
      selection: selection,
      items: items,
      orientation: orientation,
      focusID: focusID,
      isDisabled: isDisabled
    )
  }
}

// MARK: - Radio Button Group Convenience Modifiers

extension RadioButtonGroup {
  /// Creates a disabled version of this radio button group.
  ///
  /// - Parameter disabled: Whether the group is disabled.
  /// - Returns: A new group with the disabled state.
  public func disabled(_ disabled: Bool = true) -> RadioButtonGroup<Value> {
    var newGroup = self
    newGroup.isDisabled = disabled
    return newGroup
  }

  /// Sets a custom focus identifier for this radio button group.
  ///
  /// - Parameter id: The unique focus identifier.
  /// - Returns: A group with the specified focus identifier.
  public func focusID(_ id: String) -> RadioButtonGroup<Value> {
    var copy = self
    copy.focusID = id
    return copy
  }
}
