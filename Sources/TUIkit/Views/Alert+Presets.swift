//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alert+Presets.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Convenience Initializer (no actions)

extension Alert where Actions == EmptyView {
  /// Creates an alert without action buttons.
  ///
  /// - Parameters:
  ///   - title: The alert title.
  ///   - message: The alert message.
  ///   - borderStyle: The border style (default: appearance default).
  ///   - borderColor: The border color (default: nil).
  ///   - titleColor: The title color (default: nil).
  public init(
    title: String,
    message: String,
    borderStyle: BorderStyle? = nil,
    borderColor: Color? = nil,
    titleColor: Color? = nil
  ) {
    self.title = title
    self.message = message
    self.config = ContainerConfig(
      borderStyle: borderStyle,
      borderColor: borderColor,
      titleColor: titleColor,
      padding: EdgeInsets(horizontal: 2, vertical: 1),
      showFooterSeparator: false
    )
    self.actions = EmptyView()
  }
}

// MARK: - Preset Alert Styles

extension Alert {
  /// Creates a warning-style alert with palette warning colors.
  ///
  /// - Parameters:
  ///   - title: The alert title (default: "Warning").
  ///   - message: The alert message.
  ///   - actions: The action views.
  /// - Returns: A warning-styled alert.
  public static func warning<A: View>(
    title: String = "Warning",
    message: String,
    @ViewBuilder actions: () -> A
  ) -> Alert<A> {
    Alert<A>(
      title: title,
      message: message,
      titleColor: .palette.warning,
      actions: actions
    )
  }

  /// Creates an error-style alert with palette error title color.
  ///
  /// - Parameters:
  ///   - title: The alert title (default: "Error").
  ///   - message: The alert message.
  ///   - actions: The action views.
  /// - Returns: An error-styled alert.
  public static func error<A: View>(
    title: String = "Error",
    message: String,
    @ViewBuilder actions: () -> A
  ) -> Alert<A> {
    Alert<A>(
      title: title,
      message: message,
      titleColor: .palette.error,
      actions: actions
    )
  }

  /// Creates an info-style alert with palette info title color.
  ///
  /// - Parameters:
  ///   - title: The alert title (default: "Info").
  ///   - message: The alert message.
  ///   - actions: The action views.
  /// - Returns: An info-styled alert.
  public static func info<A: View>(
    title: String = "Info",
    message: String,
    @ViewBuilder actions: () -> A
  ) -> Alert<A> {
    Alert<A>(
      title: title,
      message: message,
      titleColor: .palette.info,
      actions: actions
    )
  }

  /// Creates a success-style alert with palette success title color.
  ///
  /// - Parameters:
  ///   - title: The alert title (default: "Success").
  ///   - message: The alert message.
  ///   - actions: The action views.
  /// - Returns: A success-styled alert.
  public static func success<A: View>(
    title: String = "Success",
    message: String,
    @ViewBuilder actions: () -> A
  ) -> Alert<A> {
    Alert<A>(
      title: title,
      message: message,
      titleColor: .palette.success,
      actions: actions
    )
  }
}

// MARK: - Preset Alerts without Actions

extension Alert where Actions == EmptyView {
  /// Creates a warning-style alert without actions.
  public static func warning(title: String = "Warning", message: String) -> Alert<EmptyView> {
    Alert<EmptyView>(title: title, message: message, titleColor: .palette.warning)
  }

  /// Creates an error-style alert without actions.
  public static func error(title: String = "Error", message: String) -> Alert<EmptyView> {
    Alert<EmptyView>(title: title, message: message, titleColor: .palette.error)
  }

  /// Creates an info-style alert without actions.
  public static func info(title: String = "Info", message: String) -> Alert<EmptyView> {
    Alert<EmptyView>(title: title, message: message, titleColor: .palette.info)
  }

  /// Creates a success-style alert without actions.
  public static func success(title: String = "Success", message: String) -> Alert<EmptyView> {
    Alert<EmptyView>(title: title, message: message, titleColor: .palette.success)
  }
}
