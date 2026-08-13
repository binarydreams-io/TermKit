//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alert.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modal alert view that displays a title, message, and optional action buttons.
///
/// `Alert` is designed to be shown as an overlay on top of other content.
/// Use it together with `.overlay()` and `.dimmed()` for a modal effect.
///
/// ## Structure
///
/// - **Header**: Title (rendered in the top border)
/// - **Body**: Message
/// - **Footer**: Action buttons (separated by optional separator line)
///
/// ## Examples
///
/// ```swift
/// // Simple alert
/// Alert(title: "Warning", message: "Are you sure?")
///
/// // Alert with action buttons
/// Alert(title: "Confirm", message: "Delete this item?") {
///     Button("Yes") { }
///     Button("No") { }
/// }
///
/// // Modal overlay pattern
/// mainContent
///     .dimmed()
///     .overlay {
///         Alert(title: "Notice", message: "Operation complete!")
///     }
/// ```
public struct Alert<Actions: View>: View {
  /// The alert title.
  let title: String

  /// The alert message.
  let message: String

  /// The shared visual configuration.
  let config: ContainerConfig

  /// The action views (typically buttons).
  let actions: Actions

  /// Creates an alert with custom action views.
  ///
  /// - Parameters:
  ///   - title: The alert title.
  ///   - message: The alert message.
  ///   - borderStyle: The border style (default: appearance borderStyle).
  ///   - borderColor: The border color (default: theme border).
  ///   - titleColor: The title color (default: theme foreground).
  ///   - showFooterSeparator: Whether to show separator before actions (default: true).
  ///   - actions: The action views to display in the footer.
  public init(
    title: String,
    message: String,
    borderStyle: BorderStyle? = nil,
    borderColor: Color? = nil,
    titleColor: Color? = nil,
    showFooterSeparator: Bool = true,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.message = message
    self.config = ContainerConfig(
      borderStyle: borderStyle,
      borderColor: borderColor,
      titleColor: titleColor,
      padding: EdgeInsets(horizontal: 2, vertical: 1),
      showFooterSeparator: showFooterSeparator
    )
    self.actions = actions()
  }

  public var body: some View {
    _AlertCore(
      title: title,
      message: message,
      config: config,
      actions: actions
    )
  }
}
