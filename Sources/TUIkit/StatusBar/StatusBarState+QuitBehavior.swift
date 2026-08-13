//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarState+QuitBehavior.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Controls when the quit shortcut (`q`) is active.
public enum QuitBehavior: Sendable {
  /// Quit works from any screen.
  ///
  /// Pressing `q` will always exit the application, regardless of
  /// the current navigation state.
  case always

  /// Quit only works from the root/main screen.
  ///
  /// Pressing `q` will only exit when no context is pushed onto the
  /// status bar stack. On subpages, `q` does nothing, allowing the
  /// app to handle navigation (e.g., ESC to go back).
  case rootOnly
}
