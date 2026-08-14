// Design origin: ../../docs/design-origin.md

/// A character-offset selection in a prompt document.
public struct PromptSelection: Sendable, Hashable {
  /// The fixed end of the selection.
  public var anchor: Int
  /// The active end of the selection.
  public var head: Int

  /// Creates a selection from character offsets.
  public init(anchor: Int, head: Int) {
    precondition(anchor >= 0 && head >= 0, "Prompt selection offsets must not be negative.")
    self.anchor = anchor
    self.head = head
  }

  /// Creates a collapsed selection at a caret offset.
  public init(caret: Int) {
    self.init(anchor: caret, head: caret)
  }

  /// The normalized selected range.
  /// - Complexity: O(1).
  public var range: Range<Int> {
    min(anchor, head) ..< max(anchor, head)
  }

  /// A Boolean value that indicates whether the selection is a caret.
  public var isCollapsed: Bool {
    anchor == head
  }
}

/// Editable prompt text and its current selection.
public struct PromptDocument: Sendable, Hashable {
  /// The editable text.
  public var text: String
  /// The current selection.
  public var selection: PromptSelection

  /// Creates a prompt document.
  /// - Complexity: O(n), where n is the number of characters in the text.
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

  /// Applies a replacement and moves the caret to its requested offset.
  /// - Complexity: O(n), where n is the number of characters in the document and replacement.
  public mutating func apply(_ insertion: PromptInsertion) {
    let characterCount = text.count
    let lowerBound = min(max(0, insertion.replacementRange.lowerBound), characterCount)
    let upperBound = min(max(lowerBound, insertion.replacementRange.upperBound), characterCount)
    let start = text.index(text.startIndex, offsetBy: lowerBound)
    let end = text.index(text.startIndex, offsetBy: upperBound)
    text.replaceSubrange(start ..< end, with: insertion.text)

    let replacementCount = insertion.text.count
    let cursorOffset = min(max(0, insertion.cursorOffset), replacementCount)
    selection = PromptSelection(caret: lowerBound + cursorOffset)
  }
}

/// The input mode of an agent prompt.
public enum AgentPromptMode: String, Sendable, Hashable, CaseIterable {
  /// Accepts conversational input.
  case conversation
  /// Accepts command input.
  case command
}

/// Provider, model, agent, and variant labels shown below the prompt.
public struct AgentPromptMetadata: Sendable, Hashable {
  /// The active agent label, if available.
  public var agent: String?
  /// The active model label, if available.
  public var model: String?
  /// The provider label, if available.
  public var provider: String?
  /// The model variant label, if available.
  public var variant: String?

  /// Creates prompt metadata.
  public init(agent: String? = nil, model: String? = nil, provider: String? = nil, variant: String? = nil) {
    self.agent = agent
    self.model = model
    self.provider = provider
    self.variant = variant
  }
}

/// Presentation configuration that has no session or provider dependency.
public struct AgentPromptConfiguration: Sendable, Hashable {
  /// The prompt input mode.
  public var mode: AgentPromptMode
  /// The placeholder shown for an empty prompt.
  public var placeholder: String
  /// A Boolean value that indicates whether input is enabled.
  public var isEnabled: Bool
  /// A Boolean value that indicates whether the agent is busy.
  public var isBusy: Bool
  /// The metadata shown with the prompt.
  public var metadata: AgentPromptMetadata
  /// A Boolean value that indicates whether animations are enabled.
  public var areAnimationsEnabled: Bool
  /// The prompt color scheme.
  public var colorScheme: ColorScheme
  /// The policy for pasted text.
  public var pastePolicy: AgentPromptPastePolicy

  /// Creates an agent prompt configuration.
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
    self.areAnimationsEnabled = animationsEnabled
    self.colorScheme = colorScheme
    self.pastePolicy = pastePolicy
  }

  /// The duration of prompt metadata transitions.
  public var metadataTransitionDuration: TimeSpan {
    areAnimationsEnabled ? .milliseconds(150) : .zero
  }

  /// Creates an opacity animation track for prompt metadata.
  /// - Complexity: O(1).
  @MainActor
  public func metadataOpacityTrack(
    at instant: TimeInstant,
    from start: Double = 0,
    to target: Double = 1
  ) -> AnimationTrack<Double> {
    AnimationTrack(
      from: areAnimationsEnabled ? start : target,
      to: target,
      at: instant,
      animation: areAnimationsEnabled ? .easeOut(duration: metadataTransitionDuration) : nil
    )
  }
}

/// Rules for accepting pasted prompt text.
public struct AgentPromptPastePolicy: Sendable, Hashable {
  /// The response to text that exceeds the large-paste threshold.
  public enum LargePasteBehavior: Sendable, Hashable {
    /// Accepts large pasted text.
    case accept
    /// Rejects large pasted text.
    case reject
  }

  /// The character count that identifies a large paste.
  public var largePasteThreshold: Int
  /// The response to a large paste.
  public var largePasteBehavior: LargePasteBehavior

  /// Creates a prompt paste policy.
  public init(largePasteThreshold: Int = 100000, largePasteBehavior: LargePasteBehavior = .reject) {
    precondition(largePasteThreshold > 0, "The large-paste threshold must be positive.")
    self.largePasteThreshold = largePasteThreshold
    self.largePasteBehavior = largePasteBehavior
  }

  /// Returns whether the policy accepts the specified text.
  /// - Complexity: O(n), where n is the number of characters in the text.
  public func accepts(_ text: String) -> Bool {
    text.count <= largePasteThreshold || largePasteBehavior == .accept
  }
}

/// A diagnostic emitted by an agent prompt.
public enum AgentPromptDiagnostic: Sendable, Hashable {
  /// A paste exceeded the configured character limit.
  case pasteRejected(characterCount: Int, limit: Int)
}

/// User actions emitted by an agent prompt.
public struct AgentPromptActions<Attachment: Sendable>: Sendable {
  /// Submits a prompt document.
  public var submit: @MainActor @Sendable (_ document: PromptDocument) -> Void
  /// Cancels the current prompt operation.
  public var cancel: @MainActor @Sendable () -> Void
  /// Reports accepted pasted text.
  public var paste: @MainActor @Sendable (_ text: String) -> Void
  /// Adds an attachment.
  public var attach: @MainActor @Sendable (_ attachment: Attachment) -> Void
  /// Reports a prompt diagnostic.
  public var diagnostic: @MainActor @Sendable (_ diagnostic: AgentPromptDiagnostic) -> Void

  /// Creates prompt actions without a diagnostic handler.
  public init(
    submit: @escaping @MainActor @Sendable (_ document: PromptDocument) -> Void,
    cancel: @escaping @MainActor @Sendable () -> Void,
    paste: @escaping @MainActor @Sendable (_ text: String) -> Void,
    attach: @escaping @MainActor @Sendable (_ attachment: Attachment) -> Void
  ) {
    self.init(submit: submit, cancel: cancel, paste: paste, attach: attach, diagnostic: { _ in })
  }

  /// Creates prompt actions with a diagnostic handler.
  public init(
    submit: @escaping @MainActor @Sendable (_ document: PromptDocument) -> Void,
    cancel: @escaping @MainActor @Sendable () -> Void,
    paste: @escaping @MainActor @Sendable (_ text: String) -> Void,
    attach: @escaping @MainActor @Sendable (_ attachment: Attachment) -> Void,
    diagnostic: @escaping @MainActor @Sendable (_ diagnostic: AgentPromptDiagnostic) -> Void
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
  /// The horizontal content padding in cells.
  public var horizontalPadding: Int
  /// The top content padding in cells.
  public var topPadding: Int
  /// The width of the leading rail in cells.
  public var railWidth: Int
  /// The minimum preferred prompt width.
  public var minimumPreferredWidth: Int
  /// The fraction of terminal width used for the preferred maximum.
  public var widthFraction: Double

  /// Creates an agent prompt layout policy.
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

  /// Returns the preferred maximum width for a terminal width.
  /// - Complexity: O(1).
  public func preferredMaximumWidth(forTerminalWidth terminalWidth: Int) -> Int {
    precondition(terminalWidth >= 0)
    return max(minimumPreferredWidth, Int((Double(terminalWidth) * widthFraction).rounded(.down)))
  }

  /// Returns the prompt width for a terminal width.
  /// - Complexity: O(1).
  public func resolvedWidth(forTerminalWidth terminalWidth: Int) -> Int {
    min(terminalWidth, preferredMaximumWidth(forTerminalWidth: terminalWidth))
  }
}

/// A prompt component model whose only effects are explicit actions.
public struct AgentPrompt<Attachment: Sendable>: Sendable {
  /// The prompt document snapshot.
  public var document: PromptDocument
  /// The prompt presentation configuration.
  public var configuration: AgentPromptConfiguration
  /// The prompt layout policy.
  public var layoutPolicy: AgentPromptLayoutPolicy
  /// The actions emitted by the prompt.
  public var actions: AgentPromptActions<Attachment>
  private var documentBinding: Binding<PromptDocument>?
  private var leadingAccessory: @MainActor @Sendable () -> [NodeDescriptor]
  private var trailingAccessory: @MainActor @Sendable () -> [NodeDescriptor]

  /// Creates an unbound agent prompt.
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
    self.documentBinding = nil
    self.leadingAccessory = { [] }
    self.trailingAccessory = { [] }
  }

  /// Creates a bound prompt with leading and trailing accessories.
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
    self.documentBinding = document
    self.leadingAccessory = { buildViewGraph(leadingAccessory) }
    self.trailingAccessory = { buildViewGraph(trailingAccessory) }
  }

  /// Creates a bound prompt without accessories.
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
    self.documentBinding = document
    self.leadingAccessory = { [] }
    self.trailingAccessory = { [] }
  }

  /// The current document from the binding or local snapshot.
  /// - Complexity: O(1).
  @MainActor
  public var currentDocument: PromptDocument {
    documentBinding?.wrappedValue ?? document
  }

  /// Replaces the current prompt document.
  /// - Complexity: O(1), excluding binding observers.
  @MainActor
  public mutating func replaceDocument(with document: PromptDocument) {
    setDocument(document)
  }

  /// Applies an insertion to the current document.
  /// - Complexity: O(n), where n is the document and replacement length.
  @MainActor
  public mutating func insert(_ insertion: PromptInsertion) {
    var updatedDocument = currentDocument
    updatedDocument.apply(insertion)
    setDocument(updatedDocument)
  }

  /// Pastes text when the configured policy accepts it.
  /// - Complexity: O(n), where n is the document and pasted text length.
  @MainActor
  @discardableResult
  public mutating func paste(_ text: String) -> Bool {
    guard configuration.pastePolicy.accepts(text) else {
      actions.diagnostic(
        .pasteRejected(
          characterCount: text.count,
          limit: configuration.pastePolicy.largePasteThreshold
        )
      )
      return false
    }
    let selection = currentDocument.selection.range
    insert(PromptInsertion(replacementRange: selection, text: text))
    actions.paste(text)
    return true
  }

  /// Applies an autocomplete insertion.
  /// - Complexity: O(n), where n is the document and replacement length.
  @MainActor
  public mutating func insertAutocomplete(_ insertion: PromptInsertion) {
    insert(insertion)
  }

  /// Submits the current document.
  /// - Complexity: O(1), excluding action work.
  @MainActor
  public func submit() {
    actions.submit(currentDocument)
  }

  /// Moves the caret or active selection end by a character offset.
  /// - Complexity: O(n), where n is the number of document characters.
  @MainActor
  public mutating func moveCaret(by offset: Int, extendingSelection: Bool = false) {
    var document = currentDocument
    let target: Int = if extendingSelection || document.selection.isCollapsed {
      min(max(0, document.selection.head + offset), document.text.count)
    } else {
      offset < 0 ? document.selection.range.lowerBound : document.selection.range.upperBound
    }
    document.selection =
      extendingSelection
        ? PromptSelection(anchor: document.selection.anchor, head: target)
        : PromptSelection(caret: target)
    setDocument(document)
  }

  /// Deletes the selection or the character before the caret.
  /// - Complexity: O(n), where n is the number of document characters.
  @MainActor
  public mutating func deleteBackward() {
    var document = currentDocument
    let range =
      document.selection.isCollapsed
        ? max(0, document.selection.head - 1) ..< document.selection.head
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

extension AgentPrompt: View {
  /// The view graph for the prompt and its accessories.
  /// - Complexity: O(n), where n is the number of accessory nodes.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    let layout = LayoutPrimitive.stack(StackLayout(axis: .horizontal))
    var renderValue = self
    renderValue.document = currentDocument
    var children = leadingAccessory()
    var promptChildren = [
      NodeDescriptor(
        type: AgentPromptRenderLeaf<Attachment>.self,
        key: AgentPromptRenderLeaf<Attachment>.key,
        primitive: AgentPromptRenderLeaf(renderValue),
        focus: FocusMetadata(isFocusable: configuration.isEnabled),
        hitTest: HitTestMetadata(isEnabled: configuration.isEnabled),
        dirtyOnUpdate: .layout
      )
    ]
    let metadata = configuration.metadata.displayText
    if metadata.isEmpty == false {
      let leaf = NodeDescriptor(
        type: AgentPromptMetadataLeaf.self,
        primitive: AgentPromptMetadataLeaf(text: metadata),
        dirtyOnUpdate: .layout
      )
      let metadataContainer: NodeDescriptor
      if configuration.areAnimationsEnabled {
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
    children.append(
      NodeDescriptor(
        type: AgentPromptContentLayout.self,
        key: "prompt-content",
        value: LayoutPrimitive.stack(StackLayout(axis: .vertical)),
        primitive: LayoutPrimitive.stack(StackLayout(axis: .vertical)),
        children: promptChildren,
        dirtyOnUpdate: .layout
      )
    )
    children.append(contentsOf: trailingAccessory())
    return [
      NodeDescriptor(
        type: AgentPromptRetainedLayout.self,
        value: layout,
        primitive: layout,
        children: children,
        dirtyOnUpdate: .layout
      )
    ]
  }
}

private enum AgentPromptRetainedLayout {}
private enum AgentPromptContentLayout {}
private enum AgentPromptMetadataTransitionContainer {}

extension AgentPromptMetadata {
  var displayText: String {
    [agent, model, provider, variant].compactMap(\.self).joined(separator: " · ")
  }
}

struct AgentPromptMetadataLeaf: Sendable {
  var text: String
}

struct AgentPromptRenderLeaf<Attachment: Sendable>: Sendable {
  static var key: String {
    "prompt-editor"
  }

  var prompt: AgentPrompt<Attachment>

  init(_ prompt: AgentPrompt<Attachment>) {
    self.prompt = prompt
  }
}

/// The category of a prompt suggestion.
public enum PromptSuggestionKind: String, Sendable, Hashable, CaseIterable {
  /// A command suggestion.
  case command
  /// A file suggestion.
  case file
  /// An agent suggestion.
  case agent
  /// A symbol suggestion.
  case symbol
}

/// A typed autocomplete result that does not mutate the prompt directly.
public struct PromptSuggestion<ID: Sendable & Hashable>: Sendable, Hashable {
  /// The stable suggestion identifier.
  public var id: ID
  /// The suggestion category.
  public var kind: PromptSuggestionKind
  /// The suggestion title.
  public var title: String
  /// Additional suggestion details, if available.
  public var detail: String?
  /// The insertion produced by the suggestion.
  public var insertion: PromptInsertion

  /// Creates a prompt suggestion.
  public init(id: ID, kind: PromptSuggestionKind, title: String, insertion: PromptInsertion, detail: String? = nil) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.insertion = insertion
  }
}

/// A semantic replacement returned by an autocomplete provider.
public struct PromptInsertion: Sendable, Hashable {
  /// The character range to replace.
  public var replacementRange: Range<Int>
  /// The replacement text.
  public var text: String
  /// The caret offset within the replacement text.
  public var cursorOffset: Int

  /// Creates a prompt insertion.
  /// - Complexity: O(n), where n is the replacement text length.
  public init(replacementRange: Range<Int>, text: String, cursorOffset: Int? = nil) {
    precondition(replacementRange.lowerBound >= 0, "A replacement range must not start before the document.")
    let resolvedCursorOffset = cursorOffset ?? text.count
    precondition(resolvedCursorOffset >= 0 && resolvedCursorOffset <= text.count)
    self.replacementRange = replacementRange
    self.text = text
    self.cursorOffset = resolvedCursorOffset
  }
}

/// The document state supplied to an autocomplete provider.
public struct PromptAutocompleteContext: Sendable, Hashable {
  /// The current prompt document.
  public var document: PromptDocument
  /// The character range of the active query.
  public var queryRange: Range<Int>
  /// The character that triggered autocomplete, if any.
  public var trigger: Character?

  /// Creates an autocomplete context.
  public init(document: PromptDocument, queryRange: Range<Int>, trigger: Character? = nil) {
    precondition(queryRange.lowerBound >= 0 && queryRange.upperBound <= document.text.count)
    self.document = document
    self.queryRange = queryRange
    self.trigger = trigger
  }
}

/// A provider that asynchronously produces prompt suggestions.
public protocol PromptAutocompleteProvider: Sendable {
  /// The stable identifier type of a suggestion.
  associatedtype SuggestionID: Sendable & Hashable

  /// Returns suggestions for an autocomplete context.
  /// - Complexity: Depends on the provider implementation.
  func suggestions(for context: PromptAutocompleteContext) async throws -> [PromptSuggestion<SuggestionID>]
}

/// Selection and anchor state for an autocomplete overlay.
public struct PromptAutocompleteState<ID: Sendable & Hashable>: Sendable, Hashable {
  /// The available suggestions.
  public var suggestions: [PromptSuggestion<ID>]
  /// The selected suggestion index, if any.
  public var selectedIndex: Int?
  /// The overlay anchor column.
  public var anchorColumn: Int
  /// The overlay anchor row.
  public var anchorRow: Int

  /// Creates autocomplete overlay state.
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

  /// The selected suggestion, if the selected index is valid.
  /// - Complexity: O(1).
  public var selectedSuggestion: PromptSuggestion<ID>? {
    guard let selectedIndex, suggestions.indices.contains(selectedIndex) else { return nil }
    return suggestions[selectedIndex]
  }

  /// A Boolean value that indicates whether suggestions are presented.
  public var isPresented: Bool {
    suggestions.isEmpty == false
  }

  /// Moves selection by an offset and clamps it to the suggestion list.
  /// - Complexity: O(1).
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
  /// The suggestions displayed by the overlay.
  public var suggestions: [PromptSuggestion<ID>] {
    didSet { selectList.items = Self.items(from: suggestions, isEnabled: isEnabled) }
  }

  /// The select list that presents suggestions.
  public let selectList: SelectList<ID>
  /// The overlay anchor column.
  public var anchorColumn: Int
  /// The overlay anchor row.
  public var anchorRow: Int
  /// A Boolean value that indicates whether selection is enabled.
  public var isEnabled: Bool {
    didSet { selectList.items = Self.items(from: suggestions, isEnabled: isEnabled) }
  }

  /// A closure called with an activated insertion.
  public var onInsert: (@MainActor @Sendable (_ insertion: PromptInsertion) -> Void)?

  /// Creates a prompt autocomplete overlay.
  /// - Complexity: O(n), where n is the number of suggestions.
  public init(
    state: PromptAutocompleteState<ID>,
    isEnabled: Bool = true,
    onInsert: (@MainActor @Sendable (_ insertion: PromptInsertion) -> Void)? = nil
  ) {
    self.suggestions = state.suggestions
    self.anchorColumn = state.anchorColumn
    self.anchorRow = state.anchorRow
    self.isEnabled = isEnabled
    self.onInsert = onInsert
    let selectedID = state.selectedIndex.flatMap { index in
      state.suggestions.indices.contains(index) ? state.suggestions[index].id : nil
    }
    self.selectList = SelectList(
      items: Self.items(from: state.suggestions, isEnabled: isEnabled),
      id: "prompt-autocomplete",
      selectedID: selectedID
    )
    selectList.onActivate = { [weak self] id in
      _ = self?.activate(id)
    }
  }

  /// The serializable state of the autocomplete overlay.
  /// - Complexity: O(n), where n is the number of suggestions.
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

  /// The text used to filter suggestions.
  public var query: String {
    get { selectList.query }
    set { selectList.setQuery(newValue) }
  }

  /// The selected suggestion, if any.
  /// - Complexity: O(n), where n is the number of suggestions.
  public var selectedSuggestion: PromptSuggestion<ID>? {
    guard let selectedID = selectList.selectedID else { return nil }
    return suggestions.first { $0.id == selectedID }
  }

  /// A Boolean value that indicates whether suggestions are presented.
  public var isPresented: Bool {
    suggestions.isEmpty == false
  }

  /// Moves selection and returns the selected identifier.
  /// - Complexity: Depends on ``SelectList/move(by:wrapping:)``.
  @discardableResult
  public func moveSelection(by offset: Int, wrapping: Bool = true) -> ID? {
    selectList.move(by: offset, wrapping: wrapping)
  }

  /// Activates the selected suggestion and returns its insertion.
  /// - Complexity: O(n), where n is the number of suggestions.
  @discardableResult
  public func activateSelection() -> PromptInsertion? {
    guard isEnabled, let selectedID = selectList.activateSelection() else { return nil }
    return suggestions.first { $0.id == selectedID }?.insertion
  }

  /// Returns whether two autocomplete overlays are the same instance.
  /// - Complexity: O(1).
  public nonisolated static func == (lhs: PromptAutocomplete, rhs: PromptAutocomplete) -> Bool {
    lhs === rhs
  }

  /// Hashes the identity of the autocomplete overlay.
  /// - Complexity: O(1).
  public nonisolated func hash(into hasher: inout Hasher) {
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

extension PromptAutocomplete: View {
  /// The anchored suggestion view graph.
  /// - Complexity: O(n), where n is the number of visible suggestions.
  public var graphBody: [NodeDescriptor] {
    guard isPresented else { return [] }
    return selectList.view()
      .offset(x: Double(anchorColumn), y: Double(anchorRow))
      .graphBody
  }
}
