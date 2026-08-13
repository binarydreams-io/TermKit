private struct NavigationSplitViewStyleKey: EnvironmentKey {
  static let defaultValue: any NavigationSplitViewStyle = AutomaticNavigationSplitViewStyle()
}

extension EnvironmentValues {
  /// The navigation split view style for this environment.
  public var navigationSplitViewStyle: any NavigationSplitViewStyle {
    get { self[NavigationSplitViewStyleKey.self] }
    set { self[NavigationSplitViewStyleKey.self] = newValue }
  }
}

// MARK: - View Extension

extension View {
  /// Sets the style for navigation split views within this view.
  ///
  /// Use this modifier to specify how columns in a ``NavigationSplitView``
  /// should be sized and displayed.
  ///
  /// ```swift
  /// NavigationSplitView {
  ///     SidebarView()
  /// } detail: {
  ///     DetailView()
  /// }
  /// .navigationSplitViewStyle(.prominentDetail)
  /// ```
  ///
  /// ## Available Styles
  ///
  /// - ``AutomaticNavigationSplitViewStyle/automatic``: Resolves based on context.
  /// - ``BalancedNavigationSplitViewStyle/balanced``: Columns share space proportionally.
  /// - ``ProminentDetailNavigationSplitViewStyle/prominentDetail``: Detail gets more space.
  ///
  /// - Parameter style: The navigation split view style to apply.
  /// - Returns: A view with the specified navigation split view style.
  public func navigationSplitViewStyle(_ style: some NavigationSplitViewStyle) -> some View {
    environment(\.navigationSplitViewStyle, style)
  }
}
