//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Layout+OverlayPadding.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Overlay

extension View {
  /// Layers the specified view on top of this view.
  ///
  /// The overlay is positioned according to the specified alignment
  /// within the bounds of the base view.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text("Background content here")
  ///     .overlay(alignment: .center) {
  ///         Text("Centered overlay")
  ///     }
  /// ```
  ///
  /// - Parameters:
  ///   - alignment: The alignment of the overlay (default: .center).
  ///   - content: The overlay content.
  /// - Returns: A view with the overlay applied.
  public func overlay(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> some View
  ) -> some View {
    OverlayModifier(base: self, overlay: content(), alignment: alignment)
  }
}

// MARK: - Padding

extension View {
  /// Adds padding on all sides.
  ///
  /// In a terminal context, 1 unit of padding means:
  /// - **Vertical (top/bottom):** 1 line
  /// - **Horizontal (leading/trailing):** 1 character
  ///
  /// When called without arguments, `.padding()` adds 1 unit on all sides.
  ///
  /// ```swift
  /// Text("Hello")
  ///     .padding()    // 1 line top/bottom, 1 char left/right
  ///     .padding(2)   // 2 lines top/bottom, 2 chars left/right
  /// ```
  ///
  /// - Parameter amount: The padding amount on all sides (default: 1).
  /// - Returns: A padded view.
  public func padding(_ amount: Int = 1) -> some View {
    modifier(PaddingModifier(insets: EdgeInsets(all: amount)))
  }

  /// Adds padding on specific edges.
  ///
  /// In a terminal context, 1 unit of padding means:
  /// - **Vertical (top/bottom):** 1 line
  /// - **Horizontal (leading/trailing):** 1 character
  ///
  /// ```swift
  /// Text("Hello")
  ///     .padding(.horizontal, 4)  // 4 chars left and right
  ///     .padding(.vertical, 2)    // 2 lines top and bottom
  /// ```
  ///
  /// - Parameters:
  ///   - edges: The edges to pad.
  ///   - amount: The padding amount (default: 1).
  /// - Returns: A padded view.
  public func padding(_ edges: Edge, _ amount: Int = 1) -> some View {
    let insets = EdgeInsets(
      top: edges.contains(.top) ? amount : 0,
      leading: edges.contains(.leading) ? amount : 0,
      bottom: edges.contains(.bottom) ? amount : 0,
      trailing: edges.contains(.trailing) ? amount : 0
    )
    return modifier(PaddingModifier(insets: insets))
  }

  /// Adds padding with explicit edge insets.
  ///
  /// ```swift
  /// Text("Hello")
  ///     .padding(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
  /// ```
  ///
  /// - Parameter insets: The edge insets.
  /// - Returns: A padded view.
  public func padding(_ insets: EdgeInsets) -> some View {
    modifier(PaddingModifier(insets: insets))
  }
}
