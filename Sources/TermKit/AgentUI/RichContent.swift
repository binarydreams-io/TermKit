/// The wrapping behavior of agent code content.
public enum AgentCodeWrapPolicy: String, Sendable, Hashable, CaseIterable {
    /// Keeps each source line on one display row.
    case noWrap
    /// Wraps source lines to the available width.
    case wrap
}

/// Source code and its presentation options.
public struct AgentCodeBlock: Sendable, Hashable {
    /// The source code.
    public var text: String
    /// The source language, if known.
    public var language: String?
    /// The block title, if available.
    public var title: String?
    /// A Boolean value that indicates whether line numbers are visible.
    public var showsLineNumbers: Bool
    /// A Boolean value that indicates whether text selection is supported.
    public var supportsSelection: Bool
    /// The selected character range, if any.
    public var selection: Range<Int>?
    /// A Boolean value that indicates whether copying is enabled.
    public var isCopyEnabled: Bool
    /// The code wrapping policy.
    public var wrapPolicy: AgentCodeWrapPolicy

    /// Creates an agent code block.
    nonisolated public init(
        text: String,
        language: String? = nil,
        title: String? = nil,
        showsLineNumbers: Bool = false,
        supportsSelection: Bool = true,
        selection: Range<Int>? = nil,
        isCopyEnabled: Bool = true,
        wrapPolicy: AgentCodeWrapPolicy = .noWrap
    ) {
        self.text = text
        self.language = language
        self.title = title
        self.showsLineNumbers = showsLineNumbers
        self.supportsSelection = supportsSelection
        self.selection = selection
        self.isCopyEnabled = isCopyEnabled
        self.wrapPolicy = wrapPolicy
    }

    /// The equivalent rich-text code block model.
    /// - Complexity: O(1).
    public var richTextModel: CodeBlockModel {
        CodeBlockModel(
            code: text,
            language: language,
            title: title,
            showsLineNumbers: showsLineNumbers,
            wrapPolicy: wrapPolicy.richTextPolicy,
            isCopyEnabled: isCopyEnabled,
            isSelectable: supportsSelection,
            selection: selection.map { TextRange($0.lowerBound, $0.upperBound) }
        )
    }
}

/// The requested layout of a diff.
public enum AgentDiffLayoutPolicy: String, Sendable, Hashable, CaseIterable {
    /// Chooses a layout from the available width.
    case automatic
    /// Displays one unified column.
    case unified
    /// Displays old and new content side by side.
    case sideBySide
}

/// The concrete layout selected for a diff.
public enum AgentResolvedDiffLayout: String, Sendable, Hashable, CaseIterable {
    /// A single unified column.
    case unified
    /// Old and new content in separate columns.
    case sideBySide
}

/// Raw or parsed input for an agent diff.
public enum AgentDiffInput<ParsedDiff: Sendable & Hashable>: Sendable, Hashable {
    /// A unified diff string.
    case unifiedText(String)
    /// A parsed diff value.
    case parsed(ParsedDiff)
}

/// Diff content and its presentation options.
public struct AgentDiffView<ParsedDiff: Sendable & Hashable>: Sendable, Hashable {
    /// The raw or parsed diff input.
    public var input: AgentDiffInput<ParsedDiff>
    /// The requested diff layout.
    public var layoutPolicy: AgentDiffLayoutPolicy
    /// A Boolean value that indicates whether text selection is supported.
    public var supportsSelection: Bool
    /// The code wrapping policy.
    public var wrapPolicy: AgentCodeWrapPolicy

    /// Creates an agent diff view model.
    public init(
        input: AgentDiffInput<ParsedDiff>,
        layoutPolicy: AgentDiffLayoutPolicy = .automatic,
        supportsSelection: Bool = true,
        wrapPolicy: AgentCodeWrapPolicy = .noWrap
    ) {
        self.input = input
        self.layoutPolicy = layoutPolicy
        self.supportsSelection = supportsSelection
        self.wrapPolicy = wrapPolicy
    }

    /// Returns the concrete layout for an available width.
    /// - Complexity: O(1).
    public func resolvedLayout(availableWidth: Int) -> AgentResolvedDiffLayout {
        switch layoutPolicy {
        case .automatic: availableWidth > 120 ? .sideBySide : .unified
        case .unified: .unified
        case .sideBySide: .sideBySide
        }
    }
}

extension AgentDiffView where ParsedDiff == UnifiedDiff {
    /// The equivalent rich-text diff model.
    /// - Complexity: O(1).
    public var richTextModel: DiffViewModel {
        switch input {
        case .unifiedText(let source):
            DiffViewModel(
                unifiedDiff: source,
                layoutPolicy: layoutPolicy.richTextPolicy,
                wrapPolicy: wrapPolicy.richTextPolicy,
                isSelectable: supportsSelection
            )
        case .parsed(let diff):
            DiffViewModel(
                diff: diff,
                layoutPolicy: layoutPolicy.richTextPolicy,
                wrapPolicy: wrapPolicy.richTextPolicy,
                isSelectable: supportsSelection
            )
        }
    }
}

/// Actions emitted by a code block.
public struct CodeBlockActions: Sendable {
    /// Copies source code.
    public var copy: @MainActor @Sendable (_ text: String) -> Void

    /// Creates code block actions.
    public init(copy: @escaping @MainActor @Sendable (_ text: String) -> Void) {
        self.copy = copy
    }
}

/// A renderable agent code block.
public struct AgentCodeBlockView: AgentComponentRenderable, SemanticRenderable, View, Sendable {
    /// The code block model.
    public var codeBlock: AgentCodeBlock
    /// The optional code block actions.
    public var actions: CodeBlockActions?
    /// The semantic theme.
    public var theme: SemanticTheme
    /// The color scheme.
    public var scheme: ColorScheme
    private let highlighter: any SyntaxHighlighter

    /// Creates an agent code block view.
    nonisolated public init(
        _ codeBlock: AgentCodeBlock,
        actions: CodeBlockActions? = nil,
        highlighter: any SyntaxHighlighter = SubtleSyntaxHighlighter(),
        theme: SemanticTheme = .standard,
        scheme: ColorScheme = .dark
    ) {
        self.codeBlock = codeBlock
        self.actions = actions
        self.highlighter = highlighter
        self.theme = theme
        self.scheme = scheme
    }

    /// Copies the block text when copying is available.
    /// - Complexity: O(1), excluding action work.
    @MainActor
    public func copy() {
        guard let text = codeBlock.richTextModel.copyText else { return }
        actions?.copy(text)
    }

    /// Renders the code block for a context.
    /// - Complexity: O(n), where n is the source length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        do {
            let result = try CodeBlock(model: codeBlock.richTextModel).render(
                width: context.width,
                highlighter: highlighter
            )
            var semantics = result.semantics
            if actions != nil, codeBlock.isCopyEnabled { semantics.actions.insert(.activate) }
            return result.agentOutput(context: context, semantics: semantics)
        } catch {
            preconditionFailure("Code block rendering failed: \(error)")
        }
    }

    /// Returns the code block size for a proposal.
    /// - Complexity: O(n), where n is the source length.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = max(1, proposal.width ?? 80)
        let size = CodeBlockLayout().layout(codeBlock.richTextModel, width: width, highlighter: highlighter).size
        return CellSize(
            width: min(size.width, proposal.width ?? size.width),
            height: min(size.height, proposal.height ?? size.height)
        )
    }

    /// Paints the code block and returns its semantic node.
    /// - Complexity: O(w * h), where w and h are the painted dimensions.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        try paintAgentComponent(
            renderable: self,
            theme: theme,
            scheme: scheme,
            into: &surface,
            context: context,
            resources: &resources
        )
    }

    /// The primitive view graph for the code block.
    /// - Complexity: O(1).
    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }
}

extension AgentCodeBlockView: ControlActivatable {
    /// Copies the code when activation is available.
    /// - Complexity: O(1), excluding action work.
    @MainActor
    @discardableResult
    public func activate() -> Bool {
        guard actions != nil, codeBlock.richTextModel.copyText != nil else { return false }
        copy()
        return true
    }
}

/// A renderable unified diff.
public struct AgentDiffContentView: AgentComponentRenderable, SemanticRenderable, View, Sendable {
    /// The diff view model.
    public var diffView: AgentDiffView<UnifiedDiff>
    /// The semantic theme.
    public var theme: SemanticTheme
    /// The color scheme.
    public var scheme: ColorScheme

    /// Creates an agent diff content view.
    nonisolated public init(
        _ diffView: AgentDiffView<UnifiedDiff>,
        theme: SemanticTheme = .standard,
        scheme: ColorScheme = .dark
    ) {
        self.diffView = diffView
        self.theme = theme
        self.scheme = scheme
    }

    /// Creates an agent diff content view from unified diff text.
    nonisolated public init(
        unifiedDiff: String,
        layoutPolicy: AgentDiffLayoutPolicy = .automatic,
        supportsSelection: Bool = true,
        wrapPolicy: AgentCodeWrapPolicy = .noWrap,
        theme: SemanticTheme = .standard,
        scheme: ColorScheme = .dark
    ) {
        self.init(
            AgentDiffView(
                input: .unifiedText(unifiedDiff),
                layoutPolicy: layoutPolicy,
                supportsSelection: supportsSelection,
                wrapPolicy: wrapPolicy
            ),
            theme: theme,
            scheme: scheme
        )
    }

    /// Creates an agent diff content view from a parsed diff.
    nonisolated public init(
        diff: UnifiedDiff,
        layoutPolicy: AgentDiffLayoutPolicy = .automatic,
        supportsSelection: Bool = true,
        wrapPolicy: AgentCodeWrapPolicy = .noWrap,
        theme: SemanticTheme = .standard,
        scheme: ColorScheme = .dark
    ) {
        self.init(
            AgentDiffView(
                input: .parsed(diff),
                layoutPolicy: layoutPolicy,
                supportsSelection: supportsSelection,
                wrapPolicy: wrapPolicy
            ),
            theme: theme,
            scheme: scheme
        )
    }

    /// Renders the diff for a context.
    /// - Complexity: O(n), where n is the diff size.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        do {
            let result = try DiffView(model: diffView.richTextModel).render(width: context.width)
            return result.agentOutput(context: context)
        } catch {
            preconditionFailure("Diff rendering failed: \(error)")
        }
    }

    /// Returns the diff size for a proposal.
    /// - Complexity: O(n), where n is the diff size.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = max(1, proposal.width ?? 80)
        let size = DiffView(model: diffView.richTextModel).layout(width: width).size
        return CellSize(
            width: min(size.width, proposal.width ?? size.width),
            height: min(size.height, proposal.height ?? size.height)
        )
    }

    /// Paints the diff and returns its semantic node.
    /// - Complexity: O(w * h), where w and h are the painted dimensions.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        try paintAgentComponent(
            renderable: self,
            theme: theme,
            scheme: scheme,
            into: &surface,
            context: context,
            resources: &resources
        )
    }

    /// The primitive view graph for the diff.
    /// - Complexity: O(1).
    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }
}

extension AgentCodeWrapPolicy {
    fileprivate var richTextPolicy: TextWrapPolicy {
        switch self {
        case .noWrap: .none
        case .wrap: .character
        }
    }
}

extension AgentDiffLayoutPolicy {
    fileprivate var richTextPolicy: DiffLayoutPolicy {
        switch self {
        case .automatic: .automatic
        case .unified: .unified
        case .sideBySide: .sideBySide
        }
    }
}

extension RichTextRenderResult {
    fileprivate func agentOutput(context: AgentRenderContext, semantics: SemanticNode? = nil) -> AgentRenderOutput {
        let rows = cells.rows.map { row in
            row.map { cell -> SemanticCell? in
                var attributes = cell.style.attributes.richTextAttributes
                if cell.isSelected { attributes.insert(.selected) }
                return SemanticCell(
                    grapheme: cell.grapheme,
                    displayWidth: Int(cell.packedCell.displayWidth),
                    role: cell.role,
                    attributes: attributes,
                    link: cell.link,
                    isContinuation: cell.isContinuation,
                    backgroundRole: nil
                )
            }
        }
        return AgentRenderOutput(
            cells: SemanticCellGrid(width: cells.width, rows: rows),
            semantics: semantics ?? self.semantics,
            theme: context.theme
        )
    }
}

extension TextAttributes {
    fileprivate var richTextAttributes: StyledTextAttributes {
        var result: StyledTextAttributes = []
        if contains(.bold) { result.insert(.bold) }
        if contains(.italic) { result.insert(.italic) }
        if contains(.underline) { result.insert(.underline) }
        if contains(.strikethrough) { result.insert(.strikethrough) }
        if contains(.dim) { result.insert(.dim) }
        return result
    }
}

@MainActor
private func paintAgentComponent(
    renderable: any AgentComponentRenderable,
    theme: SemanticTheme,
    scheme: ColorScheme,
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
) throws -> SemanticNode {
    guard context.clip.width > 0, context.clip.height > 0 else {
        return SemanticNode(id: "agent-rich-content", role: .text)
    }
    let output = renderable.render(
        in: AgentRenderContext(width: context.clip.width, theme: try theme.resolve(scheme: scheme))
    )
    try SemanticCellPainter.paint(
        output.cells,
        into: &surface,
        context: context,
        theme: output.theme,
        resources: &resources
    )
    return output.semantics.offsetBy(dx: context.origin.x, dy: context.origin.y)
}

extension SemanticNode {
    fileprivate func offsetBy(dx: Int, dy: Int) -> SemanticNode {
        var copy = self
        copy.frame = frame?.offsetBy(dx: dx, dy: dy)
        copy.children = children.map { $0.offsetBy(dx: dx, dy: dy) }
        return copy
    }
}
