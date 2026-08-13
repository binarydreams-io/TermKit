import TUIControls
import TUIDesign
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIRichText
import TUIViewGraph

public enum AgentCodeWrapPolicy: String, Sendable, Hashable, CaseIterable {
    case noWrap
    case wrap
}

public struct AgentCodeBlock: Sendable, Hashable {
    public var text: String
    public var language: String?
    public var title: String?
    public var showsLineNumbers: Bool
    public var supportsSelection: Bool
    public var selection: Range<Int>?
    public var isCopyEnabled: Bool
    public var wrapPolicy: AgentCodeWrapPolicy

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

public enum AgentDiffLayoutPolicy: String, Sendable, Hashable, CaseIterable {
    case automatic
    case unified
    case sideBySide
}

public enum AgentResolvedDiffLayout: String, Sendable, Hashable, CaseIterable {
    case unified
    case sideBySide
}

public enum AgentDiffInput<ParsedDiff: Sendable & Hashable>: Sendable, Hashable {
    case unifiedText(String)
    case parsed(ParsedDiff)
}

public struct AgentDiffView<ParsedDiff: Sendable & Hashable>: Sendable, Hashable {
    public var input: AgentDiffInput<ParsedDiff>
    public var layoutPolicy: AgentDiffLayoutPolicy
    public var supportsSelection: Bool
    public var wrapPolicy: AgentCodeWrapPolicy

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

    public func resolvedLayout(availableWidth: Int) -> AgentResolvedDiffLayout {
        switch layoutPolicy {
        case .automatic: availableWidth > 120 ? .sideBySide : .unified
        case .unified: .unified
        case .sideBySide: .sideBySide
        }
    }
}

extension AgentDiffView where ParsedDiff == UnifiedDiff {
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

public struct CodeBlockActions: Sendable {
    public var copy: @MainActor @Sendable (String) -> Void

    public init(copy: @escaping @MainActor @Sendable (String) -> Void) {
        self.copy = copy
    }
}

public struct AgentCodeBlockView: AgentComponentRenderable, SemanticRenderable, TUIViewGraph.View, Sendable {
    public var codeBlock: AgentCodeBlock
    public var actions: CodeBlockActions?
    public var theme: SemanticTheme
    public var scheme: ColorScheme
    private let highlighter: any SyntaxHighlighter

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

    @MainActor
    public func copy() {
        guard let text = codeBlock.richTextModel.copyText else { return }
        actions?.copy(text)
    }

    nonisolated public func render(in context: AgentRenderContext) -> AgentRenderOutput {
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

    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = max(1, proposal.width ?? 80)
        let size = CodeBlockLayout().layout(codeBlock.richTextModel, width: width, highlighter: highlighter).size
        return CellSize(
            width: min(size.width, proposal.width ?? size.width),
            height: min(size.height, proposal.height ?? size.height)
        )
    }

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
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

    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }
}

extension AgentCodeBlockView: ControlActivatable {
    @MainActor
    @discardableResult
    public func activate() -> Bool {
        guard actions != nil, codeBlock.richTextModel.copyText != nil else { return false }
        copy()
        return true
    }
}

public struct AgentDiffContentView: AgentComponentRenderable, SemanticRenderable, TUIViewGraph.View, Sendable {
    public var diffView: AgentDiffView<UnifiedDiff>
    public var theme: SemanticTheme
    public var scheme: ColorScheme

    nonisolated public init(
        _ diffView: AgentDiffView<UnifiedDiff>,
        theme: SemanticTheme = .standard,
        scheme: ColorScheme = .dark
    ) {
        self.diffView = diffView
        self.theme = theme
        self.scheme = scheme
    }

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

    nonisolated public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        do {
            let result = try DiffView(model: diffView.richTextModel).render(width: context.width)
            return result.agentOutput(context: context)
        } catch {
            preconditionFailure("Diff rendering failed: \(error)")
        }
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = max(1, proposal.width ?? 80)
        let size = DiffView(model: diffView.richTextModel).layout(width: width).size
        return CellSize(
            width: min(size.width, proposal.width ?? size.width),
            height: min(size.height, proposal.height ?? size.height)
        )
    }

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
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

    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }
}

private extension AgentCodeWrapPolicy {
    var richTextPolicy: TextWrapPolicy {
        switch self {
        case .noWrap: .none
        case .wrap: .character
        }
    }
}

private extension AgentDiffLayoutPolicy {
    var richTextPolicy: DiffLayoutPolicy {
        switch self {
        case .automatic: .automatic
        case .unified: .unified
        case .sideBySide: .sideBySide
        }
    }
}

private extension RichTextRenderResult {
    func agentOutput(context: AgentRenderContext, semantics: SemanticNode? = nil) -> AgentRenderOutput {
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

private extension TextAttributes {
    var richTextAttributes: StyledTextAttributes {
        var result: StyledTextAttributes = []
        if contains(.bold) { result.insert(.bold) }
        if contains(.italic) { result.insert(.italic) }
        if contains(.underline) { result.insert(.underline) }
        if contains(.strikethrough) { result.insert(.strikethrough) }
        if contains(.dim) { result.insert(.dim) }
        return result
    }
}

private func paintAgentComponent(
    renderable: any AgentComponentRenderable,
    theme: SemanticTheme,
    scheme: ColorScheme,
    into surface: inout TUIRenderer.Surface,
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

private extension SemanticNode {
    func offsetBy(dx: Int, dy: Int) -> SemanticNode {
        var copy = self
        copy.frame = frame?.offsetBy(dx: dx, dy: dy)
        copy.children = children.map { $0.offsetBy(dx: dx, dy: dy) }
        return copy
    }
}
