//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OverlaysPage+Demo.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Overlay Demo Variants

/// Available overlay demo variants.
enum OverlayDemo: Int, CaseIterable {
  case alertStandard
  case alertWarning
  case alertError
  case alertInfo
  case alertSuccess
  case dialog
  case dialogWithFooter
  case modalCustom
  case notification

  /// Display label for the menu.
  var label: String {
    switch self {
    case .alertStandard: "Alert (Standard)"
    case .alertWarning: "Alert (Warning)"
    case .alertError: "Alert (Error)"
    case .alertInfo: "Alert (Info)"
    case .alertSuccess: "Alert (Success)"
    case .dialog: "Dialog"
    case .dialogWithFooter: "Dialog with Footer"
    case .modalCustom: "Modal (Custom)"
    case .notification: "Notification"
    }
  }

  /// Description text for the detail panel.
  var description: String {
    switch self {
    case .alertStandard:
      "A standard alert with default theme colors. Uses .alert(isPresented:) modifier."
    case .alertWarning:
      "A warning-style alert with palette warning colors. Uses Alert.warning() preset."
    case .alertError:
      "An error-style alert with palette error colors. Uses Alert.error() preset."
    case .alertInfo:
      "An info-style alert with palette info colors. Uses Alert.info() preset."
    case .alertSuccess:
      "A success-style alert with palette success colors. Uses Alert.success() preset."
    case .dialog:
      "A Dialog view with custom content. More flexible than Alert — accepts any views."
    case .dialogWithFooter:
      "A Dialog with a footer section for action buttons, separated by a divider line."
    case .modalCustom:
      "A custom modal overlay using .modal(isPresented:). Accepts any view as content."
    case .notification:
      "A fire-and-forget notification. Fades in, stays 3s, fades out. Posted via NotificationService."
    }
  }

  /// API usage example for the detail panel.
  var apiUsage: String {
    switch self {
    case .alertStandard:
      ".alert(\"Title\", isPresented: $show) { actions } message: { Text(\"...\") }"
    case .alertWarning:
      ".modal(isPresented: $show) { Alert.warning(message: \"...\") { actions } }"
    case .alertError:
      ".modal(isPresented: $show) { Alert.error(message: \"...\") { actions } }"
    case .alertInfo:
      ".modal(isPresented: $show) { Alert.info(message: \"...\") { actions } }"
    case .alertSuccess:
      ".modal(isPresented: $show) { Alert.success(message: \"...\") { actions } }"
    case .dialog:
      ".modal(isPresented: $show) { Dialog(title: \"...\") { content } }"
    case .dialogWithFooter:
      ".modal(isPresented: $show) { Dialog(title: \"...\") { content } footer: { buttons } }"
    case .modalCustom:
      ".modal(isPresented: $show) { VStack { ... } }"
    case .notification:
      "@Environment(\\.notificationService) + notifications.post(\"Saved!\")"
    }
  }

  /// Whether this demo variant is a notification (not a modal).
  var isNotification: Bool {
    self == .notification
  }
}
