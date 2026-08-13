//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContainerView+Extensions.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Equatable Conformance

extension ContainerView: @preconcurrency Equatable where Content: Equatable, Footer: Equatable {
  static func == (lhs: ContainerView<Content, Footer>, rhs: ContainerView<Content, Footer>) -> Bool {
    lhs.title == rhs.title &&
      lhs.titleColor == rhs.titleColor &&
      lhs.content == rhs.content &&
      lhs.footer == rhs.footer &&
      lhs.style == rhs.style &&
      lhs.padding == rhs.padding
  }
}

// MARK: - Convenience Initializer (no footer)

extension ContainerView where Footer == EmptyView {
  /// Creates a container without a footer.
  ///
  /// - Parameters:
  ///   - title: The title (optional).
  ///   - titleColor: The title color (default: theme accent).
  ///   - style: The container style configuration.
  ///   - padding: Inner padding for body content.
  ///   - content: The main content.
  init(
    title: String? = nil,
    titleColor: Color? = nil,
    style: ContainerStyle = .default,
    padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.titleColor = titleColor
    self.style = style
    self.padding = padding
    self.content = content()
    self.footer = nil
  }
}
