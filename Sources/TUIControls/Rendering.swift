import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public struct StyledRun: Sendable, Hashable {
    public var text: String
    public var style: CellStyle

    public init(_ text: String, style: CellStyle = .default) {
        self.text = text
        self.style = style
    }
}

public struct ControlRenderResources: Sendable {
    public var graphemes: GraphemeInterner
    public var styles: StyleInterner
    public var paintStyle: PaintStyle

    public init(
        graphemes: GraphemeInterner = GraphemeInterner(),
        styles: StyleInterner = StyleInterner(),
        paintStyle: PaintStyle = PaintStyle()
    ) {
        self.graphemes = graphemes
        self.styles = styles
        self.paintStyle = paintStyle
    }

    public mutating func internPaintStyle(_ style: CellStyle) throws -> StyleID {
        try styles.intern(paintStyle.applying(to: style))
    }
}

public struct PaintStyle: Sendable, Hashable {
    public var foreground: Color?
    public var background: Color?

    public init(foreground: Color? = nil, background: Color? = nil) {
        self.foreground = foreground
        self.background = background
    }

    public func applying(to style: CellStyle) -> CellStyle {
        CellStyle(
            foreground: foreground ?? style.foreground,
            background: background ?? style.background,
            attributes: style.attributes
        )
    }

    public func overriding(foreground: Color?, background: Color?) -> PaintStyle {
        PaintStyle(
            foreground: foreground ?? self.foreground,
            background: background ?? self.background
        )
    }
}

public protocol SemanticRenderable: Sendable {
    func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize

    func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode
}

public protocol ControlActivatable: Sendable {
    @MainActor
    @discardableResult
    func activate() -> Bool
}

public protocol ControlPointerActivatable: Sendable {
    @MainActor
    @discardableResult
    func activate(at point: CellPoint) -> Bool
}

public protocol ControlFocusHandler: Sendable {
    @MainActor
    func controlFocusChanged(_ isFocused: Bool)
}

@MainActor
public protocol ControlFocusTrapping: Sendable {
    var trapsControlFocus: Bool { get }
}

public enum ControlInputEvent: Sendable, Hashable {
    case text(String)
    case paste(String)
    case submit
    case newline
    case cancel
    case moveUp
    case moveDown
    case moveLeft
    case moveRight
    case deleteBackward
}

@MainActor
public protocol ControlInputHandler: Sendable {
    @discardableResult
    func handleControlInput(_ event: ControlInputEvent) -> Bool
}

@MainActor
public protocol ControlSemanticActionHandler: Sendable {
    @discardableResult
    func handleSemanticAction(_ action: SemanticAction) -> Bool
}

@MainActor
public protocol ControlShortcutHandler: Sendable {
    @discardableResult
    func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool
}

public struct Text: SemanticRenderable, TUIViewGraph.View, Hashable {
    public var id: SemanticID
    public var runs: [StyledRun]

    nonisolated public init(_ text: String, id: SemanticID = "text", style: CellStyle = .default) {
        self.init(id: id, runs: [StyledRun(text, style: style)])
    }

    nonisolated public init(id: SemanticID = "text", runs: [StyledRun]) {
        self.id = id
        self.runs = runs
    }

    nonisolated public var plainText: String {
        runs.map(\.text).joined()
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let lines = plainText.split(separator: "\n", omittingEmptySubsequences: false)
        let natural = CellSize(
            width: lines.map { TerminalWidth.width(of: String($0)) }.max() ?? 0,
            height: max(1, lines.count)
        )
        return CellSize(
            width: min(natural.width, proposal.width ?? natural.width),
            height: min(natural.height, proposal.height ?? natural.height)
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
        let frame = try SurfaceTextPainter.paint(
            runs,
            into: &surface,
            context: context,
            resources: &resources
        )
        return SemanticNode(id: id, role: .text, label: plainText, frame: frame)
    }
}

public enum SurfaceTextPainter {
    public static func paint(
        _ runs: [StyledRun],
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> CellRect? {
        var x = 0
        var y = 0
        var painted: CellRect?

        for run in runs {
            let styleID = try resources.internPaintStyle(run.style)
            for character in run.text {
                if character == "\n" {
                    x = 0
                    y += 1
                    continue
                }

                let originalWidth = TerminalWidth.width(of: character)
                guard originalWidth > 0 else { continue }
                let point = context.origin.offsetBy(dx: x, dy: y)
                let originalAtom = CellRect(x: point.x, y: point.y, width: originalWidth, height: 1)
                let isClippedWideGrapheme = originalWidth == 2
                    && (!context.clip.contains(originalAtom) || !surface.bounds.contains(originalAtom))
                    && context.clip.contains(point)
                    && surface.bounds.contains(point)
                let renderedCharacter: Character = isClippedWideGrapheme ? "�" : character
                let width = isClippedWideGrapheme ? 1 : originalWidth
                let atom = CellRect(x: point.x, y: point.y, width: width, height: 1)
                if context.clip.contains(atom), surface.bounds.contains(atom) {
                    let graphemeID = try resources.graphemes.intern(renderedCharacter)
                    _ = try surface.write(
                        graphemeID: graphemeID,
                        styleID: styleID,
                        displayWidth: UInt8(width),
                        at: point,
                        clip: context.clip
                    )
                    painted = painted.map { $0.union(atom) } ?? atom
                }
                x += originalWidth
            }
        }
        return painted
    }

    public static func cellWidth(of character: Character) -> Int {
        TerminalWidth.width(of: character)
    }

    public static func cellWidth(of text: String) -> Int {
        text.reduce(into: 0) { width, character in
            if character != "\n" { width += TerminalWidth.width(of: character) }
        }
    }
}
