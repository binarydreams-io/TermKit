/// Identifies a built-in declarative layout operation.
public enum LayoutPrimitive: Sendable, Hashable {
  /// Arranges children in a stack.
  case stack(StackLayout)
  /// Adds padding around content.
  case padding(PaddingLayout)
  /// Places content in a frame.
  case frame(FrameLayout)
  /// Defines a scroll viewport.
  case scrollViewport(ScrollViewportLayout)
}

/// Defines optional dimensions for a scroll viewport.
public struct ScrollViewportLayout: Sendable, Hashable {
  /// The fixed viewport width, or `nil` when unspecified.
  public var width: Int?
  /// The fixed viewport height, or `nil` when unspecified.
  public var height: Int?

  /// Creates a scroll viewport layout.
  public init(width: Int? = nil, height: Int? = nil) {
    precondition(width.map { $0 >= 0 } ?? true)
    precondition(height.map { $0 >= 0 } ?? true)
    self.width = width
    self.height = height
  }
}

/// Defines a declarative scroll viewport.
public struct ScrollViewport: View {
  private let descriptor: NodeDescriptor

  /// Creates a scroll viewport with declarative content.
  @MainActor
  public init(
    width: Int? = nil,
    height: Int? = nil,
    @ViewBuilder content: () -> [NodeDescriptor]
  ) {
    let primitive = LayoutPrimitive.scrollViewport(ScrollViewportLayout(width: width, height: height))
    self.descriptor = NodeDescriptor(
      type: Self.self,
      value: primitive,
      primitive: primitive,
      children: buildViewGraph(content),
      dirtyOnUpdate: .layout
    )
  }

  /// The descriptor that represents the viewport.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [descriptor]
  }
}

/// Arranges declarative content vertically.
public struct VStack: View {
  private let descriptor: NodeDescriptor

  /// Creates a vertical stack.
  @MainActor
  public init(
    alignment: HorizontalCellAlignment = .center,
    spacing: Int = 0,
    @ViewBuilder content: () -> [NodeDescriptor]
  ) {
    let primitive = LayoutPrimitive.stack(
      StackLayout(axis: .vertical, spacing: spacing, horizontalAlignment: alignment)
    )
    self.descriptor = NodeDescriptor(
      type: Self.self,
      value: primitive,
      primitive: primitive,
      children: buildViewGraph(content),
      dirtyOnUpdate: .layout
    )
  }

  /// The descriptor that represents the stack.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [descriptor]
  }
}

/// Arranges declarative content horizontally.
public struct HStack: View {
  private let descriptor: NodeDescriptor

  /// Creates a horizontal stack.
  @MainActor
  public init(
    alignment: VerticalCellAlignment = .center,
    spacing: Int = 0,
    @ViewBuilder content: () -> [NodeDescriptor]
  ) {
    let primitive = LayoutPrimitive.stack(
      StackLayout(axis: .horizontal, spacing: spacing, verticalAlignment: alignment)
    )
    self.descriptor = NodeDescriptor(
      type: Self.self,
      value: primitive,
      primitive: primitive,
      children: buildViewGraph(content),
      dirtyOnUpdate: .layout
    )
  }

  /// The descriptor that represents the stack.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [descriptor]
  }
}

struct SpacerLayoutValue: Sendable, Hashable {
  let minimumLength: Int
}

/// Expands along the primary axis of its containing stack.
public struct Spacer: View {
  private let descriptor: NodeDescriptor

  /// Creates a spacer with a minimum primary-axis length.
  @MainActor
  public init(minLength: Int = 0) {
    precondition(minLength >= 0)
    let value = SpacerLayoutValue(minimumLength: minLength)
    let primitive = LayoutPrimitive.stack(StackLayout(axis: .horizontal))
    self.descriptor = NodeDescriptor(
      type: Self.self,
      value: value,
      primitive: primitive,
      dirtyOnUpdate: .layout
    )
  }

  /// The empty descriptor that participates only in layout.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [descriptor]
  }
}

/// Contains the proposed geometry supplied to a geometry reader.
public struct GeometryReaderContext: Sendable, Hashable {
  /// The size proposed by the parent layout.
  public let proposedSize: ProposedCellSize

  /// The proposed dimensions with unspecified values replaced by zero.
  public var size: CellSize {
    proposedSize.replacingUnspecifiedDimensions(by: .zero)
  }
}

/// Builds content from the size proposed by the parent layout.
public struct GeometryReader: View {
  @Environment(ProposedCellSizeEnvironmentKey.self) private var proposedSize
  private let content: @MainActor (_ context: GeometryReaderContext) -> [NodeDescriptor]

  /// Creates a reader that rebuilds content when its proposed size changes.
  @MainActor
  public init(
    @ViewBuilder content: @escaping @MainActor (_ context: GeometryReaderContext) -> [NodeDescriptor]
  ) {
    self.content = content
  }

  /// The content built for the current proposed size.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    buildViewGraph {
      content(GeometryReaderContext(proposedSize: proposedSize))
    }
  }
}

extension View {
  /// Adds the specified insets around this view.
  public func padding(_ insets: EdgeInsets) -> some View {
    LayoutModifierView(content: self, primitive: .padding(PaddingLayout(insets)))
  }

  /// Adds equal padding on every edge of this view.
  public func padding(_ amount: Int = 1) -> some View {
    padding(EdgeInsets(all: amount))
  }

  /// Places this view in a frame with optional fixed dimensions.
  public func frame(
    width: Int? = nil,
    height: Int? = nil,
    alignment: CellAlignment = .center
  ) -> some View {
    LayoutModifierView(
      content: self,
      primitive: .frame(FrameLayout(width: width, height: height, alignment: alignment))
    )
  }

  /// Places this view in a scroll viewport.
  public func scrollViewport(width: Int? = nil, height: Int? = nil) -> some View {
    LayoutModifierView(
      content: self,
      primitive: .scrollViewport(ScrollViewportLayout(width: width, height: height))
    )
  }
}

private struct LayoutModifierView<Content: View>: View {
  private let descriptor: NodeDescriptor

  @MainActor
  init(content: Content, primitive: LayoutPrimitive) {
    self.descriptor = NodeDescriptor(
      type: Self.self,
      value: primitive,
      primitive: primitive,
      children: buildViewGraph { content },
      dirtyOnUpdate: .layout
    )
  }

  @MainActor
  var graphBody: [NodeDescriptor] {
    [descriptor]
  }
}
