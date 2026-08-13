// Interaction concepts adapted from OpenCode; no OpenCode source code was copied.
// Design origin: ../../docs/design-origin.md

import TUIFoundation
import TUIAnimation
import TUIDesign
import TUILayout
import TUIViewGraph

/// A character-offset selection in a prompt document.
public struct PromptSelection: Sendable, Hashable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
        precondition(anchor >= 0 && head >= 0, "Prompt selection offsets must not be negative.")
        self.anchor = anchor
        self.head = head
    }

    public init(caret: Int) {
        self.init(anchor: caret, head: caret)
    }

    public var range: Range<Int> {
        min(anchor, head)..<max(anchor, head)
    }

    public var isCollapsed: Bool { anchor == head }
}

/// Editable prompt text and its current selection.
public struct PromptDocument: Sendable, Hashable {
    public var text: String
    public var selection: PromptSelection

    public init(text: String = "", selection: PromptSelection? = nil) {
        let characterCount = text.count
        let resolvedSelection = selection ?? PromptSelection(caret: characterCount)
        precondition(
            resolvedSelection.anchor <= characterCount && resolvedSelection.head <= characterCount,
            "Prompt selection offsets must be within the document."
        )
        self.text = text
        self.selection = resolvedSelection
    }

    public mutating func apply(_ insertion: PromptInsertion) {
        let characterCount = text.count
        let lowerBound = min(max(0, insertion.replacementRange.lowerBound), characterCount)
        let upperBound = min(max(lowerBound, insertion.replacementRange.upperBound), characterCount)
        let start = text.index(text.startIndex, offsetBy: lowerBound)
        let end = text.index(text.startIndex, offsetBy: upperBound)
        text.replaceSubrange(start..<end, with: insertion.text)

        let replacementCount = insertion.text.count
        let cursorOffset = min(max(0, insertion.cursorOffset), replacementCount)
        selection = PromptSelection(caret: lowerBound + cursorOffset)
    }
}

public enum AgentPromptMode: String, Sendable, Hashable, CaseIterable {
    case conversation
    case command
}

/// Provider, model, agent, and variant labels shown below the prompt.
public struct AgentPromptMetadata: Sendable, Hashable {
    public var agent: String?
    public var model: String?
    public var provider: String?
    public var variant: String?

    public init(agent: String? = nil, model: String? = nil, provider: String? = nil, variant: String? = nil) {
        self.agent = agent
        self.model = model
        self.provider = provider
        self.variant = variant
    }
}

/// Presentation configuration that has no session or provider dependency.
public struct AgentPromptConfiguration: Sendable, Hashable {
    public var mode: AgentPromptMode
    public var placeholder: String
    public var isEnabled: Bool
    public var isBusy: Bool
    public var metadata: AgentPromptMetadata
    public var animationsEnabled: Bool
    public var colorScheme: ColorScheme
    public var pastePolicy: AgentPromptPastePolicy

    public init(
        mode: AgentPromptMode = .conversation,
        placeholder: String = "Ask anything",
        isEnabled: Bool = true,
        isBusy: Bool = false,
        metadata: AgentPromptMetadata = AgentPromptMetadata(),
        animationsEnabled: Bool = true,
        colorScheme: ColorScheme = .dark,
        pastePolicy: AgentPromptPastePolicy = AgentPromptPastePolicy()
    ) {
        self.mode = mode
        self.placeholder = placeholder
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        self.metadata = metadata
        self.animationsEnabled = animationsEnabled
        self.colorScheme = colorScheme
        self.pastePolicy = pastePolicy
    }

    public var metadataTransitionDuration: TUIDuration {
        animationsEnabled ? .milliseconds(150) : .zero
    }

    @MainActor
    public func metadataOpacityTrack(
        from start: Double = 0,
        to target: Double = 1,
        at instant: TimeInstant
    ) -> AnimationTrack<Double> {
        AnimationTrack(
            from: animationsEnabled ? start : target,
            to: target,
            at: instant,
            animation: animationsEnabled ? .easeOut(duration: metadataTransitionDuration) : nil
        )
    }
}

public struct AgentPromptPastePolicy: Sendable, Hashable {
    public enum LargePasteBehavior: Sendable, Hashable {
        case accept
        case reject
    }

    public var largePasteThreshold: Int
    public var largePasteBehavior: LargePasteBehavior

    public init(largePasteThreshold: Int = 100_000, largePasteBehavior: LargePasteBehavior = .reject) {
        precondition(largePasteThreshold > 0, "The large-paste threshold must be positive.")
        self.largePasteThreshold = largePasteThreshold
        self.largePasteBehavior = largePasteBehavior
    }

    public func accepts(_ text: String) -> Bool {
        text.count <= largePasteThreshold || largePasteBehavior == .accept
    }
}

public enum AgentPromptDiagnostic: Sendable, Hashable {
    case pasteRejected(characterCount: Int, limit: Int)
}

/// User actions emitted by an agent prompt.
public struct AgentPromptActions<Attachment: Sendable>: Sendable {
    public var submit: @MainActor @Sendable (PromptDocument) -> Void
    public var cancel: @MainActor @Sendable () -> Void
    public var paste: @MainActor @Sendable (String) -> Void
    public var attach: @MainActor @Sendable (Attachment) -> Void
    public var diagnostic: @MainActor @Sendable (AgentPromptDiagnostic) -> Void

    public init(
        submit: @escaping @MainActor @Sendable (PromptDocument) -> Void,
        cancel: @escaping @MainActor @Sendable () -> Void,
        paste: @escaping @MainActor @Sendable (String) -> Void,
        attach: @escaping @MainActor @Sendable (Attachment) -> Void
    ) {
        self.init(submit: submit, cancel: cancel, paste: paste, attach: attach, diagnostic: { _ in })
    }

    public init(
        submit: @escaping @MainActor @Sendable (PromptDocument) -> Void,
        cancel: @escaping @MainActor @Sendable () -> Void,
        paste: @escaping @MainActor @Sendable (String) -> Void,
        attach: @escaping @MainActor @Sendable (Attachment) -> Void,
        diagnostic: @escaping @MainActor @Sendable (AgentPromptDiagnostic) -> Void
    ) {
        self.submit = submit
        self.cancel = cancel
        self.paste = paste
        self.attach = attach
        self.diagnostic = diagnostic
    }
}

/// Fixed prompt metrics and width resolution for a terminal viewport.
public struct AgentPromptLayoutPolicy: Sendable, Hashable {
    public var horizontalPadding: Int
    public var topPadding: Int
    public var railWidth: Int
    public var minimumPreferredWidth: Int
    public var widthFraction: Double

    public init(
        horizontalPadding: Int = 2,
        topPadding: Int = 1,
        railWidth: Int = 1,
        minimumPreferredWidth: Int = 75,
        widthFraction: Double = 0.7
    ) {
        precondition(horizontalPadding >= 0 && topPadding >= 0 && railWidth >= 0)
        precondition(minimumPreferredWidth >= 0 && widthFraction >= 0 && widthFraction.isFinite)
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.railWidth = railWidth
        self.minimumPreferredWidth = minimumPreferredWidth
        self.widthFraction = widthFraction
    }

    public func preferredMaximumWidth(forTerminalWidth terminalWidth: Int) -> Int {
        precondition(terminalWidth >= 0)
        return max(minimumPreferredWidth, Int((Double(terminalWidth) * widthFraction).rounded(.down)))
    }

    public func resolvedWidth(forTerminalWidth terminalWidth: Int) -> Int {
        min(terminalWidth, preferredMaximumWidth(forTerminalWidth: terminalWidth))
    }
}

/// A prompt component model whose only effects are explicit actions.
public struct AgentPrompt<Attachment: Sendable>: Sendable {
    public var document: PromptDocument
    public var configuration: AgentPromptConfiguration
    public var layoutPolicy: AgentPromptLayoutPolicy
    public var actions: AgentPromptActions<Attachment>
    private var documentBinding: Binding<PromptDocument>?
    private var leadingAccessory: @MainActor @Sendable () -> [NodeDescriptor]
    private var trailingAccessory: @MainActor @Sendable () -> [NodeDescriptor]

    public init(
        document: PromptDocument,
        configuration: AgentPromptConfiguration = AgentPromptConfiguration(),
        layoutPolicy: AgentPromptLayoutPolicy = AgentPromptLayoutPolicy(),
        actions: AgentPromptActions<Attachment>
    ) {
        self.document = document
        self.configuration = configuration
        self.layoutPolicy = layoutPolicy
        self.actions = actions
        documentBinding = nil
        leadingAccessory = { [] }
        trailingAccessory = { [] }
    }

    @MainActor
    public init(
        _ document: Binding<PromptDocument>,
        configuration: AgentPromptConfiguration = AgentPromptConfiguration(),
        layoutPolicy: AgentPromptLayoutPolicy = AgentPromptLayoutPolicy(),
        actions: AgentPromptActions<Attachment>,
        @ViewBuilder leadingAccessory: @escaping @MainActor @Sendable () -> [NodeDescriptor],
        @ViewBuilder trailingAccessory: @escaping @MainActor @Sendable () -> [NodeDescriptor]
    ) {
        self.document = document.wrappedValue
        self.configuration = configuration
        self.layoutPolicy = layoutPolicy
        self.actions = actions
        documentBinding = document
        self.leadingAccessory = { buildViewGraph(leadingAccessory) }
        self.trailingAccessory = { buildViewGraph(trailingAccessory) }
    }

    @MainActor
    public init(
        _ document: Binding<PromptDocument>,
        configuration: AgentPromptConfiguration = AgentPromptConfiguration(),
        layoutPolicy: AgentPromptLayoutPolicy = AgentPromptLayoutPolicy(),
        actions: AgentPromptActions<Attachment>
    ) {
        self.document = document.wrappedValue
        self.configuration = configuration
        self.layoutPolicy = layoutPolicy
        self.actions = actions
        documentBinding = document
        leadingAccessory = { [] }
        trailingAccessory = { [] }
    }

    @MainActor
    public var currentDocument: PromptDocument {
        documentBinding?.wrappedValue ?? document
    }

    @MainActor
    public mutating func replaceDocument(with document: PromptDocument) {
        setDocument(document)
    }

    @MainActor
    public mutating func insert(_ insertion: PromptInsertion) {
        var updatedDocument = currentDocument
        updatedDocument.apply(insertion)
        setDocument(updatedDocument)
    }

    @MainActor
    @discardableResult
    public mutating func paste(_ text: String) -> Bool {
        guard configuration.pastePolicy.accepts(text) else {
            actions.diagnostic(.pasteRejected(
                characterCount: text.count,
                limit: configuration.pastePolicy.largePasteThreshold
            ))
            return false
        }
        let selection = currentDocument.selection.range
        insert(PromptInsertion(replacementRange: selection, text: text))
        actions.paste(text)
        return true
    }

    @MainActor
    public mutating func insertAutocomplete(_ insertion: PromptInsertion) {
        insert(insertion)
    }

    @MainActor
    public func submit() {
        actions.submit(currentDocument)
    }

    @MainActor
    public mutating func moveCaret(by offset: Int, extendingSelection: Bool = false) {
        var document = currentDocument
        let target: Int
        if extendingSelection || document.selection.isCollapsed {
            target = min(max(0, document.selection.head + offset), document.text.count)
        } else {
            target = offset < 0 ? document.selection.range.lowerBound : document.selection.range.upperBound
        }
        document.selection = extendingSelection
            ? PromptSelection(anchor: document.selection.anchor, head: target)
            : PromptSelection(caret: target)
        setDocument(document)
    }

    @MainActor
    public mutating func deleteBackward() {
        var document = currentDocument
        let range = document.selection.isCollapsed
            ? max(0, document.selection.head - 1)..<document.selection.head
            : document.selection.range
        guard range.isEmpty == false else { return }
        document.apply(PromptInsertion(replacementRange: range, text: ""))
        setDocument(document)
    }

    @MainActor
    private mutating func setDocument(_ document: PromptDocument) {
        if let documentBinding {
            documentBinding.wrappedValue = document
        } else {
            self.document = document
        }
    }
}

extension AgentPrompt: TUIViewGraph.View {
    @MainActor
    public var graphBody: [NodeDescriptor] {
        let layout = LayoutPrimitive.stack(StackLayout(axis: .horizontal))
        var renderValue = self
        renderValue.document = currentDocument
        var children = leadingAccessory()
        var promptChildren = [NodeDescriptor(
            type: AgentPromptRenderLeaf<Attachment>.self,
            key: AgentPromptRenderLeaf<Attachment>.key,
            primitive: AgentPromptRenderLeaf(renderValue),
            focus: FocusMetadata(isFocusable: configuration.isEnabled),
            hitTest: HitTestMetadata(isEnabled: configuration.isEnabled),
            dirtyOnUpdate: .layout
        )]
        let metadata = configuration.metadata.displayText
        if metadata.isEmpty == false {
            let leaf = NodeDescriptor(
                type: AgentPromptMetadataLeaf.self,
                primitive: AgentPromptMetadataLeaf(text: metadata),
                dirtyOnUpdate: .layout
            )
            let metadataContainer: NodeDescriptor
            if configuration.animationsEnabled {
                var transaction = Transaction.current
                transaction.animation = .easeOut(duration: configuration.metadataTransitionDuration)
                metadataContainer = withTransaction(transaction) {
                    NodeDescriptor(
                        type: AgentPromptMetadataTransitionContainer.self,
                        key: metadata,
                        children: [leaf],
                        dirtyOnUpdate: .layout
                    )
                    .transition(.opacity)
                }
            } else {
                metadataContainer = NodeDescriptor(
                    type: AgentPromptMetadataTransitionContainer.self,
                    key: metadata,
                    children: [leaf],
                    dirtyOnUpdate: .layout
                )
            }
            promptChildren.append(metadataContainer)
        }
        children.append(NodeDescriptor(
            type: AgentPromptContentLayout.self,
            key: "prompt-content",
            value: LayoutPrimitive.stack(StackLayout(axis: .vertical)),
            primitive: LayoutPrimitive.stack(StackLayout(axis: .vertical)),
            children: promptChildren,
            dirtyOnUpdate: .layout
        ))
        children.append(contentsOf: trailingAccessory())
        return [NodeDescriptor(
            type: AgentPromptRetainedLayout.self,
            value: layout,
            primitive: layout,
            children: children,
            dirtyOnUpdate: .layout
        )]
    }
}

private enum AgentPromptRetainedLayout {}
private enum AgentPromptContentLayout {}
private enum AgentPromptMetadataTransitionContainer {}

extension AgentPromptMetadata {
    var displayText: String {
        [agent, model, provider, variant].compactMap { $0 }.joined(separator: " · ")
    }
}

struct AgentPromptMetadataLeaf: Sendable {
    var text: String
}

struct AgentPromptRenderLeaf<Attachment: Sendable>: Sendable {
    static var key: String { "prompt-editor" }

    var prompt: AgentPrompt<Attachment>

    init(_ prompt: AgentPrompt<Attachment>) {
        self.prompt = prompt
    }
}

public enum PromptSuggestionKind: String, Sendable, Hashable, CaseIterable {
    case command
    case file
    case agent
    case symbol
}

/// A typed autocomplete result that does not mutate the prompt directly.
public struct PromptSuggestion<ID: Sendable & Hashable>: Sendable, Hashable {
    public var id: ID
    public var kind: PromptSuggestionKind
    public var title: String
    public var detail: String?
    public var insertion: PromptInsertion

    public init(id: ID, kind: PromptSuggestionKind, title: String, detail: String? = nil, insertion: PromptInsertion) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.insertion = insertion
    }
}

/// A semantic replacement returned by an autocomplete provider.
public struct PromptInsertion: Sendable, Hashable {
    public var replacementRange: Range<Int>
    public var text: String
    public var cursorOffset: Int

    public init(replacementRange: Range<Int>, text: String, cursorOffset: Int? = nil) {
        precondition(replacementRange.lowerBound >= 0, "A replacement range must not start before the document.")
        let resolvedCursorOffset = cursorOffset ?? text.count
        precondition(resolvedCursorOffset >= 0 && resolvedCursorOffset <= text.count)
        self.replacementRange = replacementRange
        self.text = text
        self.cursorOffset = resolvedCursorOffset
    }
}

public struct PromptAutocompleteContext: Sendable, Hashable {
    public var document: PromptDocument
    public var queryRange: Range<Int>
    public var trigger: Character?

    public init(document: PromptDocument, queryRange: Range<Int>, trigger: Character? = nil) {
        precondition(queryRange.lowerBound >= 0 && queryRange.upperBound <= document.text.count)
        self.document = document
        self.queryRange = queryRange
        self.trigger = trigger
    }
}

public protocol PromptAutocompleteProvider: Sendable {
    associatedtype SuggestionID: Sendable & Hashable

    func suggestions(for context: PromptAutocompleteContext) async throws -> [PromptSuggestion<SuggestionID>]
}

/// Selection and anchor state for an autocomplete overlay.
public struct PromptAutocompleteState<ID: Sendable & Hashable>: Sendable, Hashable {
    public var suggestions: [PromptSuggestion<ID>]
    public var selectedIndex: Int?
    public var anchorColumn: Int
    public var anchorRow: Int

    public init(
        suggestions: [PromptSuggestion<ID>] = [],
        selectedIndex: Int? = nil,
        anchorColumn: Int = 0,
        anchorRow: Int = 0
    ) {
        precondition(anchorColumn >= 0 && anchorRow >= 0)
        self.suggestions = suggestions
        self.anchorColumn = anchorColumn
        self.anchorRow = anchorRow
        if let selectedIndex, suggestions.indices.contains(selectedIndex) {
            self.selectedIndex = selectedIndex
        } else {
            self.selectedIndex = suggestions.isEmpty ? nil : 0
        }
    }

    public var selectedSuggestion: PromptSuggestion<ID>? {
        guard let selectedIndex, suggestions.indices.contains(selectedIndex) else { return nil }
        return suggestions[selectedIndex]
    }

    public var isPresented: Bool { suggestions.isEmpty == false }

    public mutating func moveSelection(by offset: Int) {
        guard suggestions.isEmpty == false else {
            selectedIndex = nil
            return
        }
        let current = selectedIndex ?? 0
        selectedIndex = min(max(0, current + offset), suggestions.count - 1)
    }
}

/// An anchored adapter that presents prompt suggestions through ``SelectList``.
@MainActor
public final class PromptAutocomplete<ID: Sendable & Hashable>: Hashable {
    public var suggestions: [PromptSuggestion<ID>] {
        didSet { selectList.items = Self.items(from: suggestions, isEnabled: isEnabled) }
    }
    public let selectList: SelectList<ID>
    public var anchorColumn: Int
    public var anchorRow: Int
    public var isEnabled: Bool {
        didSet { selectList.items = Self.items(from: suggestions, isEnabled: isEnabled) }
    }
    public var onInsert: (@MainActor @Sendable (PromptInsertion) -> Void)?

    public init(
        state: PromptAutocompleteState<ID>,
        isEnabled: Bool = true,
        onInsert: (@MainActor @Sendable (PromptInsertion) -> Void)? = nil
    ) {
        suggestions = state.suggestions
        anchorColumn = state.anchorColumn
        anchorRow = state.anchorRow
        self.isEnabled = isEnabled
        self.onInsert = onInsert
        let selectedID = state.selectedIndex.flatMap { index in
            state.suggestions.indices.contains(index) ? state.suggestions[index].id : nil
        }
        selectList = SelectList(
            id: "prompt-autocomplete",
            items: Self.items(from: state.suggestions, isEnabled: isEnabled),
            selectedID: selectedID
        )
        selectList.onActivate = { [weak self] id in
            _ = self?.activate(id)
        }
    }

    public var state: PromptAutocompleteState<ID> {
        get {
            PromptAutocompleteState(
                suggestions: suggestions,
                selectedIndex: selectList.selectedID.flatMap { selectedID in
                    suggestions.firstIndex { $0.id == selectedID }
                },
                anchorColumn: anchorColumn,
                anchorRow: anchorRow
            )
        }
        set {
            suggestions = newValue.suggestions
            anchorColumn = newValue.anchorColumn
            anchorRow = newValue.anchorRow
            if let index = newValue.selectedIndex, newValue.suggestions.indices.contains(index) {
                let selectedID = newValue.suggestions[index].id
                if let filteredIndex = selectList.filteredItems.firstIndex(where: { $0.id == selectedID }) {
                    _ = selectList.select(at: filteredIndex)
                }
            }
        }
    }

    public var query: String {
        get { selectList.query }
        set { selectList.setQuery(newValue) }
    }

    public var selectedSuggestion: PromptSuggestion<ID>? {
        guard let selectedID = selectList.selectedID else { return nil }
        return suggestions.first { $0.id == selectedID }
    }

    public var isPresented: Bool { suggestions.isEmpty == false }

    @discardableResult
    public func moveSelection(by offset: Int, wrapping: Bool = true) -> ID? {
        selectList.move(by: offset, wrapping: wrapping)
    }

    @discardableResult
    public func activateSelection() -> PromptInsertion? {
        guard isEnabled, let selectedID = selectList.activateSelection() else { return nil }
        return suggestions.first { $0.id == selectedID }?.insertion
    }

    nonisolated public static func == (lhs: PromptAutocomplete, rhs: PromptAutocomplete) -> Bool {
        lhs === rhs
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    @discardableResult
    private func activate(_ id: ID) -> PromptInsertion? {
        guard isEnabled, let insertion = suggestions.first(where: { $0.id == id })?.insertion else { return nil }
        onInsert?(insertion)
        return insertion
    }

    private static func items(
        from suggestions: [PromptSuggestion<ID>],
        isEnabled: Bool = true
    ) -> [SelectListItem<ID>] {
        suggestions.map { suggestion in
            SelectListItem(
                id: suggestion.id,
                title: suggestion.title,
                details: suggestion.detail,
                group: suggestion.kind.rawValue,
                searchTerms: [suggestion.kind.rawValue],
                isEnabled: isEnabled
            )
        }
    }
}

extension PromptAutocomplete: TUIViewGraph.View {
    public var graphBody: [NodeDescriptor] {
        guard isPresented else { return [] }
        return selectList.view()
            .offset(x: Double(anchorColumn), y: Double(anchorRow))
            .graphBody
    }
}
