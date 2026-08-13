//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarState+Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

extension StatusBarState {
  /// Creates a status bar state with a default `AppState` instance.
  ///
  /// Used for environment key defaults and testing only.
  convenience init() {
    self.init(appState: AppState())
  }
}

private struct StatusBarKey: EnvironmentKey {
  static let defaultValue = StatusBarState()
}

extension EnvironmentValues {
  // The status bar state for the current application.
  //
  // Use this to set status bar items from within your views:
  //
  // ```swift
  // let statusBar = context.environment.statusBar
  // statusBar.setItems([
  //     StatusBarItem(shortcut: "q", label: "quit")
  // ])
  // ```
  public var statusBar: StatusBarState {
    get { self[StatusBarKey.self] }
    set { self[StatusBarKey.self] = newValue }
  }
}
