//  TUIKit - Terminal UI Kit for Swift
//  TabBarStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Tab Bar Style

/// The look of a ``TabView``'s one-line tab bar.
///
/// ```
/// filled:  1 ALPHA       2 BETA        every tab fills a share of the width
/// plain:   ▎ ALPHA    2 BETA           no fill; the rail marks the selection
/// ```
///
/// Apply a style with the `tabBarStyle(_:)` modifier. The style is a
/// TUI-specific option: SwiftUI's `TabViewStyle` selects a paging behaviour,
/// not the appearance of a bar that is one terminal row tall.
public enum TabBarStyle: Sendable, Equatable {
  /// Every tab fills an equal share of the bar's width, the selected tab in the
  /// accent colour and the rest in the focus background. This is the default.
  case filled

  /// No fill on the bar or on its labels.
  ///
  /// The selected tab prints the thin rail `▎`, one space, and its label in the
  /// accent, bold. An unselected tab prints its key hint in the dimmest
  /// foreground and its label in the tertiary foreground. Each tab keeps its
  /// natural width, so the labels read as items and not as strips.
  case plain
}
