/// Arranges items sequentially along one axis.
public struct StackLayout: Sendable, Hashable {
  /// The axis along which items are arranged.
  public var axis: StackAxis
  /// The number of cells between adjacent items.
  public var spacing: Int
  /// The horizontal alignment for a vertical stack.
  public var horizontalAlignment: HorizontalCellAlignment
  /// The vertical alignment for a horizontal stack.
  public var verticalAlignment: VerticalCellAlignment

  /// Creates a stack layout.
  public init(
    axis: StackAxis,
    spacing: Int = 0,
    horizontalAlignment: HorizontalCellAlignment = .center,
    verticalAlignment: VerticalCellAlignment = .center
  ) {
    precondition(spacing >= 0)
    self.axis = axis
    self.spacing = spacing
    self.horizontalAlignment = horizontalAlignment
    self.verticalAlignment = verticalAlignment
  }

  /// Measures and places items in a stack.
  @MainActor
  public func layout(
    _ items: [LayoutItem],
    in proposal: ProposedCellSize = .unspecified,
    cache: LayoutCache
  ) -> LayoutResult {
    let childProposal = switch axis {
    case .horizontal:
      ProposedCellSize(height: proposal.height)
    case .vertical:
      ProposedCellSize(width: proposal.width)
    }
    var sizes = items.map { cache.measure($0, in: childProposal) }
    let spacerIndices = items.indices.filter { items[$0].spacerMinimumLength != nil }
    for index in spacerIndices {
      let minimumLength = items[index].spacerMinimumLength ?? 0
      switch axis {
      case .horizontal:
        sizes[index].width = max(sizes[index].width, minimumLength)
      case .vertical:
        sizes[index].height = max(sizes[index].height, minimumLength)
      }
    }
    let totalSpacing = layoutMultiplying(spacing, max(0, items.count - 1))
    let naturalSize = switch axis {
    case .horizontal:
      CellSize(
        width: sizes.reduce(totalSpacing) { layoutAdding($0, $1.width) },
        height: sizes.map(\.height).max() ?? 0
      )
    case .vertical:
      CellSize(
        width: sizes.map(\.width).max() ?? 0,
        height: sizes.reduce(totalSpacing) { layoutAdding($0, $1.height) }
      )
    }
    let proposedPrimaryLength = switch axis {
    case .horizontal: proposal.width
    case .vertical: proposal.height
    }
    let naturalPrimaryLength = switch axis {
    case .horizontal: naturalSize.width
    case .vertical: naturalSize.height
    }
    if let proposedPrimaryLength,
       proposedPrimaryLength > naturalPrimaryLength,
       spacerIndices.isEmpty == false
    {
      let remaining = layoutSubtracting(proposedPrimaryLength, naturalPrimaryLength)
      let increment = remaining / spacerIndices.count
      let remainder = remaining % spacerIndices.count
      for (offset, index) in spacerIndices.enumerated() {
        let extra = layoutAdding(increment, offset < remainder ? 1 : 0)
        switch axis {
        case .horizontal:
          sizes[index].width = layoutAdding(sizes[index].width, extra)
        case .vertical:
          sizes[index].height = layoutAdding(sizes[index].height, extra)
        }
      }
    }
    let container = CellSize(
      width: proposal.width ?? naturalSize.width,
      height: proposal.height ?? naturalSize.height
    )

    var cursor = 0
    var placements: [LayoutPlacement] = []
    placements.reserveCapacity(items.count)
    for (index, pair) in zip(items, sizes).enumerated() {
      let (item, size) = pair
      let itemSpacing = index == items.index(before: items.endIndex) ? 0 : spacing
      let origin: CellPoint
      switch axis {
      case .horizontal:
        origin = CellPoint(
          x: cursor,
          y: alignedOffset(available: container.height, occupied: size.height, alignment: verticalAlignment)
        )
        cursor = layoutAdding(cursor, layoutAdding(size.width, itemSpacing))
      case .vertical:
        origin = CellPoint(
          x: alignedOffset(available: container.width, occupied: size.width, alignment: horizontalAlignment),
          y: cursor
        )
        cursor = layoutAdding(cursor, layoutAdding(size.height, itemSpacing))
      }
      placements.append(LayoutPlacement(nodeID: item.nodeID, frame: CellRect(origin: origin, size: size)))
    }
    return LayoutResult(size: container, placements: placements)
  }
}

/// Places one item in a frame with optional fixed dimensions.
public struct FrameLayout: Sendable, Hashable {
  /// The fixed width, or `nil` to use the proposal or content width.
  public var width: Int?
  /// The fixed height, or `nil` to use the proposal or content height.
  public var height: Int?
  /// The item's alignment within the frame.
  public var alignment: CellAlignment

  /// Creates a frame layout.
  public init(width: Int? = nil, height: Int? = nil, alignment: CellAlignment = .center) {
    precondition(width.map { $0 >= 0 } ?? true)
    precondition(height.map { $0 >= 0 } ?? true)
    self.width = width
    self.height = height
    self.alignment = alignment
  }

  /// Measures and places an item in the frame.
  @MainActor
  public func layout(_ item: LayoutItem, in proposal: ProposedCellSize, cache: LayoutCache) -> LayoutResult {
    let contentProposal = ProposedCellSize(
      width: width ?? proposal.width,
      height: height ?? proposal.height
    )
    let measuredSize = cache.measure(item, in: contentProposal)
    let frameSize = CellSize(
      width: width ?? proposal.width ?? measuredSize.width,
      height: height ?? proposal.height ?? measuredSize.height
    )
    let contentSize = cache.measure(
      item,
      in: ProposedCellSize(width: frameSize.width, height: frameSize.height)
    )
    let origin = CellPoint(
      x: alignedOffset(available: frameSize.width, occupied: contentSize.width, alignment: alignment.horizontal),
      y: alignedOffset(available: frameSize.height, occupied: contentSize.height, alignment: alignment.vertical)
    )
    return LayoutResult(
      size: frameSize,
      placements: [LayoutPlacement(nodeID: item.nodeID, frame: CellRect(origin: origin, size: contentSize))]
    )
  }
}

/// Places one item inside edge insets.
public struct PaddingLayout: Sendable, Hashable {
  /// The insets around the item.
  public var insets: EdgeInsets

  /// Creates a padding layout.
  public init(_ insets: EdgeInsets) {
    self.insets = insets
  }

  /// Measures and places an item inside the insets.
  @MainActor
  public func layout(_ item: LayoutItem, in proposal: ProposedCellSize, cache: LayoutCache) -> LayoutResult {
    let horizontalInsets = layoutAdding(insets.leading, insets.trailing)
    let verticalInsets = layoutAdding(insets.top, insets.bottom)
    let childProposal = ProposedCellSize(
      width: proposal.width.map { max(0, layoutSubtracting($0, horizontalInsets)) },
      height: proposal.height.map { max(0, layoutSubtracting($0, verticalInsets)) }
    )
    let childSize = cache.measure(item, in: childProposal)
    let size = CellSize(
      width: layoutAdding(childSize.width, horizontalInsets),
      height: layoutAdding(childSize.height, verticalInsets)
    )
    return LayoutResult(
      size: size,
      placements: [
        LayoutPlacement(
          nodeID: item.nodeID,
          frame: CellRect(
            origin: CellPoint(x: insets.leading, y: insets.top),
            size: childSize
          )
        )
      ]
    )
  }
}

/// Places items on top of each other.
public struct OverlayLayout: Sendable, Hashable {
  /// The alignment of each item in the overlay.
  public var alignment: CellAlignment

  /// Creates an overlay layout.
  public init(alignment: CellAlignment = .center) {
    self.alignment = alignment
  }

  /// Measures and places all items in one container.
  @MainActor
  public func layout(_ items: [LayoutItem], in proposal: ProposedCellSize, cache: LayoutCache) -> LayoutResult {
    let sizes = items.map { cache.measure($0, in: proposal) }
    let natural = CellSize(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.map(\.height).max() ?? 0
    )
    let size = proposal.replacingUnspecifiedDimensions(by: natural)
    let placements = zip(items, sizes).map { item, childSize in
      LayoutPlacement(
        nodeID: item.nodeID,
        frame: CellRect(
          x: alignedOffset(available: size.width, occupied: childSize.width, alignment: alignment.horizontal),
          y: alignedOffset(available: size.height, occupied: childSize.height, alignment: alignment.vertical),
          width: childSize.width,
          height: childSize.height
        )
      )
    }
    return LayoutResult(size: size, placements: placements)
  }
}
