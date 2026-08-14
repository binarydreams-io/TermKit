/// The visual elevation of a design surface.
public enum ElevationToken: Sendable, Hashable {
    /// No elevation.
    case flat
    /// A slightly raised surface.
    case raised
    /// A floating surface.
    case floating
}

/// A padded text surface with semantic elevation.
public struct SurfaceView: SemanticRenderable, View, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The displayed text.
    public var text: String
    /// The foreground color.
    public var foreground: RGBA
    /// The base background color.
    public var background: RGBA
    /// The content padding.
    public var padding: EdgeInsets
    /// The surface elevation.
    public var elevation: ElevationToken

    /// Creates a text surface.
    public init(
        text: String,
        foreground: RGBA,
        background: RGBA,
        id: SemanticID = "surface",
        padding: EdgeInsets = .zero,
        elevation: ElevationToken = .flat
    ) {
        self.id = id
        self.text = text
        self.foreground = foreground
        self.background = background
        self.padding = padding
        self.elevation = elevation
    }

    /// Returns the padded text size constrained by a proposal.
    /// - Complexity: O(*n*), where *n* is the text length.
    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let contentProposal = ProposedCellSize(
            width: proposal.width.map { max(0, $0 - padding.horizontal) },
            height: proposal.height.map { max(0, $0 - padding.vertical) }
        )
        let contentSize = Text(text).sizeThatFits(contentProposal)
        return CellSize(
            width: min(contentSize.width + padding.horizontal, proposal.width ?? .max),
            height: min(contentSize.height + padding.vertical, proposal.height ?? .max)
        )
    }

    @MainActor
    /// The primitive node descriptor for the surface.
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }

    /// Paints the surface and returns its semantic group.
    /// - Complexity: O(*w* × *h*), where the terms are the clipped dimensions.
    nonisolated public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let resolvedBackground: RGBA =
            switch elevation {
            case .flat: background
            case .raised: background.interpolated(to: .white, progress: 0.04)
            case .floating: background.interpolated(to: .white, progress: 0.08)
            }
        let style = CellStyle(foreground: .rgba(foreground), background: .rgba(resolvedBackground))
        let styleID = try resources.internPaintStyle(style)
        let blank = PackedCell.makeBlank(styleID: styleID)
        if let fillRect = context.clip.intersection(surface.bounds) {
            surface.clear(fillRect, with: blank)
        }
        let textOrigin = context.origin.offsetBy(dx: padding.leading, dy: padding.top)
        let textClip = context.clip.inset(by: padding)
        let child: SemanticNode
        #if DEBUG
            child = try context.withClipScope(origin: textOrigin, clip: textClip) { textContext in
                try Text(text, id: SemanticID(rawValue: "\(id.rawValue)-content"), style: style)
                    .paint(into: &surface, context: textContext, resources: &resources)
            }
        #else
            let textContext = PaintContext(
                clip: textClip,
                origin: textOrigin,
                opacity: context.opacity,
                zIndex: context.zIndex
            )
            child = try Text(text, id: SemanticID(rawValue: "\(id.rawValue)-content"), style: style)
                .paint(into: &surface, context: textContext, resources: &resources)
        #endif
        return SemanticNode(id: id, role: .group, label: text, frame: context.clip, children: [child])
    }
}

/// A vertical edge of a rectangular region.
public enum VerticalEdge: Sendable, Hashable {
    /// The leading edge.
    case leading
    /// The trailing edge.
    case trailing
}

/// A one-column vertical accent rail.
public struct AccentRail: SemanticRenderable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The edge that contains the rail.
    public var edge: VerticalEdge
    /// The rail style.
    public var style: CellStyle
    /// The rail glyph.
    public var glyph: Character

    /// Creates an accent rail.
    public init(
        style: CellStyle,
        id: SemanticID = "accent-rail",
        edge: VerticalEdge = .leading,
        glyph: Character = "▌"
    ) {
        self.id = id
        self.edge = edge
        self.style = style
        self.glyph = glyph
    }

    /// Returns a one-column size constrained by a proposal.
    /// - Complexity: O(1).
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: min(1, proposal.width ?? 1), height: proposal.height ?? 1)
    }

    /// Paints the rail and returns its semantic group.
    /// - Complexity: O(*h*), where *h* is the clipped height.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let x = edge == .leading ? 0 : max(0, context.clip.width - 1)
        let runs = (0..<context.clip.height).map { row in
            StyledRun(row == 0 ? String(glyph) : "\n\(glyph)", style: style)
        }
        let frame = try SurfaceTextPainter.paint(
            runs,
            into: &surface,
            context: context.translated(by: CellPoint(x: x)),
            resources: &resources
        )
        return SemanticNode(id: id, role: .group, label: "Accent", frame: frame)
    }
}

/// A one-row decorative bottom cap.
public struct BottomCap: SemanticRenderable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The requested cap width.
    public var width: Int
    /// The cap style.
    public var style: CellStyle
    /// A Boolean value that enables the lower-half block glyph.
    public var supportsHalfBlock: Bool

    /// Creates a bottom cap.
    public init(width: Int, style: CellStyle, id: SemanticID = "bottom-cap", supportsHalfBlock: Bool = true) {
        self.id = id
        self.width = max(0, width)
        self.style = style
        self.supportsHalfBlock = supportsHalfBlock
    }

    /// Returns the cap size constrained by a proposal.
    /// - Complexity: O(1).
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    /// Paints the cap and returns its semantic group.
    /// - Complexity: O(*w*), where *w* is the painted width.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let glyph = supportsHalfBlock ? "▄" : "─"
        let text = String(repeating: glyph, count: min(width, context.clip.width))
        let frame = try SurfaceTextPainter.paint([StyledRun(text, style: style)], into: &surface, context: context, resources: &resources)
        return SemanticNode(id: id, role: .group, label: "Bottom cap", frame: frame)
    }
}

/// A semantic list row with selection and interaction states.
public struct SelectionRow: SemanticRenderable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The row label.
    public var label: String
    /// A Boolean value that indicates selection.
    public var isSelected: Bool
    /// A Boolean value that indicates the current value.
    public var isCurrent: Bool
    /// A Boolean value that indicates a disabled row.
    public var isDisabled: Bool
    /// A Boolean value that indicates pointer hover.
    public var isHovered: Bool
    /// The default row style.
    public var normalStyle: CellStyle
    /// The emphasized row style.
    public var selectedStyle: CellStyle

    /// Creates a selection row.
    public init(
        id: SemanticID,
        label: String,
        selectedStyle: CellStyle,
        isSelected: Bool = false,
        isCurrent: Bool = false,
        isDisabled: Bool = false,
        isHovered: Bool = false,
        normalStyle: CellStyle = .default
    ) {
        self.id = id
        self.label = label
        self.isSelected = isSelected
        self.isCurrent = isCurrent
        self.isDisabled = isDisabled
        self.isHovered = isHovered
        self.normalStyle = normalStyle
        self.selectedStyle = selectedStyle
    }

    /// Returns the row size constrained by a proposal.
    /// - Complexity: O(*n*), where *n* is the label length.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = 2 + TerminalWidth.width(of: label)
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    /// Paints the row and returns its semantic list item.
    /// - Complexity: O(*n*), where *n* is the label length.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let marker = isCurrent ? "▌ " : "  "
        let style = isSelected || isCurrent || isHovered ? selectedStyle : normalStyle
        let frame = try SurfaceTextPainter.paint(
            [StyledRun(marker + label, style: style)],
            into: &surface,
            context: context,
            resources: &resources
        )
        var state: SemanticState = []
        if isSelected { state.insert(.selected) }
        if isCurrent { state.insert(.current) }
        if isDisabled { state.insert(.disabled) }
        if isHovered { state.insert(.hovered) }
        return SemanticNode(
            id: id,
            role: .listItem,
            label: label,
            state: state,
            actions: isDisabled ? [] : [.activate, .focus],
            frame: frame
        )
    }
}

/// A prioritized field in a metadata line.
public struct MetadataField: Sendable, Hashable {
    /// The field text.
    public var text: String
    /// The retention priority when space is limited.
    public var priority: Int
    /// The minimum useful display width.
    public var minimumWidth: Int

    /// Creates a metadata field.
    /// - Complexity: O(*n*), where *n* is the text length.
    public init(_ text: String, priority: Int = 0, minimumWidth: Int? = nil) {
        self.text = text
        self.priority = priority
        let textWidth = TerminalWidth.width(of: text)
        self.minimumWidth = min(max(0, minimumWidth ?? textWidth), textWidth)
    }
}

/// A single-line collection of prioritized metadata fields.
public struct MetadataLine: SemanticRenderable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The metadata fields.
    public var fields: [MetadataField]
    /// The separator between visible fields.
    public var separator: String
    /// The line style.
    public var style: CellStyle

    /// Creates a metadata line.
    public init(
        fields: [MetadataField],
        style: CellStyle,
        id: SemanticID = "metadata",
        separator: String = " · "
    ) {
        self.id = id
        self.fields = fields
        self.separator = separator
        self.style = style
    }

    /// Returns fields retained at the specified width.
    /// - Complexity: O(*n*²), where *n* is the number of fields.
    public func visibleFields(in width: Int) -> [MetadataField] {
        guard width > 0 else { return [] }
        let positions = Dictionary(uniqueKeysWithValues: fields.indices.map { ($0, $0) })
        var included = Array(fields.indices)
        func requiredWidth() -> Int {
            included.reduce(0) { $0 + TerminalWidth.width(of: fields[$1].text) }
                + max(0, included.count - 1) * TerminalWidth.width(of: separator)
        }
        while requiredWidth() > width, included.count > 1,
            let removable = included.min(by: {
                if fields[$0].priority != fields[$1].priority { return fields[$0].priority < fields[$1].priority }
                return positions[$0, default: 0] > positions[$1, default: 0]
            })
        {
            included.removeAll { $0 == removable }
        }
        return included.sorted().map { fields[$0] }
    }

    /// Returns visible metadata text clipped to a width.
    /// - Complexity: O(*n*²), where *n* is the number of fields.
    public func text(in width: Int) -> String {
        TerminalWidth.prefix(
            of: visibleFields(in: width).map(\.text).joined(separator: separator),
            fitting: max(0, width)
        )
    }

    /// Returns the metadata line size constrained by a proposal.
    /// - Complexity: O(*n*), where *n* is the total field text length.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let naturalWidth = TerminalWidth.width(of: fields.map(\.text).joined(separator: separator))
        let width = min(naturalWidth, proposal.width ?? naturalWidth)
        return CellSize(width: width, height: min(1, proposal.height ?? 1))
    }

    /// Paints visible metadata and returns its semantic text node.
    /// - Complexity: O(*n*²), where *n* is the number of fields.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let visibleText = text(in: context.clip.width)
        let frame = try SurfaceTextPainter.paint(
            [StyledRun(visibleText, style: style)],
            into: &surface,
            context: context,
            resources: &resources
        )
        return SemanticNode(id: id, role: .text, label: visibleText, frame: frame)
    }
}

/// A keyboard shortcut and its action label.
public struct KeyHint: SemanticRenderable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The keyboard shortcut.
    public var shortcut: KeyboardShortcut
    /// The action label.
    public var label: String
    /// The shortcut style.
    public var keyStyle: CellStyle
    /// The label style.
    public var labelStyle: CellStyle

    /// Creates a key hint.
    public init(
        shortcut: KeyboardShortcut,
        label: String,
        id: SemanticID = "key-hint",
        keyStyle: CellStyle = .default,
        labelStyle: CellStyle = .default
    ) {
        self.id = id
        self.shortcut = shortcut
        self.label = label
        self.keyStyle = keyStyle
        self.labelStyle = labelStyle
    }

    /// Returns the key-hint size constrained by a proposal.
    /// - Complexity: O(*n*), where *n* is the rendered text length.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = TerminalWidth.width(of: shortcut.normalizedDescription + "  " + label)
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    /// Paints the key hint and returns its semantic text node.
    /// - Complexity: O(*n*), where *n* is the rendered text length.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let key = shortcut.normalizedDescription
        let frame = try SurfaceTextPainter.paint(
            [StyledRun(key, style: keyStyle), StyledRun("  \(label)", style: labelStyle)],
            into: &surface,
            context: context,
            resources: &resources
        )
        return SemanticNode(id: id, role: .text, label: "\(key), \(label)", frame: frame)
    }
}

/// The semantic kind of a status value.
public enum StatusKind: Sendable, Hashable {
    /// A neutral status.
    case neutral
    /// An informational status.
    case info
    /// A successful status.
    case success
    /// A warning status.
    case warning
    /// An error status.
    case error
}

/// A compact, padded status label.
public struct StatusPill: SemanticRenderable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The status text.
    public var text: String
    /// The semantic status kind.
    public var kind: StatusKind
    /// The pill style.
    public var style: CellStyle

    /// Creates a status pill.
    public init(text: String, style: CellStyle, id: SemanticID = "status", kind: StatusKind = .neutral) {
        self.id = id
        self.text = text
        self.kind = kind
        self.style = style
    }

    /// Returns the pill size constrained by a proposal.
    /// - Complexity: O(*n*), where *n* is the text length.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = TerminalWidth.width(of: text) + 2
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    /// Paints the status pill and returns its semantic status node.
    /// - Complexity: O(*n*), where *n* is the text length.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let frame = try SurfaceTextPainter.paint(
            [StyledRun(" \(text) ", style: style)],
            into: &surface,
            context: context,
            resources: &resources
        )
        return SemanticNode(id: id, role: .status, label: text, value: String(describing: kind), frame: frame)
    }
}
