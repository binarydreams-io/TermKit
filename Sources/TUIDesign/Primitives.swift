import TUIControls
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public enum ElevationToken: Sendable, Hashable {
    case flat
    case raised
    case floating
}

public struct Surface: SemanticRenderable, TUIViewGraph.View, Hashable {
    public var id: SemanticID
    public var text: String
    public var foreground: RGBA
    public var background: RGBA
    public var padding: EdgeInsets
    public var elevation: ElevationToken

    public init(
        id: SemanticID = "surface",
        text: String,
        foreground: RGBA,
        background: RGBA,
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
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let resolvedBackground: RGBA = switch elevation {
        case .flat: background
        case .raised: background.interpolated(to: .white, progress: 0.04)
        case .floating: background.interpolated(to: .white, progress: 0.08)
        }
        let style = CellStyle(foreground: .rgba(foreground), background: .rgba(resolvedBackground))
        let styleID = try resources.internPaintStyle(style)
        let blank = PackedCell.blank(styleID: styleID)
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
            origin: textOrigin,
            clip: textClip,
            opacity: context.opacity,
            zIndex: context.zIndex
        )
        child = try Text(text, id: SemanticID(rawValue: "\(id.rawValue)-content"), style: style)
            .paint(into: &surface, context: textContext, resources: &resources)
        #endif
        return SemanticNode(id: id, role: .group, label: text, frame: context.clip, children: [child])
    }
}

public enum VerticalEdge: Sendable, Hashable {
    case leading
    case trailing
}

public struct AccentRail: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var edge: VerticalEdge
    public var style: CellStyle
    public var glyph: Character

    public init(
        id: SemanticID = "accent-rail",
        edge: VerticalEdge = .leading,
        style: CellStyle,
        glyph: Character = "▌"
    ) {
        self.id = id
        self.edge = edge
        self.style = style
        self.glyph = glyph
    }

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: min(1, proposal.width ?? 1), height: proposal.height ?? 1)
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
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

public struct BottomCap: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var width: Int
    public var style: CellStyle
    public var supportsHalfBlock: Bool

    public init(id: SemanticID = "bottom-cap", width: Int, style: CellStyle, supportsHalfBlock: Bool = true) {
        self.id = id
        self.width = max(0, width)
        self.style = style
        self.supportsHalfBlock = supportsHalfBlock
    }

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let glyph = supportsHalfBlock ? "▄" : "─"
        let text = String(repeating: glyph, count: min(width, context.clip.width))
        let frame = try SurfaceTextPainter.paint([StyledRun(text, style: style)], into: &surface, context: context, resources: &resources)
        return SemanticNode(id: id, role: .group, label: "Bottom cap", frame: frame)
    }
}

public struct SelectionRow: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var label: String
    public var isSelected: Bool
    public var isCurrent: Bool
    public var isDisabled: Bool
    public var isHovered: Bool
    public var normalStyle: CellStyle
    public var selectedStyle: CellStyle

    public init(
        id: SemanticID,
        label: String,
        isSelected: Bool = false,
        isCurrent: Bool = false,
        isDisabled: Bool = false,
        isHovered: Bool = false,
        normalStyle: CellStyle = .default,
        selectedStyle: CellStyle
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

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = 2 + TerminalWidth.width(of: label)
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
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

public struct MetadataField: Sendable, Hashable {
    public var text: String
    public var priority: Int
    public var minimumWidth: Int

    public init(_ text: String, priority: Int = 0, minimumWidth: Int? = nil) {
        self.text = text
        self.priority = priority
        let textWidth = TerminalWidth.width(of: text)
        self.minimumWidth = min(max(0, minimumWidth ?? textWidth), textWidth)
    }
}

public struct MetadataLine: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var fields: [MetadataField]
    public var separator: String
    public var style: CellStyle

    public init(
        id: SemanticID = "metadata",
        fields: [MetadataField],
        separator: String = " · ",
        style: CellStyle
    ) {
        self.id = id
        self.fields = fields
        self.separator = separator
        self.style = style
    }

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

    public func text(in width: Int) -> String {
        TerminalWidth.prefix(
            of: visibleFields(in: width).map(\.text).joined(separator: separator),
            fitting: max(0, width)
        )
    }

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let naturalWidth = TerminalWidth.width(of: fields.map(\.text).joined(separator: separator))
        let width = min(naturalWidth, proposal.width ?? naturalWidth)
        return CellSize(width: width, height: min(1, proposal.height ?? 1))
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
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

public struct KeyHint: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var shortcut: KeyboardShortcut
    public var label: String
    public var keyStyle: CellStyle
    public var labelStyle: CellStyle

    public init(
        id: SemanticID = "key-hint",
        shortcut: KeyboardShortcut,
        label: String,
        keyStyle: CellStyle = .default,
        labelStyle: CellStyle = .default
    ) {
        self.id = id
        self.shortcut = shortcut
        self.label = label
        self.keyStyle = keyStyle
        self.labelStyle = labelStyle
    }

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = TerminalWidth.width(of: shortcut.normalizedDescription + "  " + label)
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
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

public enum StatusKind: Sendable, Hashable {
    case neutral
    case info
    case success
    case warning
    case error
}

public struct StatusPill: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var text: String
    public var kind: StatusKind
    public var style: CellStyle

    public init(id: SemanticID = "status", text: String, kind: StatusKind = .neutral, style: CellStyle) {
        self.id = id
        self.text = text
        self.kind = kind
        self.style = style
    }

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = TerminalWidth.width(of: text) + 2
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
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
