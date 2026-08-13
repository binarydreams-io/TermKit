//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Button+Styles.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Button Role

/// A value that describes the purpose of a button.
///
/// Use button roles to give buttons a semantic meaning that affects
/// their appearance and behavior. In alerts and dialogs, buttons are
/// automatically ordered based on their role.
///
/// - `cancel`: A button that cancels the current operation. Placed on the left.
/// - `destructive`: A button that deletes data or performs an irreversible action.
public struct ButtonRole: Equatable, Sendable {
  let rawValue: String

  private init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  /// A role that indicates a cancellation action.
  ///
  /// Cancel buttons are placed on the left side in alerts and dialogs.
  /// Pressing ESC triggers the cancel action if one exists.
  public static let cancel = Self("cancel")

  /// A role that indicates a destructive action.
  ///
  /// Destructive buttons are styled with the error color to indicate danger.
  /// Use for buttons that delete user data or perform irreversible operations.
  public static let destructive = Self("destructive")
}

// MARK: - Button Style

/// Defines the visual style of a button.
public struct ButtonStyle: Sendable {
  /// The foreground color for the label.
  ///
  /// Uses a semantic color reference so the actual value is resolved
  /// at render time from the active palette. Set to `nil` to use the
  /// palette's accent color.
  public var foregroundColor: Color?

  /// The background color (reserved for future use).
  public var backgroundColor: Color?

  /// Whether the label is bold.
  public var isBold: Bool

  /// Horizontal padding inside the button.
  public var horizontalPadding: Int

  /// Creates a button style.
  ///
  /// - Parameters:
  ///   - foregroundColor: The label color (default: theme accent).
  ///   - backgroundColor: The background color.
  ///   - isBold: Whether the label is bold.
  ///   - horizontalPadding: Horizontal padding inside the button.
  public init(
    foregroundColor: Color? = nil,
    backgroundColor: Color? = nil,
    isBold: Bool = false,
    horizontalPadding: Int = 1
  ) {
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
    self.isBold = isBold
    self.horizontalPadding = horizontalPadding
  }

  // MARK: - Preset Styles

  /// Default button style — dimmed foreground, not bold.
  public static let `default` = Self(
    foregroundColor: .palette.foregroundSecondary
  )

  /// Primary button style — bold, uses palette accent.
  public static let primary = Self(
    foregroundColor: .palette.accent,
    isBold: true
  )

  /// Destructive button style — uses palette error color.
  public static let destructive = Self(
    foregroundColor: .palette.error
  )

  /// Success button style — uses palette success color.
  public static let success = Self(
    foregroundColor: .palette.success
  )

  /// Plain button style — no brackets, no border, no padding.
  public static let plain = Self(
    horizontalPadding: 0
  )
}
