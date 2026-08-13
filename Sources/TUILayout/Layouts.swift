import TUIFoundation

public struct StackLayout: Sendable, Hashable {
    public var axis: StackAxis
    public var spacing: Int
    public var horizontalAlignment: HorizontalCellAlignment
    public var verticalAlignment: VerticalCellAlignment

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

    @MainActor
    public func layout(
        _ items: [LayoutItem],
        in proposal: ProposedCellSize = .unspecified,
        cache: LayoutCache
    ) -> LayoutResult {
        let childProposal: ProposedCellSize
        switch axis {
        case .horizontal:
            childProposal = ProposedCellSize(height: proposal.height)
        case .vertical:
            childProposal = ProposedCellSize(width: proposal.width)
        }
        let sizes = items.map { cache.measure($0, in: childProposal) }
        let totalSpacing = layoutMultiplying(spacing, max(0, items.count - 1))
        let naturalSize: CellSize
        switch axis {
        case .horizontal:
            naturalSize = CellSize(
                width: sizes.reduce(totalSpacing) { layoutAdding($0, $1.width) },
                height: sizes.map(\.height).max() ?? 0
            )
        case .vertical:
            naturalSize = CellSize(
                width: sizes.map(\.width).max() ?? 0,
                height: sizes.reduce(totalSpacing) { layoutAdding($0, $1.height) }
            )
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

public struct FrameLayout: Sendable, Hashable {
    public var width: Int?
    public var height: Int?
    public var alignment: CellAlignment

    public init(width: Int? = nil, height: Int? = nil, alignment: CellAlignment = .center) {
        precondition(width.map { $0 >= 0 } ?? true)
        precondition(height.map { $0 >= 0 } ?? true)
        self.width = width
        self.height = height
        self.alignment = alignment
    }

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

public struct PaddingLayout: Sendable, Hashable {
    public var insets: EdgeInsets

    public init(_ insets: EdgeInsets) {
        self.insets = insets
    }

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

public struct OverlayLayout: Sendable, Hashable {
    public var alignment: CellAlignment

    public init(alignment: CellAlignment = .center) {
        self.alignment = alignment
    }

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

public func clipped(_ result: LayoutResult, to rect: CellRect? = nil) -> LayoutResult {
    let clip = rect ?? CellRect(origin: .zero, size: result.size)
    debugValidateLayoutRect(clip)
    return LayoutResult(
        size: result.size,
        placements: result.placements.map {
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
