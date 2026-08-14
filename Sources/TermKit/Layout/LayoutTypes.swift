/// Proposes optional dimensions for measuring layout content.
public struct ProposedCellSize: Sendable, Hashable {
  /// The proposed width, or `nil` when unspecified.
  public var width: Int?
  /// The proposed height, or `nil` when unspecified.
  public var height: Int?

  /// Creates a proposed cell size.
  public init(width: Int? = nil, height: Int? = nil) {
    precondition(width.map { $0 >= 0 } ?? true)
    precondition(height.map { $0 >= 0 } ?? true)
    self.width = width
    self.height = height
  }

  /// A proposal with no specified dimensions.
  public static let unspecified = ProposedCellSize()
  /// A proposal with zero width and height.
  public static let zero = ProposedCellSize(width: 0, height: 0)

  /// Replaces unspecified dimensions with dimensions from a fallback size.
  public func replacingUnspecifiedDimensions(by size: CellSize) -> CellSize {
    CellSize(width: width ?? size.width, height: height ?? size.height)
  }
}

/// Aligns content horizontally within available cells.
public enum HorizontalCellAlignment: Sendable, Hashable {
  /// Aligns content with the leading edge.
  case leading
  /// Centers content horizontally.
  case center
  /// Aligns content with the trailing edge.
  case trailing
}

/// Aligns content vertically within available cells.
public enum VerticalCellAlignment: Sendable, Hashable {
  /// Aligns content with the top edge.
  case top
  /// Centers content vertically.
  case center
  /// Aligns content with the bottom edge.
  case bottom
}

/// Combines horizontal and vertical cell alignment.
public struct CellAlignment: Sendable, Hashable {
  /// The horizontal alignment.
  public var horizontal: HorizontalCellAlignment
  /// The vertical alignment.
  public var vertical: VerticalCellAlignment

  /// Creates a cell alignment.
  public init(
    horizontal: HorizontalCellAlignment = .center,
    vertical: VerticalCellAlignment = .center
  ) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  /// Centers content on both axes.
  public static let center = CellAlignment()
  /// Aligns content with the top-leading corner.
  public static let topLeading = CellAlignment(horizontal: .leading, vertical: .top)
  /// Aligns content with the bottom-trailing corner.
  public static let bottomTrailing = CellAlignment(horizontal: .trailing, vertical: .bottom)
}

/// Wraps a node and its measurement operation for layout.
public struct LayoutItem: Sendable {
  /// The identifier of the measured node.
  public let nodeID: NodeID
  let spacerMinimumLength: Int?
  private let generationBody: @MainActor @Sendable () -> UInt64
  private let measureBody: @MainActor @Sendable (ProposedCellSize) -> CellSize

  /// Creates an item with a custom measurement operation.
  public init(nodeID: NodeID, measure: @escaping @MainActor @Sendable (_ proposal: ProposedCellSize) -> CellSize) {
    self.nodeID = nodeID
    self.spacerMinimumLength = nil
    self.generationBody = { 0 }
    self.measureBody = measure
  }

  /// Creates an item that tracks a mounted node's layout generation.
  @MainActor
  public init(node: MountedNode, measure: @escaping @MainActor @Sendable (_ proposal: ProposedCellSize) -> CellSize) {
    self.nodeID = node.id
    self.spacerMinimumLength = Self.spacerMinimumLength(in: node)
    self.generationBody = { node.layoutGeneration }
    self.measureBody = measure
  }

  /// Creates an item with a fixed maximum size.
  public init(nodeID: NodeID, size: CellSize) {
    self.init(nodeID: nodeID) { proposal in
      CellSize(
        width: min(size.width, proposal.width ?? size.width),
        height: min(size.height, proposal.height ?? size.height)
      )
    }
  }

  /// Creates a node-backed item with a fixed maximum size.
  @MainActor
  public init(node: MountedNode, size: CellSize) {
    self.init(node: node) { proposal in
      CellSize(
        width: min(size.width, proposal.width ?? size.width),
        height: min(size.height, proposal.height ?? size.height)
      )
    }
  }

  /// Measures the item for a proposed size.
  @MainActor
  public func measure(in proposal: ProposedCellSize) -> CellSize {
    measureBody(proposal)
  }

  @MainActor
  var layoutGeneration: UInt64 {
    generationBody()
  }

  @MainActor
  private static func spacerMinimumLength(in node: MountedNode) -> Int? {
    if let spacer = node.value(as: SpacerLayoutValue.self) {
      return spacer.minimumLength
    }
    guard node.primitive == nil, node.children.count == 1, let child = node.children.first else {
      return nil
    }
    return spacerMinimumLength(in: child)
  }
}

/// Places a node in a layout result.
public struct LayoutPlacement: Sendable, Hashable {
  /// The identifier of the placed node.
  public var nodeID: NodeID
  /// The node's frame in container coordinates.
  public var frame: CellRect
  /// The optional clipping rectangle in container coordinates.
  public var clip: CellRect?

  /// Creates a layout placement.
  public init(nodeID: NodeID, frame: CellRect, clip: CellRect? = nil) {
    debugValidateLayoutRect(frame)
    if let clip {
      debugValidateLayoutRect(clip)
    }
    self.nodeID = nodeID
    self.frame = frame
    self.clip = clip
  }
}

/// Contains a container size and its child placements.
public struct LayoutResult: Sendable, Hashable {
  /// The size of the layout container.
  public var size: CellSize
  /// The placements of nodes in the container.
  public var placements: [LayoutPlacement]

  /// Creates a layout result.
  public init(size: CellSize, placements: [LayoutPlacement]) {
    #if DEBUG
    for placement in placements {
      debugValidateLayoutRect(placement.frame)
      if let clip = placement.clip {
        debugValidateLayoutRect(clip)
      }
    }
    #endif
    self.size = size
    self.placements = placements
  }

  /// Returns a layout result with a clipping rectangle applied to every placement.
  public func clipped(to rect: CellRect? = nil) -> LayoutResult {
    let clip = rect ?? CellRect(origin: .zero, size: size)
    debugValidateLayoutRect(clip)
    return LayoutResult(
      size: size,
      placements: placements.map {
        var placement = $0
        if let existingClip = placement.clip {
          debugValidateLayoutRect(existingClip)
          placement.clip = existingClip.intersection(clip) ?? .zero
        } else {
          placement.clip = clip
        }
        return placement
      }
    )
  }
}

@inline(__always)
func layoutAdding(_ lhs: Int, _ rhs: Int) -> Int {
  #if DEBUG
  let (result, overflow) = lhs.addingReportingOverflow(rhs)
  precondition(overflow == false, "Layout geometry exceeds the Int cell range.")
  return result
  #else
  lhs + rhs
  #endif
}

@inline(__always)
func layoutSubtracting(_ lhs: Int, _ rhs: Int) -> Int {
  #if DEBUG
  let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
  precondition(overflow == false, "Layout geometry exceeds the Int cell range.")
  return result
  #else
  lhs - rhs
  #endif
}

@inline(__always)
func layoutMultiplying(_ lhs: Int, _ rhs: Int) -> Int {
  #if DEBUG
  let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
  precondition(overflow == false, "Layout geometry exceeds the Int cell range.")
  return result
  #else
  lhs * rhs
  #endif
}

@inline(__always)
func debugValidateLayoutRect(_ rect: CellRect) {
  #if DEBUG
  let (_, xOverflow) = rect.origin.x.addingReportingOverflow(rect.size.width)
  let (_, yOverflow) = rect.origin.y.addingReportingOverflow(rect.size.height)
  precondition(xOverflow == false && yOverflow == false, "Layout rectangle exceeds the Int cell range.")
  #endif
}

/// Selects the primary axis of a stack.
public enum StackAxis: Sendable, Hashable {
  /// Arranges items from leading to trailing.
  case horizontal
  /// Arranges items from top to bottom.
  case vertical
}

func alignedOffset(available: Int, occupied: Int, alignment: HorizontalCellAlignment) -> Int {
  switch alignment {
  case .leading: 0
  case .center: max(0, (available - occupied) / 2)
  case .trailing: max(0, available - occupied)
  }
}

func alignedOffset(available: Int, occupied: Int, alignment: VerticalCellAlignment) -> Int {
  switch alignment {
  case .top: 0
  case .center: max(0, (available - occupied) / 2)
  case .bottom: max(0, available - occupied)
  }
}
