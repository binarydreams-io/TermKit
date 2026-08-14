/// A text segment with one cell style.
public struct StyledRun: Sendable, Hashable {
    /// The segment text.
    public var text: String
    /// The style applied to the segment.
    public var style: CellStyle

    /// Creates a styled text segment.
    public init(_ text: String, style: CellStyle = .default) {
        self.text = text
        self.style = style
    }
}

/// Mutable interners and paint overrides shared during control rendering.
public struct ControlRenderResources: Sendable {
    /// The grapheme interner.
    public var graphemes: GraphemeInterner
    /// The style interner.
    public var styles: StyleInterner
    /// The current paint overrides.
    public var paintStyle: PaintStyle
    /// The terminal color capability used by specialized painters.
    public var colorCapability: TerminalColorCapability

    /// Creates control render resources.
    public init(
        graphemes: GraphemeInterner = GraphemeInterner(),
        styles: StyleInterner = StyleInterner(),
        paintStyle: PaintStyle = PaintStyle(),
        colorCapability: TerminalColorCapability = .trueColor
    ) {
        self.graphemes = graphemes
        self.styles = styles
        self.paintStyle = paintStyle
        self.colorCapability = colorCapability
    }

    /// Applies paint overrides and interns the resulting style.
    /// - Complexity: O(1) on average.
    public mutating func internPaintStyle(_ style: CellStyle) throws -> StyleID {
        try styles.intern(paintStyle.applying(to: style))
    }
}

/// Optional foreground and background paint overrides.
public struct PaintStyle: Sendable, Hashable {
    /// The foreground override.
    public var foreground: Color?
    /// The background override.
    public var background: Color?

    /// Creates paint overrides.
    public init(foreground: Color? = nil, background: Color? = nil) {
        self.foreground = foreground
        self.background = background
    }

    /// Applies these overrides to a cell style.
    /// - Complexity: O(1).
    public func applying(to style: CellStyle) -> CellStyle {
        CellStyle(
            foreground: foreground ?? style.foreground,
            background: background ?? style.background,
            attributes: style.attributes
        )
    }

    /// Returns paint overrides with new non-`nil` values applied.
    /// - Complexity: O(1).
    public func overriding(foreground: Color?, background: Color?) -> PaintStyle {
        PaintStyle(
            foreground: foreground ?? self.foreground,
            background: background ?? self.background
        )
    }
}

/// A control that measures, paints, and exposes semantic output.
public protocol SemanticRenderable: Sendable {
    /// Returns the control size for a proposed size.
    @MainActor
    func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize

    /// Paints the control and returns its semantic node.
    @MainActor
    func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode
}

/// A control that supports activation without a pointer location.
public protocol ControlActivatable: Sendable {
    /// Activates the control and reports whether it handled the action.
    @MainActor
    @discardableResult
    func activate() -> Bool
}

/// A control that supports activation at a pointer location.
public protocol ControlPointerActivatable: Sendable {
    /// Activates the control at a point and reports whether it handled the action.
    @MainActor
    @discardableResult
    func activate(at point: CellPoint) -> Bool
}

/// A control that receives focus changes.
public protocol ControlFocusHandler: Sendable {
    /// Updates the control's focused state.
    @MainActor
    func controlFocusChanged(_ isFocused: Bool)
}

/// A control that can trap focus within its subtree.
@MainActor
public protocol ControlFocusTrapping: Sendable {
    /// A value that indicates whether the control traps focus.
    var trapsControlFocus: Bool { get }
}

/// An input event routed to a control.
public enum ControlInputEvent: Sendable, Hashable {
    /// Inserts typed text.
    case text(String)
    /// Inserts pasted text.
    case paste(String)
    /// Submits the control's value.
    case submit
    /// Inserts a newline.
    case newline
    /// Cancels the current operation.
    case cancel
    /// Moves upward.
    case moveUp
    /// Moves downward.
    case moveDown
    /// Moves left.
    case moveLeft
    /// Moves right.
    case moveRight
    /// Deletes content before the caret.
    case deleteBackward
}

/// A control that handles routed input events.
@MainActor
public protocol ControlInputHandler: Sendable {
    /// Handles an input event and reports whether it was consumed.
    @discardableResult
    func handleControlInput(_ event: ControlInputEvent) -> Bool
}

/// A control that handles semantic actions.
@MainActor
public protocol ControlSemanticActionHandler: Sendable {
    /// Handles a semantic action and reports whether it was consumed.
    @discardableResult
    func handleSemanticAction(_ action: SemanticAction) -> Bool
}

/// A control that handles keyboard shortcuts.
@MainActor
public protocol ControlShortcutHandler: Sendable {
    /// Handles a keyboard shortcut and reports whether it was consumed.
    @discardableResult
    func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool
}

/// Styled text that can measure, paint, and expose semantic output.
public struct Text: SemanticRenderable, View, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The styled text segments.
    public var runs: [StyledRun]

    /// Creates one styled text segment.
    nonisolated public init(_ text: String, id: SemanticID = "text", style: CellStyle = .default) {
        self.init(runs: [StyledRun(text, style: style)], id: id)
    }

    /// Creates text from styled segments.
    nonisolated public init(runs: [StyledRun], id: SemanticID = "text") {
        self.id = id
        self.runs = runs
    }

    /// The unstyled concatenation of all segments.
    /// - Complexity: O(n), where n is the total text length.
    nonisolated public var plainText: String {
        runs.map(\.text).joined()
    }

    /// Returns the text size for a proposed size.
    /// - Complexity: O(n), where n is the total text length.
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

    /// The node descriptor for the text.
    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }

    /// Paints the text and returns its semantic node.
    /// - Complexity: O(n), where n is the total text length.
    nonisolated public func paint(
        into surface: inout Surface,
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

/// Utilities for painting styled text into a surface.
public enum SurfaceTextPainter {
    /// Paints styled runs and returns the painted bounds.
    /// - Complexity: O(n), where n is the total text length.
    public static func paint(
        _ runs: [StyledRun],
        into surface: inout Surface,
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
                let isClippedWideGrapheme =
                    originalWidth == 2
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
                        at: point,
                        styleID: styleID,
                        displayWidth: UInt8(width),
                        clip: context.clip
                    )
                    painted = painted.map { $0.union(atom) } ?? atom
                }
                x += originalWidth
            }
        }
        return painted
    }

    /// Returns the terminal-cell width of a character.
    /// - Complexity: O(1).
    public static func cellWidth(of character: Character) -> Int {
        TerminalWidth.width(of: character)
    }

    /// Returns the total terminal-cell width, excluding newlines.
    /// - Complexity: O(n), where n is the text length.
    public static func cellWidth(of text: String) -> Int {
        text.reduce(into: 0) { width, character in
            if character != "\n" { width += TerminalWidth.width(of: character) }
        }
    }
}
