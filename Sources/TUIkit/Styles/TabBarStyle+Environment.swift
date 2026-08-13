//  TUIKit - Terminal UI Kit for Swift
//  TabBarStyle+Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

private struct TabBarStyleKey: EnvironmentKey {
  static let defaultValue: TabBarStyle = .filled
}

extension EnvironmentValues {
  /// The tab bar style for this environment.
  ///
  /// Set it with the `tabBarStyle(_:)` modifier on any ancestor of a
  /// ``TabView``. Default: ``TabBarStyle/filled``.
  var tabBarStyle: TabBarStyle {
    get { self[TabBarStyleKey.self] }
    set { self[TabBarStyleKey.self] = newValue }
  }
}

// MARK: - View Extension

extension View {
  /// Sets the look of the tab bar for tab views within this view.
  ///
  /// ```swift
  /// TabView(selection: $tab, tabs: tabs) { tab in
  ///     Pane(tab)
  /// }
  /// .tabBarStyle(.plain)
  /// ```
  ///
  /// - Parameter style: The bar style to apply.
  /// - Returns: A view whose tab views draw their bar in the given style.
  public func tabBarStyle(_ style: TabBarStyle) -> some View {
    environment(\.tabBarStyle, style)
  }
}
