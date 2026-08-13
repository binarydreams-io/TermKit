//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Scroll Metrics

/// The vertical geometry that a ``ScrollView`` measured in its last render pass.
///
/// A screen reads these values to drive its own scroll commands. Use
/// ``maximumOffset`` to clamp an offset, ``pageSize`` to move one page, and
/// ``contentRegions`` to find the row to reveal.
public struct ScrollMetrics: Equatable, Sendable {
  /// The height of the content in terminal rows.
  public var contentHeight: Int

  /// The height of the visible viewport in terminal rows.
  public var viewportHeight: Int

  /// The largest offset that still fills the viewport.
  ///
  /// The value is `0` when the content fits in the viewport.
  public var maximumOffset: Int

  /// The number of rows that one page step moves.
  ///
  /// The value keeps two rows of context between two pages.
  public var pageSize: Int

  /// The interaction regions of the content, in content coordinates.
  ///
  /// The viewport does not clip these regions. The rendered buffer carries the
  /// clipped regions in viewport coordinates instead.
  public var contentRegions: [InteractionRegion]

  /// Creates scroll metrics.
  ///
  /// - Parameters:
  ///   - contentHeight: The height of the content in terminal rows.
  ///   - viewportHeight: The height of the visible viewport in terminal rows.
  ///   - maximumOffset: The largest offset that still fills the viewport.
  ///   - pageSize: The number of rows that one page step moves.
  ///   - contentRegions: The interaction regions in content coordinates.
  public init(
    contentHeight: Int = 0,
    viewportHeight: Int = 0,
    maximumOffset: Int = 0,
    pageSize: Int = 1,
    contentRegions: [InteractionRegion] = []
  ) {
    self.contentHeight = contentHeight
    self.viewportHeight = viewportHeight
    self.maximumOffset = maximumOffset
    self.pageSize = pageSize
    self.contentRegions = contentRegions
  }
}

// MARK: - ScrollView

/// A view that shows a vertical window onto content that is taller than the
/// available height.
///
/// ```swift
/// @State private var offset = 0
/// @State private var metrics = ScrollMetrics()
///
/// ScrollView {
///     VStack(alignment: .leading) {
///         Text("first row")
///         Text("second row")
///     }
/// }
/// .scrollOffset($offset)
/// .scrollMetrics($metrics)
/// ```
///
/// The view always fills the available height. It clips content that is taller
/// and pads content that is shorter. Every rendered line gets the same visible
/// width, so a parent container never receives a ragged block.
///
/// ## Differences from SwiftUI
///
/// | SwiftUI | TUIkit |
/// |---------|--------|
/// | `init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, content:)` | `init(content:)`, vertical only |
/// | `CGFloat` offsets in points | `Int` offsets in terminal rows |
/// | `ScrollViewReader` and `scrollTo(_:)` | ``scrollOffset(_:)`` and ``scrollMetrics(_:)`` |
///
/// TUIkit scrolls on the vertical axis only, so the initializer takes no
/// `Axis.Set`. Offset control and geometry reporting are modifiers, not
/// initializer parameters. The initializer therefore stays a subset of the
/// SwiftUI signature.
///
/// ## Ownership of the offset
///
/// Without ``scrollOffset(_:)`` the view keeps its own offset in state storage.
/// With ``scrollOffset(_:)`` the caller owns the value.
///
/// The view clamps the offset that it reads to the range
/// `0...maximumOffset` for the current frame. The view never writes the clamped
/// value back through the binding. A caller that wants a clamped value reads
/// ``ScrollMetrics/maximumOffset`` and clamps its own state.
public struct ScrollView<Content: View>: View {
  /// The content that the viewport shows.
  let content: Content

  /// The offset binding of the caller, or `nil` when the view owns the offset.
  var offset: Binding<Int>?

  /// The metrics binding of the caller, or `nil` when no caller reads geometry.
  var metrics: Binding<ScrollMetrics>?

  /// Whether the view can draw scroll indicators.
  var showsIndicators: Bool

  /// Creates a view that scrolls its content vertically.
  ///
  /// - Parameter content: A ViewBuilder that defines the scrolled content.
  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
    self.offset = nil
    self.metrics = nil
    self.showsIndicators = true
  }
}

// MARK: - ScrollView Modifiers

extension ScrollView {
  /// Reads the vertical offset from a value that the caller owns.
  ///
  /// The offset counts terminal rows from the first row of the content. The
  /// view clamps the value that it reads for the current frame. The view never
  /// writes the clamped value back through the binding.
  ///
  /// - Parameter offset: A binding to the first visible content row.
  /// - Returns: A scroll view that reads its offset from the binding.
  public func scrollOffset(_ offset: Binding<Int>) -> ScrollView {
    var copy = self
    copy.offset = offset
    return copy
  }

  /// Reports the measured geometry after each render pass.
  ///
  /// The view writes through the binding only when the geometry changed. The
  /// view writes nothing during a measurement pass.
  ///
  /// - Parameter metrics: A binding that receives the measured geometry.
  /// - Returns: A scroll view that reports its geometry.
  public func scrollMetrics(_ metrics: Binding<ScrollMetrics>) -> ScrollView {
    var copy = self
    copy.metrics = metrics
    return copy
  }

  /// Sets whether the view can draw scroll indicators.
  ///
  /// - Parameter visible: `true` to permit indicators. The default value is `true`.
  /// - Returns: A scroll view with the indicator preference.
  ///
  /// > Note: The geometry core stores this preference. The indicator overlay
  /// > reads it in the scroll interaction layer.
  public func scrollIndicators(_ visible: Bool) -> ScrollView {
    var copy = self
    copy.showsIndicators = visible
    return copy
  }
}
