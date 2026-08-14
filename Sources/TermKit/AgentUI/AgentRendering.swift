import Foundation

/// The immutable environment for one agent component render pass.
public struct AgentRenderContext: Sendable, Hashable {
    /// The available render width in cells.
    public var width: Int
    /// The resolved semantic theme.
    public var theme: ResolvedSemanticTheme
    /// The elapsed animation time.
    public var elapsed: TimeSpan
    /// A Boolean value that indicates whether motion is reduced.
    public var isReducedMotionEnabled: Bool

    /// Creates a render context with a resolved theme.
    public init(
        width: Int,
        theme: ResolvedSemanticTheme,
        elapsed: TimeSpan = .zero,
        reduceMotion: Bool = false
    ) {
        precondition(width > 0, "A render width must be positive.")
        self.width = width
        self.theme = theme
        self.elapsed = elapsed
        isReducedMotionEnabled = reduceMotion
    }

    /// Creates a render context by resolving a semantic theme.
    public init(
        width: Int,
        scheme: ColorScheme,
        theme: SemanticTheme = .standard,
        elapsed: TimeSpan = .zero,
        reduceMotion: Bool = false
    ) throws {
        self.init(
            width: width,
            theme: try theme.resolve(scheme: scheme),
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
    }
}

/// A cell grid and accessibility tree produced by an agent component.
public struct AgentRenderOutput: Sendable, Hashable {
    /// The rendered semantic cells.
    public var cells: SemanticCellGrid
    /// The accessibility and interaction tree.
    public var semantics: SemanticNode
    /// The resolved theme used for the cells.
    public var theme: ResolvedSemanticTheme

    /// Creates agent render output.
    public init(cells: SemanticCellGrid, semantics: SemanticNode, theme: ResolvedSemanticTheme) {
        self.cells = cells
        self.semantics = semantics
        self.theme = theme
    }

    /// The rendered text without trailing row whitespace.
    /// - Complexity: O(w * h), where w and h are the grid dimensions.
    public var plainText: String {
        cells.rows.map { row in
            row.compactMap { cell in
                guard let cell, cell.isContinuation == false else { return nil }
                return cell.grapheme
            }.joined().replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    /// Returns a stable, sparse representation for semantic snapshot tests.
    /// - Complexity: O(c + n), where c is the cell count and n is the semantic node count.
    public var semanticSnapshot: String {
        var lines = [
            "agent-render-snapshot-v1",
            "grid width=\(cells.width) height=\(cells.height)",
            "theme scheme=\(theme.scheme.snapshotName)",
        ]
        for role in SemanticColorRole.allCases {
            let color = theme[role]
            lines.append("color role=\(role.rawValue) rgba=\(color.snapshotRGBA)")
        }
        for (y, row) in cells.rows.enumerated() {
            for (x, cell) in row.enumerated() {
                guard let cell else { continue }
                lines.append(
                    "cell x=\(x) y=\(y) grapheme=\(cell.grapheme.snapshotQuoted) "
                        + "width=\(cell.displayWidth) role=\(cell.role.snapshotName) "
                        + "attributes=\(cell.attributes.rawValue) link=\(cell.link?.snapshotQuoted ?? "null") "
                        + "continuation=\(cell.isContinuation ? 1 : 0) "
                        + "background=\(cell.backgroundRole?.rawValue ?? "default")"
                )
            }
        }
        append(semantics, path: "0", to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private func append(_ node: SemanticNode, path: String, to lines: inout [String]) {
        let actions = node.actions.map(\.rawValue).sorted().joined(separator: ",")
        let frame = node.frame.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? "null"
        lines.append(
            "node path=\(path) id=\(node.id.rawValue.snapshotQuoted) role=\(node.role.rawValue) "
                + "label=\(node.label.snapshotQuoted) value=\(node.value?.snapshotQuoted ?? "null") "
                + "state=\(node.state.rawValue) actions=[\(actions)] frame=\(frame)"
        )
        for (index, child) in node.children.enumerated() {
            append(child, path: "\(path).\(index)", to: &lines)
        }
    }
}

extension ColorScheme {
    fileprivate var snapshotName: String { self == .light ? "light" : "dark" }
}

extension RGBA {
    fileprivate var snapshotRGBA: String {
        [red, green, blue, alpha]
            .map { String(format: "%02X", Int(($0 * 255).rounded())) }
            .joined()
    }
}

extension SemanticTextRole {
    fileprivate var snapshotName: String {
        switch self {
        case .body: "body"
        case .heading(let level): "heading(\(level))"
        case .link: "link"
        case .inlineCode: "inlineCode"
        case .code: "code"
        case .keyword: "keyword"
        case .string: "string"
        case .number: "number"
        case .comment: "comment"
        case .type: "type"
        case .listMarker: "listMarker"
        case .quoteMarker: "quoteMarker"
        case .tableHeader: "tableHeader"
        case .diffAdded: "diffAdded"
        case .diffRemoved: "diffRemoved"
        case .diffContext: "diffContext"
        case .diffHunk: "diffHunk"
        case .lineNumber: "lineNumber"
        case .muted: "muted"
        case .diagnostic: "diagnostic"
        }
    }
}

extension String {
    fileprivate var snapshotQuoted: String {
        var result = "\""
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x00...0x1F, 0x7F: result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

/// A component that performs width-sensitive layout and semantic rendering.
public protocol AgentComponentRenderable: Sendable {
    /// Renders the component for a width, theme, and animation state.
    /// - Complexity: Depends on the component implementation.
    @MainActor
    func render(in context: AgentRenderContext) -> AgentRenderOutput
}

private protocol AgentTimelineComponent {
    var requestedTimelineCadence: TimeSpan? { get }
}

/// A view adapter for an agent component.
public struct AgentComponentView<Component: AgentComponentRenderable>: SemanticRenderable, View, Sendable {
    /// The component to render.
    public var component: Component
    /// The resolved semantic theme.
    public var theme: ResolvedSemanticTheme
    /// The elapsed animation time.
    public var elapsed: TimeSpan
    /// A Boolean value that indicates whether motion is reduced.
    public var isReducedMotionEnabled: Bool
    private var input: AgentComponentInput?
    private var preservesExecutableActions: Bool
    private var timelineCadence: TimeSpan?

    private struct AgentComponentInput: Sendable {
        var isFocusable: Bool
        var trapsFocus: Bool
        var activate: @MainActor @Sendable () -> Bool
        var activateAt: @MainActor @Sendable (CellPoint) -> Bool
        var handle: @MainActor @Sendable (ControlInputEvent) -> Bool
        var semanticAction: @MainActor @Sendable (SemanticAction) -> Bool
        var focusChanged: @MainActor @Sendable (Bool) -> Void
    }

    /// Creates a component view with a resolved theme.
    nonisolated public init(
        _ component: Component,
        theme: ResolvedSemanticTheme,
        elapsed: TimeSpan = .zero,
        reduceMotion: Bool = false
    ) {
        self.component = component
        self.theme = theme
        self.elapsed = elapsed
        isReducedMotionEnabled = reduceMotion
        input = nil
        preservesExecutableActions = false
        timelineCadence = nil
    }

    /// Creates a component view by resolving a semantic theme.
    nonisolated public init(
        _ component: Component,
        scheme: ColorScheme,
        theme: SemanticTheme = .standard,
        elapsed: TimeSpan = .zero,
        reduceMotion: Bool = false
    ) throws {
        self.init(
            component,
            theme: try theme.resolve(scheme: scheme),
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
    }

    /// Returns the component size for a proposal.
    /// - Complexity: Depends on the component renderer.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = max(1, proposal.width ?? 80)
        let output = component.render(
            in: AgentRenderContext(width: width, theme: theme, elapsed: elapsed, reduceMotion: isReducedMotionEnabled)
        )
        return CellSize(
            width: min(output.cells.width, proposal.width ?? output.cells.width),
            height: min(output.cells.height, proposal.height ?? output.cells.height)
        )
    }

    /// Paints the component and returns its semantic tree.
    /// - Complexity: O(w * h), plus component rendering.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        guard context.clip.width > 0, context.clip.height > 0 else {
            let output = component.render(
                in: AgentRenderContext(width: 1, theme: theme, elapsed: elapsed, reduceMotion: isReducedMotionEnabled)
            )
            return executableSemantics(output.semantics).offsetBy(dx: context.origin.x, dy: context.origin.y)
        }
        let output = component.render(
            in: AgentRenderContext(
                width: context.clip.width,
                theme: theme,
                elapsed: elapsed,
                reduceMotion: isReducedMotionEnabled
            )
        )
        try SemanticCellPainter.paint(
            output.cells,
            into: &surface,
            context: context,
            theme: output.theme,
            resources: &resources
        )
        return executableSemantics(output.semantics).offsetBy(dx: context.origin.x, dy: context.origin.y)
    }

    /// The view graph for the component and its optional timeline.
    /// - Complexity: O(1), excluding component rendering.
    @MainActor
    public var graphBody: [NodeDescriptor] {
        let requestedCadence =
            timelineCadence
            ?? (component as? any AgentTimelineComponent)?.requestedTimelineCadence
        if let requestedCadence {
            return TimelineView<AgentComponentPrimitiveView<Component>>(
                .animation(minimumInterval: requestedCadence)
            ) { timeline in
                var view = self
                view.elapsed = .nanoseconds(timeline.instant.nanoseconds)
                view.isReducedMotionEnabled =
                    timeline.isReducedMotionEnabled || timeline.areAnimationsEnabled == false
                view.timelineCadence = nil
                return AgentComponentPrimitiveView(view: view)
            }.graphBody
        }
        return primitiveDescriptor
    }

    @MainActor
    fileprivate var primitiveDescriptor: [NodeDescriptor] {
        [
            NodeDescriptor(
                type: Self.self,
                primitive: self,
                focus: FocusMetadata(isFocusable: input?.isFocusable == true),
                hitTest: HitTestMetadata(isEnabled: input != nil),
                dirtyOnUpdate: .layout
            )
        ]
    }

    @MainActor
    init(executable component: Component, theme: ResolvedSemanticTheme) {
        self.init(component, theme: theme)
        preservesExecutableActions = true
    }

    @MainActor
    private init(
        _ component: Component,
        theme: ResolvedSemanticTheme,
        isFocusable: Bool = true,
        trapsFocus: Bool = false,
        activate: @escaping @MainActor @Sendable () -> Bool = { false },
        activateAt: @escaping @MainActor @Sendable (CellPoint) -> Bool = { _ in false },
        handle: @escaping @MainActor @Sendable (ControlInputEvent) -> Bool = { _ in false },
        semanticAction: @escaping @MainActor @Sendable (SemanticAction) -> Bool = { _ in false },
        focusChanged: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.init(component, theme: theme)
        input = AgentComponentInput(
            isFocusable: isFocusable,
            trapsFocus: trapsFocus,
            activate: activate,
            activateAt: activateAt,
            handle: handle,
            semanticAction: semanticAction,
            focusChanged: focusChanged
        )
        preservesExecutableActions = true
    }

    nonisolated private func executableSemantics(_ semantics: SemanticNode) -> SemanticNode {
        guard preservesExecutableActions == false else { return semantics }
        var semantics = semantics
        semantics.actions = []
        semantics.children = semantics.children.map { child in
            var child = child
            child.actions = []
            return child
        }
        return semantics
    }
}

private struct AgentComponentPrimitiveView<Component: AgentComponentRenderable>: View {
    var view: AgentComponentView<Component>

    var graphBody: [NodeDescriptor] { view.primitiveDescriptor }
}

extension AgentComponentView: ControlActivatable, ControlPointerActivatable, ControlInputHandler, ControlFocusHandler,
    ControlFocusTrapping, ControlSemanticActionHandler
{
    /// A Boolean value that indicates whether the component traps control focus.
    public var trapsControlFocus: Bool { input?.trapsFocus == true }
    /// Activates the component.
    /// - Complexity: O(1), excluding action work.
    @MainActor public func activate() -> Bool { input?.activate() ?? false }
    /// Activates the component at a cell point.
    /// - Complexity: O(1), excluding action work.
    @MainActor public func activate(at point: CellPoint) -> Bool { input?.activateAt(point) ?? false }
    /// Handles a control input event.
    /// - Complexity: O(1), excluding handler work.
    @MainActor public func handleControlInput(_ event: ControlInputEvent) -> Bool { input?.handle(event) ?? false }
    /// Reports a control focus change.
    /// - Complexity: O(1), excluding handler work.
    @MainActor public func controlFocusChanged(_ isFocused: Bool) { input?.focusChanged(isFocused) }
    /// Handles a semantic action.
    /// - Complexity: O(1), excluding handler work.
    @MainActor public func handleSemanticAction(_ action: SemanticAction) -> Bool {
        if input?.semanticAction(action) == true { return true }
        return action == .activate ? activate() : false
    }
}

/// Interactive adapters for built-in agent components.
extension AgentComponentView {
    /// Creates an interactive attachment chip view.
    @MainActor
    public init<ID>(
        _ component: AttachmentChip<ID>,
        actions: AttachmentChipActions<ID>,
        theme: ResolvedSemanticTheme
    ) where Component == AttachmentChip<ID> {
        self.init(
            component,
            theme: theme,
            activate: {
                actions.remove(component.id)
                return true
            },
            activateAt: { _ in
                actions.remove(component.id)
                return true
            },
            focusChanged: { if $0 { actions.focus(component.id) } }
        )
    }

    /// Creates an interactive reasoning disclosure view.
    @MainActor
    public init<Body>(
        _ component: ReasoningDisclosure<Body>,
        actions: ReasoningDisclosureActions,
        theme: ResolvedSemanticTheme
    ) where Component == ReasoningDisclosure<Body> {
        let isExpandable = component.phase == .completed
        self.init(
            component,
            theme: theme,
            isFocusable: isExpandable,
            activate: {
                guard isExpandable else { return false }
                actions.toggle()
                return true
            }
        )
        timelineCadence = component.phase == .running ? .milliseconds(120) : nil
    }

    /// Creates an interactive conversation viewport view.
    @MainActor
    public init<Item>(
        items: [Item],
        state: Binding<ConversationViewportState>,
        theme: ResolvedSemanticTheme,
        actions: ConversationViewportActions = ConversationViewportActions()
    ) where Component == ConversationViewport<Item>, Item: AgentContentPresentable {
        let component = ConversationViewport(items: items, state: state.wrappedValue)
        self.init(
            component,
            theme: theme,
            handle: { event in
                switch event {
                case .moveDown: return Self.scrollViewport(state, forward: true, actions: actions)
                case .moveUp: return Self.scrollViewport(state, forward: false, actions: actions)
                default: return false
                }
            },
            semanticAction: { action in
                switch action {
                case .scrollForward: return Self.scrollViewport(state, forward: true, actions: actions)
                case .scrollBackward: return Self.scrollViewport(state, forward: false, actions: actions)
                default: return false
                }
            }
        )
    }

    @MainActor
    private static func scrollViewport(
        _ state: Binding<ConversationViewportState>,
        forward: Bool,
        actions: ConversationViewportActions
    ) -> Bool {
        var value = state.wrappedValue
        let delta = value.scrollState.viewportExtent * (forward ? 1 : -1)
        value.scroll(to: value.scrollState.offset + delta)
        state.wrappedValue = value
        if forward { actions.scrollForward() } else { actions.scrollBackward() }
        return true
    }

    /// Creates an interactive tool call row view.
    @MainActor
    public init<ID>(
        _ component: ToolCallRow<ID>,
        actions: ToolCallRowActions<ID>,
        theme: ResolvedSemanticTheme
    ) where Component == ToolCallRow<ID> {
        let canRevealFailure = component.state == .failed && component.errorBody != nil
        self.init(
            component,
            theme: theme,
            isFocusable: canRevealFailure,
            activate: {
                guard canRevealFailure else { return false }
                actions.toggleFailure(component.id)
                return true
            }
        )
    }

    /// Creates an interactive shell result view.
    @MainActor
    public init(
        _ component: ShellResult,
        actions: ShellResultActions,
        theme: ResolvedSemanticTheme,
        viewportWidth: Int = 80
    ) where Component == ShellResult {
        let isExpandable = component.visibleLineLimit(viewportWidth: viewportWidth) != nil || component.isExpanded
        self.init(
            component,
            theme: theme,
            isFocusable: isExpandable,
            activate: {
                guard isExpandable else { return false }
                actions.toggleExpansion()
                return true
            }
        )
    }

    /// Creates an interactive diagnostics list view.
    @MainActor
    public init<ID>(
        _ component: DiagnosticsList<ID>,
        state: Binding<DiagnosticsListState>,
        actions: DiagnosticsListActions<ID>,
        theme: ResolvedSemanticTheme
    ) where Component == DiagnosticsList<ID> {
        let move: @MainActor @Sendable (Int) -> Bool = { offset in
            guard component.diagnostics.isEmpty == false else { return false }
            var value = state.wrappedValue
            value.focusedIndex = min(max(0, value.focusedIndex + offset), component.diagnostics.count - 1)
            state.wrappedValue = value
            return true
        }
        let navigate: @MainActor @Sendable () -> Bool = {
            guard component.diagnostics.indices.contains(state.wrappedValue.focusedIndex) else { return false }
            actions.navigate(component.diagnostics[state.wrappedValue.focusedIndex].id)
            return true
        }
        self.init(
            component,
            theme: theme,
            isFocusable: component.mode == .block && component.diagnostics.isEmpty == false,
            activate: navigate,
            activateAt: { point in
                guard component.diagnostics.indices.contains(point.y) else { return false }
                var value = state.wrappedValue
                value.focusedIndex = point.y
                state.wrappedValue = value
                actions.navigate(component.diagnostics[point.y].id)
                return true
            },
            handle: { event in
                switch event {
                case .moveUp: move(-1)
                case .moveDown: move(1)
                case .submit: navigate()
                default: false
                }
            }
        )
    }

    /// Creates an interactive permission prompt view.
    @MainActor
    public init(
        _ prompt: Binding<PermissionPrompt>,
        actions: PermissionPromptActions,
        theme: ResolvedSemanticTheme
    ) where Component == PermissionPrompt {
        let choose: @MainActor @Sendable () -> Bool = {
            actions.choose(prompt.wrappedValue.focusedChoice)
            return true
        }
        self.init(
            prompt.wrappedValue,
            theme: theme,
            trapsFocus: true,
            activate: choose,
            activateAt: { point in
                var value = prompt.wrappedValue
                let index = point.y - 2 - value.resources.count
                guard value.choices.indices.contains(index) else { return false }
                value.moveFocus(by: index - value.focusedChoiceIndex)
                prompt.wrappedValue = value
                actions.choose(value.focusedChoice)
                return true
            },
            handle: { event in
                var value = prompt.wrappedValue
                switch event {
                case .moveUp:
                    value.moveFocus(by: -1)
                    prompt.wrappedValue = value
                    return true
                case .moveDown:
                    value.moveFocus(by: 1)
                    prompt.wrappedValue = value
                    return true
                case .submit:
                    return choose()
                default:
                    return true
                }
            }
        )
    }

    /// Creates an interactive question prompt view.
    @MainActor
    public init(
        _ prompt: Binding<QuestionPrompt>,
        state: Binding<QuestionPromptState>,
        actions: QuestionPromptActions,
        theme: ResolvedSemanticTheme
    ) where Component == QuestionPrompt {
        let initialPrompt = prompt.wrappedValue
        let initialState = state.wrappedValue
        let displayedPrompt: QuestionPrompt
        if initialPrompt.questions.indices.contains(initialState.stepIndex) {
            let question = initialPrompt.questions[initialState.stepIndex]
            displayedPrompt = QuestionPrompt(
                questions: [question],
                answers: initialPrompt.answers[question.id].map { [question.id: $0] } ?? [:]
            )
        } else {
            displayedPrompt = initialPrompt
        }
        let select: @MainActor @Sendable () -> Bool = {
            var value = prompt.wrappedValue
            let viewState = state.wrappedValue
            guard value.questions.indices.contains(viewState.stepIndex) else { return false }
            let question = value.questions[viewState.stepIndex]
            guard question.kind != .customText,
                let optionIndex = viewState.focusedOptionIndex,
                question.options.indices.contains(optionIndex)
            else { return false }
            let optionID = question.options[optionIndex].id
            var selected: Set<String> = []
            if case .optionIDs(let ids) = value.answers[question.id] { selected = ids }
            if question.kind == .singleSelection {
                selected = [optionID]
            } else if selected.contains(optionID) {
                selected.remove(optionID)
            } else {
                selected.insert(optionID)
            }
            value.setAnswer(.optionIDs(selected), forQuestionID: question.id)
            prompt.wrappedValue = value
            state.wrappedValue = viewState
            return true
        }
        let advance: @MainActor @Sendable () -> Bool = {
            let value = prompt.wrappedValue
            var viewState = state.wrappedValue
            if viewState.moveToNextStep(in: value) {
                if value.questions[viewState.stepIndex].kind != .customText { viewState.focusedOptionIndex = 0 }
                state.wrappedValue = viewState
                return true
            }
            guard viewState.stepIndex == value.questions.count - 1,
                value.isQuestionValid(at: viewState.stepIndex)
            else { return false }
            actions.submit(value.answers)
            return true
        }
        self.init(
            displayedPrompt,
            theme: theme,
            activate: select,
            activateAt: { point in
                var value = prompt.wrappedValue
                var viewState = state.wrappedValue
                guard value.questions.indices.contains(viewState.stepIndex) else { return false }
                let question = value.questions[viewState.stepIndex]
                guard question.kind != .customText else { return true }
                let optionIndex = point.y - 1 - (question.detail == nil ? 0 : 1)
                guard question.options.indices.contains(optionIndex) else { return false }
                viewState.focusedOptionIndex = optionIndex
                state.wrappedValue = viewState
                let optionID = question.options[optionIndex].id
                var selected: Set<String> = []
                if case .optionIDs(let ids) = value.answers[question.id] { selected = ids }
                if question.kind == .singleSelection {
                    selected = [optionID]
                } else if selected.contains(optionID) {
                    selected.remove(optionID)
                } else {
                    selected.insert(optionID)
                }
                value.setAnswer(.optionIDs(selected), forQuestionID: question.id)
                prompt.wrappedValue = value
                return true
            },
            handle: { event in
                var value = prompt.wrappedValue
                var viewState = state.wrappedValue
                guard value.questions.indices.contains(viewState.stepIndex) else { return false }
                let question = value.questions[viewState.stepIndex]
                switch event {
                case .moveUp where question.kind != .customText,
                    .moveDown where question.kind != .customText:
                    let offset = event == .moveUp ? -1 : 1
                    let current = viewState.focusedOptionIndex ?? 0
                    viewState.focusedOptionIndex = min(max(0, current + offset), question.options.count - 1)
                    state.wrappedValue = viewState
                    return true
                case .text(let text) where question.kind == .customText,
                    .paste(let text) where question.kind == .customText:
                    let current: String
                    if case .text(let answer) = value.answers[question.id] { current = answer } else { current = "" }
                    value.setAnswer(.text(current + text), forQuestionID: question.id)
                    prompt.wrappedValue = value
                    return true
                case .deleteBackward where question.kind == .customText:
                    guard case .text(var text) = value.answers[question.id], text.isEmpty == false else { return true }
                    text.removeLast()
                    value.setAnswer(.text(text), forQuestionID: question.id)
                    prompt.wrappedValue = value
                    return true
                case .submit where question.kind == .customText:
                    return advance()
                case .submit:
                    return select()
                case .moveRight:
                    return advance()
                case .moveLeft:
                    viewState.moveToPreviousStep()
                    if value.questions[viewState.stepIndex].kind != .customText { viewState.focusedOptionIndex = 0 }
                    state.wrappedValue = viewState
                    return true
                case .cancel:
                    actions.cancel()
                    return true
                default:
                    return false
                }
            }
        )
    }

    /// Creates an interactive session sidebar view.
    @MainActor
    public init<Item>(
        _ component: SessionSidebar<Item>,
        actions: SessionSidebarActions,
        theme: ResolvedSemanticTheme
    ) where Component == SessionSidebar<Item> {
        self.init(
            component,
            theme: theme,
            isFocusable: component.isOverlayPresented,
            activate: { false },
            handle: { event in
                guard component.isOverlayPresented, event == .cancel else { return false }
                actions.dismiss()
                return true
            }
        )
    }
}

extension SemanticNode {
    fileprivate func offsetBy(dx: Int, dy: Int) -> SemanticNode {
        var copy = self
        copy.frame = frame?.offsetBy(dx: dx, dy: dy)
        copy.children = children.map { $0.offsetBy(dx: dx, dy: dy) }
        return copy
    }
}

/// A value that generic agent components can present as rich text.
public protocol AgentContentPresentable: Sendable {
    /// The styled text used to present the value.
    var agentStyledText: StyledText { get }
}

extension String: AgentContentPresentable {
    /// The string represented as styled text.
    public var agentStyledText: StyledText { StyledText(self) }
}

extension StyledText: AgentContentPresentable {
    /// The value itself as agent-styled text.
    public var agentStyledText: StyledText { self }
}

private enum AgentGrid {
    static func output(
        id: SemanticID,
        role: SemanticRole,
        label: String,
        lines: [StyledText],
        context: AgentRenderContext,
        state: SemanticState = [],
        actions: Set<SemanticAction> = [],
        children: [SemanticNode] = [],
        background: SemanticColorRole? = nil
    ) -> AgentRenderOutput {
        let cells = grid(lines: lines, width: context.width, background: background)
        let node = SemanticNode(
            id: id,
            role: role,
            label: label,
            state: state,
            actions: actions,
            frame: CellRect(x: 0, y: 0, width: context.width, height: cells.height),
            children: children
        )
        return AgentRenderOutput(cells: cells, semantics: node, theme: context.theme)
    }

    static func grid(
        lines: [StyledText],
        width: Int,
        background: SemanticColorRole? = nil
    ) -> SemanticCellGrid {
        let renderer = StyledTextCellRenderer()
        let rows = lines.flatMap { renderer.render($0, width: width, wrapPolicy: .word).rows }.map { row in
            row.map { cell in
                cell.map { cell in
                    SemanticCell(
                        grapheme: cell.grapheme,
                        displayWidth: cell.displayWidth,
                        role: cell.role,
                        attributes: cell.attributes,
                        link: cell.link,
                        isContinuation: cell.isContinuation,
                        foregroundRole: cell.foregroundRole,
                        backgroundRole: background
                    )
                }
            }
        }
        return SemanticCellGrid(width: width, rows: rows)
    }

    static func span(
        _ text: String,
        role: SemanticTextRole = .body,
        attributes: StyledTextAttributes = []
    ) -> StyledTextSpan {
        StyledTextSpan(text, role: role, attributes: attributes)
    }

    static func line(_ spans: StyledTextSpan...) -> StyledText {
        StyledText(spans: spans)
    }

    static func clipped(_ text: String, width: Int) -> String {
        TerminalWidth.prefix(of: text, fitting: max(0, width))
    }

    static func duration(_ duration: TimeSpan) -> String {
        if duration.seconds < 1 { return "\(duration.nanoseconds / 1_000_000)ms" }
        return String(format: "%.1fs", duration.seconds)
    }
}

extension AgentPrompt: AgentComponentRenderable {
    /// Renders the prompt for a context.
    /// - Complexity: O(n), where n is the prompt text length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let width = layoutPolicy.resolvedWidth(forTerminalWidth: context.width)
        let innerWidth = max(1, width - layoutPolicy.railWidth - layoutPolicy.horizontalPadding * 2)
        let body = document.text.isEmpty ? configuration.placeholder : document.text
        let bodyRole: SemanticTextRole = document.text.isEmpty ? .muted : .body
        var lines = Array(repeating: StyledText(""), count: layoutPolicy.topPadding)
        let wrapped = StyledText(body, role: bodyRole).wrapped(to: innerWidth, policy: .word)
        for line in wrapped {
            lines.append(
                AgentGrid.line(
                    AgentGrid.span("▌", role: .listMarker),
                    AgentGrid.span(String(repeating: " ", count: layoutPolicy.horizontalPadding)),
                    AgentGrid.span(line.text.plainText, role: bodyRole)
                )
            )
        }
        lines.append(StyledText(String(repeating: "▄", count: width), role: .listMarker))
        if configuration.isBusy { lines.append(StyledText("Working...", role: .muted)) }

        var state: SemanticState = []
        if configuration.isEnabled == false { state.insert(.disabled) }
        if configuration.isBusy { state.insert(.busy) }
        let editorState: SemanticState = configuration.isEnabled ? [] : .disabled
        let actions: Set<SemanticAction> = configuration.isEnabled ? [.focus, .submit] : []
        let localContext = AgentRenderContext(
            width: width,
            theme: context.theme,
            elapsed: context.elapsed,
            reduceMotion: context.isReducedMotionEnabled
        )
        var semanticChildren = [
            SemanticNode(
                id: "agent-prompt-editor",
                role: .textEditor,
                label: configuration.placeholder,
                state: editorState,
                actions: actions,
                frame: CellRect(x: 0, y: 0, width: width, height: max(0, lines.count - (configuration.isBusy ? 1 : 0)))
            )
        ]
        if configuration.isBusy {
            semanticChildren.append(
                SemanticNode(
                    id: "agent-prompt-status",
                    role: .status,
                    label: "Working...",
                    state: .busy,
                    frame: CellRect(x: 0, y: lines.count - 1, width: width, height: 1)
                )
            )
        }
        let output = AgentGrid.output(
            id: "agent-prompt",
            role: .group,
            label: configuration.placeholder,
            lines: lines,
            context: localContext,
            state: state,
            actions: [],
            children: semanticChildren,
            background: .element
        )
        return output
    }
}

extension AgentPromptRenderLeaf: SemanticRenderable {
    func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        componentView.sizeThatFits(proposal)
    }

    func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        try componentView.paint(into: &surface, context: context, resources: &resources)
    }

    @MainActor
    private var componentView: AgentComponentView<AgentPrompt<Attachment>> {
        AgentComponentView(executable: prompt, theme: resolvedTheme)
    }

    nonisolated private var resolvedTheme: ResolvedSemanticTheme {
        do {
            return try SemanticTheme.standard.resolve(scheme: prompt.configuration.colorScheme)
        } catch {
            preconditionFailure("The standard semantic theme must resolve: \(error)")
        }
    }
}

extension AgentPromptRenderLeaf: ControlInputHandler {
    @MainActor
    func handleControlInput(_ event: ControlInputEvent) -> Bool {
        guard prompt.configuration.isEnabled else { return false }
        var prompt = prompt
        switch event {
        case .text(let text), .paste(let text):
            guard text.isEmpty == false else { return false }
            if case .paste = event {
                return prompt.paste(text)
            } else {
                prompt.insert(PromptInsertion(replacementRange: prompt.currentDocument.selection.range, text: text))
            }
        case .submit:
            prompt.submit()
        case .newline:
            prompt.insert(PromptInsertion(replacementRange: prompt.currentDocument.selection.range, text: "\n"))
        case .cancel:
            prompt.actions.cancel()
        case .moveLeft:
            prompt.moveCaret(by: -1)
        case .moveRight:
            prompt.moveCaret(by: 1)
        case .deleteBackward:
            prompt.deleteBackward()
        default:
            return false
        }
        return true
    }
}

extension AgentPromptRenderLeaf: ControlShortcutHandler {
    @MainActor
    func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        guard prompt.configuration.isEnabled, shortcut.modifiers == [.shift] else { return false }
        var prompt = prompt
        switch shortcut.key {
        case .left: prompt.moveCaret(by: -1, extendingSelection: true)
        case .right: prompt.moveCaret(by: 1, extendingSelection: true)
        default: return false
        }
        return true
    }
}

extension AgentPromptMetadataLeaf: SemanticRenderable {
    nonisolated func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        Text(text).sizeThatFits(proposal)
    }

    nonisolated func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        var node = try Text(text, id: "agent-prompt-metadata").paint(
            into: &surface,
            context: context,
            resources: &resources
        )
        node.role = .status
        return node
    }
}

extension PromptAutocomplete: AgentComponentRenderable {
    /// Renders the filtered prompt suggestions.
    /// - Complexity: O(n), where n is the number of filtered suggestions.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let items = selectList.filteredItems
        let selectedID = selectList.selectedID
        let lines = items.map { item in
            AgentGrid.line(
                AgentGrid.span(item.id == selectedID ? "▌ " : "  ", role: .listMarker),
                AgentGrid.span(item.group.map { "\($0) " } ?? "", role: .muted),
                AgentGrid.span(item.title, attributes: item.id == selectedID ? .bold : []),
                AgentGrid.span(item.details.map { "  \($0)" } ?? "", role: .muted)
            )
        }
        var semantics = selectList.semanticNode()
        semantics.label = "Prompt suggestions"
        if isEnabled == false {
            semantics.state.insert(.disabled)
            for index in semantics.children.indices {
                semantics.children[index].state.insert(.disabled)
                semantics.children[index].actions = []
            }
        }
        return AgentGrid.output(
            id: "prompt-autocomplete",
            role: .menu,
            label: "Prompt suggestions",
            lines: lines.isEmpty ? [StyledText("No suggestions", role: .muted)] : lines,
            context: context,
            state: isEnabled ? [] : .disabled,
            children: semantics.children
        )
    }
}

extension AttachmentChip: AgentComponentRenderable {
    /// Renders the attachment chip.
    /// - Complexity: O(n), where n is the attachment name length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let line = AgentGrid.line(
            AgentGrid.span(" \(kind.rawValue) ", role: .inlineCode),
            AgentGrid.span(name + " ", role: .muted),
            AgentGrid.span("×", role: .listMarker)
        )
        return AgentGrid.output(
            id: "attachment-chip",
            role: .button,
            label: "\(kind.rawValue) attachment: \(name)",
            lines: [line],
            context: context,
            state: isFocused ? .focused : [],
            actions: [.focus, .dismiss]
        )
    }
}

extension ToastPresentation: AgentComponentRenderable {
    /// Renders the toast message.
    /// - Complexity: O(n), where n is the message length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let role: SemanticTextRole =
            switch kind {
            case .error: .diagnostic
            case .info, .success, .warning: .body
            }
        let line = AgentGrid.line(
            AgentGrid.span("▌ ", role: kind == .error ? .diagnostic : .listMarker),
            AgentGrid.span(message, role: role)
        )
        return AgentGrid.output(
            id: "toast",
            role: .status,
            label: message,
            lines: [line],
            context: context
        )
    }
}

extension UserMessageCard: AgentComponentRenderable where Attachment: AgentContentPresentable {
    /// Renders the user message and attachments.
    /// - Complexity: O(n), where n is the rendered content length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let innerWidth = max(1, context.width - Self.railWidth - Self.horizontalPadding * 2)
        var lines = [StyledText("")]
        for line in StyledText(text).wrapped(to: innerWidth) {
            lines.append(
                AgentGrid.line(
                    AgentGrid.span("▌", role: .listMarker),
                    AgentGrid.span("  "),
                    AgentGrid.span(line.text.plainText)
                )
            )
        }
        for attachment in attachments {
            lines.append(
                AgentGrid.line(
                    AgentGrid.span("▌  ", role: .listMarker),
                    AgentGrid.span(attachment.agentStyledText.plainText, role: .muted)
                )
            )
        }
        var footer = timestamp ?? ""
        if isQueued { footer += footer.isEmpty ? "Queued" : " · Queued" }
        if footer.isEmpty == false { lines.append(StyledText("   " + footer, role: .muted)) }
        lines.append(StyledText(""))
        var state: SemanticState = []
        if isQueued { state.insert(.busy) }
        if isHovered { state.insert(.hovered) }
        var output = AgentGrid.output(
            id: "user-message",
            role: .group,
            label: text,
            lines: lines,
            context: context,
            state: state,
            background: isHovered ? .element : .panel
        )
        output.cells = SemanticCellGrid(
            width: output.cells.width,
            rows: output.cells.rows.map { row in
                row.map { cell in
                    guard let cell, cell.grapheme == "▌" else { return cell }
                    return SemanticCell(
                        grapheme: cell.grapheme,
                        displayWidth: cell.displayWidth,
                        role: cell.role,
                        attributes: cell.attributes,
                        link: cell.link,
                        isContinuation: cell.isContinuation,
                        foregroundRole: agentColor,
                        backgroundRole: cell.backgroundRole
                    )
                }
            }
        )
        return output
    }
}

extension ReasoningDisclosure: AgentComponentRenderable where Body: AgentContentPresentable {
    /// Renders the reasoning disclosure.
    /// - Complexity: O(n), where n is the visible reasoning length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let marker: String
        if phase == .running {
            marker = context.isReducedMotionEnabled ? "..." : ["·", "●", "•"][Int(max(0, context.elapsed.nanoseconds) / 120_000_000) % 3]
        } else {
            marker = isExpanded ? "▾" : "▸"
        }
        var header = "\(marker) \(label)"
        if phase == .completed, let summary, summary.isEmpty == false { header += " · \(summary)" }
        if phase == .completed, let duration { header += " · \(AgentGrid.duration(duration))" }
        var lines = [StyledText(header, role: .muted)]
        if isExpanded { lines.append(body.agentStyledText) }
        var state: SemanticState = isExpanded ? .expanded : []
        if phase == .running { state.insert(.busy) }
        let actions: Set<SemanticAction> = phase == .completed ? [.activate] : []
        return AgentGrid.output(
            id: "reasoning",
            role: .button,
            label: label,
            lines: lines,
            context: context,
            state: state,
            actions: actions
        )
    }
}

extension ReasoningDisclosure: AgentTimelineComponent {
    fileprivate var requestedTimelineCadence: TimeSpan? {
        phase == .running ? .milliseconds(120) : nil
    }
}

extension ToolCallRow: AgentComponentRenderable {
    /// Renders the tool call row.
    /// - Complexity: O(n), where n is the visible text length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let symbol: String =
            switch state {
            case .pending: "○"
            case .running: context.isReducedMotionEnabled ? "…" : "◉"
            case .completed: "✓"
            case .denied: "⊘"
            case .failed: "!"
            }
        let attributes: StyledTextAttributes = state == .denied ? .strikethrough : []
        var lines = [
            AgentGrid.line(
                AgentGrid.span(symbol.padding(toLength: iconColumnWidth, withPad: " ", startingAt: 0), role: .listMarker),
                AgentGrid.span(label, attributes: attributes)
            )
        ]
        if revealsError, let errorBody { lines.append(StyledText(errorBody, role: .diagnostic)) }
        var semanticState: SemanticState = []
        if state == .running { semanticState.insert(.busy) }
        if revealsError { semanticState.insert(.expanded) }
        let actions: Set<SemanticAction> = state == .failed && errorBody != nil ? [.activate] : []
        return AgentGrid.output(
            id: "tool-call",
            role: .group,
            label: label,
            lines: lines,
            context: context,
            state: semanticState,
            actions: actions
        )
    }
}

extension ToolResultPanel: AgentComponentRenderable where Content: AgentContentPresentable {
    /// Renders the tool result panel.
    /// - Complexity: O(n), where n is the visible content length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        guard isVisibleAsPanel else {
            return AgentGrid.output(
                id: "tool-result",
                role: .group,
                label: title,
                lines: [],
                context: context
            )
        }
        let lines = [
            AgentGrid.line(AgentGrid.span("▌ ", role: .listMarker), AgentGrid.span(title, role: .muted)),
            AgentGrid.line(
                AgentGrid.span("▌ ", role: .listMarker),
                AgentGrid.span(content.agentStyledText.plainText)
            ),
        ]
        return AgentGrid.output(
            id: "tool-result",
            role: .group,
            label: title,
            lines: lines,
            context: context,
            background: .panel
        )
    }
}

extension ShellResult: AgentComponentRenderable {
    /// Renders the shell command and visible output.
    /// - Complexity: O(n), where n is the output length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        var lines = [
            AgentGrid.line(
                AgentGrid.span("$ ", role: .listMarker),
                AgentGrid.span(command, role: .code, attributes: .bold)
            )
        ]
        if let workingDirectory { lines.append(StyledText(workingDirectory, role: .muted)) }
        let outputLines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let limit = visibleLineLimit(viewportWidth: context.width)
        lines.append(contentsOf: outputLines.prefix(limit ?? outputLines.count).map { StyledText($0, role: .code) })
        if let limit { lines.append(StyledText("… \(outputLines.count - limit) more lines", role: .muted)) }
        if isRunning {
            lines.append(StyledText(context.isReducedMotionEnabled ? "Running..." : "● Running", role: .muted))
        }
        if hasFailed { lines.append(StyledText("Exit \(exitCode ?? 1)", role: .diagnostic)) }
        var state: SemanticState = []
        if isRunning { state.insert(.busy) }
        if isExpanded { state.insert(.expanded) }
        return AgentGrid.output(
            id: "shell-result",
            role: .group,
            label: command,
            lines: lines,
            context: context,
            state: state,
            actions: limit == nil ? [] : [.activate]
        )
    }
}

extension DiagnosticsList: AgentComponentRenderable {
    /// Renders the diagnostics list or inline summary.
    /// - Complexity: O(n), where n is the diagnostics count and text length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        if mode == .inline {
            return AgentGrid.output(
                id: "diagnostics",
                role: .status,
                label: inlineSummary ?? "No diagnostics",
                lines: inlineSummary.map { [StyledText($0, role: .diagnostic)] } ?? [],
                context: context
            )
        }
        let lines = diagnostics.map { diagnostic in
            let symbol =
                switch diagnostic.severity {
                case .information: "i"
                case .warning: "!"
                case .error: "×"
                }
            let location = [diagnostic.path, diagnostic.line.map(String.init), diagnostic.column.map(String.init)]
                .compactMap { $0 }.joined(separator: ":")
            return AgentGrid.line(
                AgentGrid.span("\(symbol) ", role: .diagnostic),
                AgentGrid.span(location.isEmpty ? "" : "\(location) ", role: .muted),
                AgentGrid.span(diagnostic.message, role: .diagnostic)
            )
        }
        let children = diagnostics.enumerated().map { index, diagnostic in
            SemanticNode(
                id: SemanticID(rawValue: "diagnostic-\(index)"),
                role: .button,
                label: diagnostic.message,
                actions: [.activate]
            )
        }
        return AgentGrid.output(
            id: "diagnostics",
            role: .list,
            label: "Diagnostics",
            lines: lines,
            context: context,
            actions: diagnostics.isEmpty ? [] : [.focus],
            children: children
        )
    }
}

/// The visible transcript items and their lazy viewport state.
public struct ConversationViewport<Item: Sendable>: Sendable {
    /// The conversation items.
    public var items: [Item]
    /// The lazy viewport state.
    public var state: ConversationViewportState

    /// Creates conversation viewport content.
    public init(items: [Item], state: ConversationViewportState) {
        precondition(items.count == state.itemCount, "The item count must match the viewport state.")
        self.items = items
        self.state = state
    }
}

extension ConversationViewport: AgentComponentRenderable where Item: AgentContentPresentable {
    /// Renders the planned visible conversation items.
    /// - Complexity: O(n), where n is the visible content length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let plannedRange = state.visiblePlan().visibleRange
        let visibleRange = max(items.startIndex, plannedRange.lowerBound)..<min(items.endIndex, plannedRange.upperBound)
        let lines = visibleRange.flatMap { index -> [StyledText] in
            let rows = items[index].agentStyledText.wrapped(to: context.width, policy: .word).map(\.text)
            return index == visibleRange.upperBound - 1 ? rows : rows + [StyledText("")]
        }
        var semanticState: SemanticState = []
        if state.isPinnedToBottom { semanticState.insert(.current) }
        let children = visibleRange.map { index in
            SemanticNode(
                id: SemanticID(rawValue: "conversation-item-\(index)"),
                role: .group,
                label: items[index].agentStyledText.plainText
            )
        }
        return AgentGrid.output(
            id: "conversation",
            role: .scrollView,
            label: "Conversation",
            lines: lines,
            context: context,
            state: semanticState,
            actions: [.scrollForward, .scrollBackward],
            children: children
        )
    }
}

extension AssistantMessage: AgentComponentRenderable
where
    Markdown: AgentContentPresentable, Reasoning: AgentContentPresentable,
    ToolActivity: AgentContentPresentable, Diagnostic: AgentContentPresentable
{
    /// Renders the assistant message sections and footer.
    /// - Complexity: O(n), where n is the visible content length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        var lines: [StyledText] = []
        lines.append(contentsOf: markdown.map(\.agentStyledText))
        lines.append(contentsOf: reasoning.map(\.agentStyledText))
        lines.append(contentsOf: toolActivity.map(\.agentStyledText))
        lines.append(contentsOf: diagnostics.map { $0.agentStyledText.applying(role: .diagnostic) })
        if let footer {
            var fields = [footer.agentMode, footer.model].compactMap { $0 }
            if let duration = footer.duration { fields.append(AgentGrid.duration(duration)) }
            if footer.wasInterrupted { fields.append("Interrupted") }
            if fields.isEmpty == false { lines.append(StyledText(fields.joined(separator: " · "), role: .muted)) }
        }
        let children = [
            ("assistant-markdown", "Response", markdown.count),
            ("assistant-reasoning", "Reasoning", reasoning.count),
            ("assistant-tools", "Tool activity", toolActivity.count),
            ("assistant-diagnostics", "Diagnostics", diagnostics.count),
        ].filter { $0.2 > 0 }.map { id, label, count in
            SemanticNode(id: SemanticID(rawValue: id), role: .group, label: label, value: String(count))
        }
        return AgentGrid.output(
            id: "assistant-message",
            role: .group,
            label: "Assistant response",
            lines: lines,
            context: context,
            children: children
        )
    }
}

extension PermissionPrompt: AgentComponentRenderable {
    /// Renders the permission request and choices.
    /// - Complexity: O(n), where n is the resources and choices count.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let riskRole: SemanticTextRole = risk >= .destructive ? .diagnostic : .body
        var lines = [
            AgentGrid.line(AgentGrid.span("Permission required", role: riskRole, attributes: .bold)),
            StyledText(requestedAction),
        ]
        lines.append(contentsOf: resources.map { StyledText("• \($0)", role: .muted) })
        lines.append(
            contentsOf: choices.enumerated().map { index, choice in
                AgentGrid.line(
                    AgentGrid.span(index == focusedChoiceIndex ? "▌ " : "  ", role: .listMarker),
                    AgentGrid.span(
                        choice.label,
                        role: choice.requiresStrongEmphasis ? .diagnostic : .body,
                        attributes: index == focusedChoiceIndex ? .bold : []
                    )
                )
            }
        )
        let children = choices.enumerated().map { index, choice in
            SemanticNode(
                id: SemanticID(rawValue: "permission-choice-\(index)"),
                role: .button,
                label: choice.label,
                state: index == focusedChoiceIndex ? .focused : [],
                actions: [.activate]
            )
        }
        return AgentGrid.output(
            id: "permission-prompt",
            role: .dialog,
            label: requestedAction,
            lines: lines,
            context: context,
            state: [.modal, .focused],
            actions: [.focus],
            children: children
        )
    }
}

extension QuestionPrompt: AgentComponentRenderable {
    /// Renders the questions and current answers.
    /// - Complexity: O(n), where n is the questions, options, and rules count.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        var lines: [StyledText] = []
        var children: [SemanticNode] = []
        for (questionIndex, question) in questions.enumerated() {
            lines.append(StyledText("\(questionIndex + 1). \(question.title)", role: .heading(3)))
            if let detail = question.detail { lines.append(StyledText(detail, role: .muted)) }
            switch question.kind {
            case .customText:
                let value: String
                if case .text(let text) = answers[question.id] { value = text } else { value = "Enter a response" }
                lines.append(StyledText("  \(value)", role: answers[question.id] == nil ? .muted : .body))
            case .singleSelection, .multipleSelection:
                let selected: Set<String>
                if case .optionIDs(let ids) = answers[question.id] { selected = ids } else { selected = [] }
                for option in question.options {
                    let marker =
                        question.kind == .singleSelection
                        ? (selected.contains(option.id) ? "●" : "○")
                        : (selected.contains(option.id) ? "☑" : "☐")
                    lines.append(
                        AgentGrid.line(
                            AgentGrid.span("  \(marker) ", role: .listMarker),
                            AgentGrid.span(option.label),
                            AgentGrid.span(option.detail.map { "  \($0)" } ?? "", role: .muted)
                        )
                    )
                    children.append(
                        SemanticNode(
                            id: SemanticID(rawValue: "question-\(questionIndex)-\(option.id)"),
                            role: .listItem,
                            label: option.label,
                            state: selected.contains(option.id) ? .selected : [],
                            actions: [.activate]
                        )
                    )
                }
            }
            if isQuestionValid(at: questionIndex) == false {
                lines.append(StyledText("Answer required or invalid", role: .diagnostic))
            }
        }
        return AgentGrid.output(
            id: "question-prompt",
            role: .dialog,
            label: "Questions",
            lines: lines,
            context: context,
            state: .modal,
            actions: [.focus, .submit, .dismiss, .setValue],
            children: children
        )
    }
}

extension TodoItem: AgentComponentRenderable {
    /// Renders the task item.
    /// - Complexity: O(n), where n is the title and detail length.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let symbol: String =
            switch state {
            case .pending: "○"
            case .inProgress: context.isReducedMotionEnabled ? "…" : "◉"
            case .completed: "✓"
            case .cancelled: "−"
            }
        let role: SemanticTextRole = usesMutedText ? .muted : .body
        var lines = [AgentGrid.line(AgentGrid.span("\(symbol) ", role: .listMarker), AgentGrid.span(title, role: role))]
        if let detail { lines.append(StyledText("  " + detail, role: .muted)) }
        var semanticState: SemanticState = []
        if state == .inProgress { semanticState.insert(.busy) }
        if state == .completed { semanticState.insert(.checked) }
        if state == .cancelled { semanticState.insert(.disabled) }
        return AgentGrid.output(
            id: "todo-item",
            role: .listItem,
            label: title,
            lines: lines,
            context: context,
            state: semanticState
        )
    }
}

extension SessionSidebar: AgentComponentRenderable where Item: AgentContentPresentable {
    /// Renders visible sidebar sections and items.
    /// - Complexity: O(n), where n is the number and length of visible items.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        guard isVisible(forTerminalWidth: context.width) else {
            return AgentGrid.output(
                id: "session-sidebar",
                role: .group,
                label: "Session sidebar",
                lines: [],
                context: context
            )
        }
        let sidebarWidth = max(1, policy.sidebarWidth(forTerminalWidth: context.width))
        var lines: [StyledText] = []
        var children: [SemanticNode] = []
        for (sectionIndex, section) in sections.enumerated() {
            lines.append(StyledText(section.title, role: .heading(3)))
            lines.append(contentsOf: section.items.map { StyledText("  " + $0.agentStyledText.plainText) })
            children.append(
                SemanticNode(
                    id: SemanticID(rawValue: "sidebar-section-\(sectionIndex)"),
                    role: .group,
                    label: section.title
                )
            )
        }
        let localContext = AgentRenderContext(
            width: sidebarWidth,
            theme: context.theme,
            elapsed: context.elapsed,
            reduceMotion: context.isReducedMotionEnabled
        )
        var state: SemanticState = []
        if policy.placement(forTerminalWidth: context.width) == .trailingOverlay { state.insert(.modal) }
        return AgentGrid.output(
            id: "session-sidebar",
            role: .group,
            label: "Session sidebar",
            lines: lines,
            context: localContext,
            state: state,
            actions: state.contains(.modal) ? [.dismiss] : [],
            children: children
        )
    }
}

extension AgentStatusFooter: AgentComponentRenderable {
    /// Renders the status fields that fit the context width.
    /// - Complexity: O(n^2), where n is the number of status fields.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let visible = visibleFields(availableWidth: context.width)
        let text = visible.map(\.text).joined(separator: String(repeating: " ", count: fieldSpacing))
        let children = visible.enumerated().map { index, field in
            SemanticNode(
                id: SemanticID(rawValue: "status-field-\(index)"),
                role: .status,
                label: field.kind.rawValue,
                value: field.text
            )
        }
        return AgentGrid.output(
            id: "agent-status",
            role: .status,
            label: text,
            lines: [StyledText(text, role: .muted)],
            context: context,
            children: children
        )
    }
}

extension BackgroundPulse: AgentComponentRenderable where Frame == BackgroundPulseFrame {
    /// Renders one row of the background pulse.
    /// - Complexity: O(w), where w is the context width.
    public func render(in context: AgentRenderContext) -> AgentRenderOutput {
        let phase = configuration.frameIndex(at: context.isReducedMotionEnabled ? .zero : context.elapsed)
        let generated = frame(size: CellSize(width: context.width, height: 1), frameIndex: phase)
        let occupiedColumns = Set(generated.cells.map(\.point.x))
        let glyphs = (0..<context.width).map { occupiedColumns.contains($0) ? "·" : " " }.joined()
        let line = StyledText(glyphs, role: .muted)
        var state: SemanticState = []
        if configuration.requiresAnimationFrames && context.isReducedMotionEnabled == false { state.insert(.busy) }
        return AgentGrid.output(
            id: "background-pulse",
            role: .progressIndicator,
            label: "Background pulse",
            lines: [line],
            context: context,
            state: state
        )
    }
}
