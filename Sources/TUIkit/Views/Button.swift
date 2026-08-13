//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Button.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Button

/// An interactive button that triggers an action when pressed.
///
/// Buttons can receive focus and respond to keyboard input (Enter or Space).
/// They display differently when focused to indicate the current selection.
///
/// ## Rendering
///
/// - **Standard appearances** (line, rounded, doubleLine, heavy):
///   Rendered as single-line `[ Label ]` with bracket delimiters.
///
/// - **Plain style**: No brackets, no background — just the label text.
///
/// # Basic Example
///
/// ```swift
/// Button("Submit") {
///     handleSubmit()
/// }
/// ```
///
/// # Styled Button
///
/// ```swift
/// Button("Delete", style: .destructive) {
///     handleDelete()
/// }
/// ```
public struct Button: View {
  /// The button's label text.
  let label: String

  /// The action to perform when pressed.
  let action: () -> Void

  /// The button's semantic role.
  ///
  /// Roles affect button ordering in alerts/dialogs and can trigger
  /// automatic styling. Cancel buttons appear on the left; destructive
  /// buttons use error coloring.
  let role: ButtonRole?

  /// The normal (unfocused) style.
  let style: ButtonStyle

  /// The focused style.
  let focusedStyle: ButtonStyle

  /// The unique focus identifier.
  ///
  /// If `nil`, automatically generated from the view's identity path.
  /// Use the `.focusID()` modifier to override.
  var focusID: String?

  /// Whether the button is disabled.
  var isDisabled: Bool

  /// Creates a button with a label and action.
  ///
  /// - Parameters:
  ///   - label: The button's label text.
  ///   - style: The button style (default: `.default`).
  ///   - focusedStyle: The style when focused (default: bold variant).
  ///   - isDisabled: Whether the button is disabled (default: false).
  ///   - action: The action to perform when pressed.
  public init(
    _ label: String,
    style: ButtonStyle = .default,
    focusedStyle: ButtonStyle? = nil,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.action = action
    self.role = nil
    self.style = style
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = isDisabled

    // Default focused style: bold version of the normal style
    self.focusedStyle =
      focusedStyle
        ?? ButtonStyle(
          foregroundColor: style.foregroundColor,
          backgroundColor: style.backgroundColor,
          isBold: true,
          horizontalPadding: style.horizontalPadding
        )
  }

  /// Creates a button with an optional role for semantic meaning.
  ///
  /// Use this initializer to create buttons with roles like `.cancel` or `.destructive`.
  /// The role affects button ordering in alerts and can influence styling.
  ///
  /// This matches the SwiftUI signature:
  /// `init(_ title: S, role: ButtonRole?, action: () -> Void)`
  ///
  /// - Parameters:
  ///   - label: The button's label text.
  ///   - role: An optional semantic role describing the button.
  ///   - action: The action to perform when pressed.
  public init(
    _ label: String,
    role: ButtonRole?,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.action = action
    self.role = role
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false

    // Style based on role
    switch role {
    case .destructive:
      self.style = .destructive
      self.focusedStyle = ButtonStyle(
        foregroundColor: .palette.error,
        isBold: true,
        horizontalPadding: 1
      )
    case .cancel:
      self.style = .default
      self.focusedStyle = ButtonStyle(
        foregroundColor: nil,
        isBold: true,
        horizontalPadding: 1
      )
    default:
      self.style = .default
      self.focusedStyle = ButtonStyle(isBold: true, horizontalPadding: 1)
    }
  }
}

// MARK: - Button Convenience Modifiers

extension Button {
  /// Creates a disabled version of this button.
  ///
  /// - Parameter disabled: Whether the button is disabled.
  /// - Returns: A new button with the disabled state.
  public func disabled(_ disabled: Bool = true) -> Button {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }

  /// Sets a custom focus identifier for this button.
  ///
  /// - Parameter id: The unique focus identifier.
  /// - Returns: A button with the specified focus identifier.
  public func focusID(_ id: String) -> Button {
    var copy = self
    copy.focusID = id
    return copy
  }
}
