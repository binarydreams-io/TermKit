@testable import TermKit
import Testing

struct PromptTests {
  @Test(
    arguments: [
      (terminalWidth: 60, expectedWidth: 60),
      (terminalWidth: 100, expectedWidth: 75),
      (terminalWidth: 200, expectedWidth: 140)
    ]
  )
  func `Prompt layout follows the specified width policy`(argument: (terminalWidth: Int, expectedWidth: Int)) {
    let policy = AgentPromptLayoutPolicy()

    #expect(policy.horizontalPadding == 2)
    #expect(policy.topPadding == 1)
    #expect(policy.railWidth == 1)
    #expect(policy.resolvedWidth(forTerminalWidth: argument.terminalWidth) == argument.expectedWidth)
  }

  @Test
  @MainActor
  func `Prompt metadata transition becomes static when animation is disabled`() {
    let animated = AgentPromptConfiguration(animationsEnabled: true)
    let reducedMotion = AgentPromptConfiguration(animationsEnabled: false)

    #expect(animated.metadataTransitionDuration == .milliseconds(150))
    #expect(reducedMotion.metadataTransitionDuration == .zero)

    var track = animated.metadataOpacityTrack(at: .zero)
    #expect(track.status == .running)
    let midpoint = track.sample(at: .zero.advanced(by: .milliseconds(75)))
    #expect(midpoint > 0)
    #expect(midpoint < 1)
    #expect(reducedMotion.metadataOpacityTrack(at: .zero).status == .completed)
  }

  @MainActor
  @Test
  func `Prompt rejects large paste while preserving ordinary paste`() {
    let recorder = PromptActionRecorder()
    var prompt = AgentPrompt<String>(
      document: PromptDocument(),
      configuration: AgentPromptConfiguration(
        pastePolicy: AgentPromptPastePolicy(largePasteThreshold: 4, largePasteBehavior: .reject)
      ),
      actions: recorder.actions
    )

    let acceptedOrdinaryPaste = prompt.paste("text")
    #expect(acceptedOrdinaryPaste)
    #expect(prompt.currentDocument.text == "text")
    let acceptedLargePaste = prompt.paste("12345")
    #expect(acceptedLargePaste == false)
    #expect(prompt.currentDocument.text == "text")
    #expect(recorder.pasted == "text")
    #expect(recorder.diagnostics == [.pasteRejected(characterCount: 5, limit: 4)])
  }

  @MainActor
  @Test
  func `Prompt edits character offsets and multiline selections`() {
    let model = PromptModel(
      document: PromptDocument(
        text: "A🦊\nBC",
        selection: PromptSelection(anchor: 1, head: 5)
      )
    )
    var prompt = AgentPrompt<String>(model.binding, actions: PromptActionRecorder().actions)

    prompt.moveCaret(by: -1, extendingSelection: true)
    #expect(model.document.selection == PromptSelection(anchor: 1, head: 4))
    prompt.deleteBackward()
    #expect(model.document == PromptDocument(text: "AC", selection: PromptSelection(caret: 1)))
    prompt.moveCaret(by: 1)
    prompt.moveCaret(by: -1, extendingSelection: true)
    #expect(model.document.selection == PromptSelection(anchor: 2, head: 1))
  }

  @Test
  func `Prompt insertion replaces character offsets and places the cursor`() {
    var document = PromptDocument(text: "Ask 🦊 now", selection: PromptSelection(caret: 5))

    document.apply(PromptInsertion(replacementRange: 4 ..< 5, text: "TUI", cursorOffset: 2))

    #expect(document.text == "Ask TUI now")
    #expect(document.selection == PromptSelection(caret: 6))
  }

  @MainActor
  @Test
  func `Autocomplete delegates filtering and navigation to SelectList`() throws {
    let suggestions = [
      PromptSuggestion(
        id: "build",
        kind: .command,
        title: "Build",
        insertion: PromptInsertion(replacementRange: 0 ..< 2, text: "/build "),
        detail: "Compile the package"
      ),
      PromptSuggestion(
        id: "test",
        kind: .command,
        title: "Test",
        insertion: PromptInsertion(replacementRange: 0 ..< 2, text: "/test ")
      )
    ]
    let autocomplete = PromptAutocomplete(
      state: PromptAutocompleteState(suggestions: suggestions, anchorColumn: 4, anchorRow: 2)
    )

    autocomplete.query = "compile"
    let output = try autocomplete.render(in: AgentRenderContext(width: 40, scheme: .dark))

    #expect(autocomplete.selectList.filteredItems.map(\.id) == ["build"])
    #expect(autocomplete.selectList.selectedID == "build")
    #expect(output.plainText.contains("Build"))
    #expect(output.plainText.contains("Test") == false)
    #expect(output.semantics.children.map(\.id) == ["prompt-autocomplete-item-0"])

    autocomplete.query = ""
    #expect(autocomplete.moveSelection(by: 1) == "test")
    #expect(autocomplete.selectList.selectedID == "test")
  }

  @MainActor
  @Test
  func `Autocomplete activation returns typed insertion without mutating the prompt`() throws {
    final class Recorder {
      var insertions: [PromptInsertion] = []
    }
    let recorder = Recorder()
    var document = PromptDocument(text: "/te")
    let insertion = PromptInsertion(replacementRange: 0 ..< 3, text: "/test ", cursorOffset: 5)
    let autocomplete = PromptAutocomplete(
      state: PromptAutocompleteState(suggestions: [
        PromptSuggestion(id: "test", kind: .command, title: "Test", insertion: insertion)
      ])
    ) { recorder.insertions.append($0) }

    let returned = autocomplete.activateSelection()

    #expect(returned == insertion)
    #expect(recorder.insertions == [insertion])
    #expect(document == PromptDocument(text: "/te"))

    try document.apply(#require(returned))
    #expect(document == PromptDocument(text: "/test ", selection: PromptSelection(caret: 5)))
  }

  @MainActor
  @Test
  func `Autocomplete retains its overlay anchor`() {
    let autocomplete = PromptAutocomplete<String>(
      state: PromptAutocompleteState(
        anchorColumn: 14,
        anchorRow: 6
      )
    )

    #expect(autocomplete.anchorColumn == 14)
    #expect(autocomplete.anchorRow == 6)
    #expect(autocomplete.state.anchorColumn == 14)
    #expect(autocomplete.state.anchorRow == 6)
  }

  @MainActor
  @Test
  func `Prompt actions emit values without owning execution`() {
    final class Recorder {
      var submitted: PromptDocument?
      var pasted = ""
      var attachment = ""
      var didCancel = false
    }

    let recorder = Recorder()
    let actions = AgentPromptActions<String>(
      submit: { recorder.submitted = $0 },
      cancel: { recorder.didCancel = true },
      paste: { recorder.pasted = $0 },
      attach: { recorder.attachment = $0 }
    )
    let document = PromptDocument(text: "Inspect the diff")

    actions.submit(document)
    actions.paste("pasted")
    actions.attach("notes.txt")
    actions.cancel()

    #expect(recorder.submitted == document)
    #expect(recorder.pasted == "pasted")
    #expect(recorder.attachment == "notes.txt")
    #expect(recorder.didCancel)
  }

  @MainActor
  @Test
  func `Bound prompt reads, mutates, and submits the current document`() throws {
    let model = PromptModel(document: PromptDocument(text: "Initial"))
    let recorder = PromptActionRecorder()
    var prompt = AgentPrompt<String>(
      model.binding,
      actions: recorder.actions
    )
    let graph = ViewGraph()
    try graph.commit(graph.prepare(prompt))

    model.document = PromptDocument(text: "External")
    try graph.commit(graph.prepare(prompt))
    let renderLeaf = try #require(graph.root?.children.first?.children.first?.children.first)
    let renderedPrompt = try #require(renderLeaf.primitive(as: AgentPromptRenderLeaf<String>.self)).prompt

    #expect(try renderedPrompt.render(in: AgentRenderContext(width: 80, scheme: .dark)).plainText.contains("External"))

    prompt.replaceDocument(with: PromptDocument(text: "Replace"))
    prompt.insert(PromptInsertion(replacementRange: 7 ..< 7, text: " me"))
    prompt.paste("!")
    prompt.insertAutocomplete(PromptInsertion(replacementRange: 0 ..< 7, text: "Complete"))
    prompt.submit()

    #expect(model.document.text == "Complete me!")
    #expect(recorder.pasted == "!")
    #expect(recorder.submitted == model.document)
  }

  @MainActor
  @Test
  func `Prompt retains accessory state and leaf identities across updates`() throws {
    let model = PromptModel(document: PromptDocument(text: "First"))
    let probe = AccessoryProbe()
    let graph = ViewGraph()
    let actions = PromptActionRecorder().actions
    let firstPrompt = AgentPrompt<String>(
      model.binding,
      configuration: AgentPromptConfiguration(metadata: AgentPromptMetadata(model: "one")),
      actions: actions,
      leadingAccessory: { StatefulAccessory(probe: probe) },
      trailingAccessory: { AccessoryLeaf(name: "trailing") }
    )
    try graph.commit(graph.prepare(firstPrompt))
    let layout = try #require(graph.root?.children.first)
    let firstChildren = layout.children
    let primitive = try #require(layout.primitive(as: LayoutPrimitive.self))
    #expect(firstChildren.count == 3)
    if case let .stack(stack) = primitive {
      #expect(stack.axis == .horizontal)
    } else {
      Issue.record("AgentPrompt must use retained horizontal layout")
    }
    #expect(firstChildren[0].children.first?.value(as: Int.self) == 0)
    let firstPromptChildren = firstChildren[1].children
    #expect(firstPromptChildren[0].primitive(as: AgentPromptRenderLeaf<String>.self) != nil)
    #expect(firstChildren[2].children.first?.value(as: String.self) == "trailing")
    #expect(firstPromptChildren[0].isFocusable)

    probe.binding?.wrappedValue = 7
    model.document = PromptDocument(text: "Second")
    let updatedPrompt = AgentPrompt<String>(
      model.binding,
      configuration: AgentPromptConfiguration(
        isEnabled: false,
        metadata: AgentPromptMetadata(model: "one")
      ),
      actions: actions,
      leadingAccessory: { StatefulAccessory(probe: probe) },
      trailingAccessory: { AccessoryLeaf(name: "trailing") }
    )
    try graph.commit(graph.prepare(updatedPrompt))
    let updatedChildren = try #require(graph.root?.children.first?.children)

    #expect(updatedChildren.map(\.id) == firstChildren.map(\.id))
    #expect(updatedChildren[0].children.first?.value(as: Int.self) == 7)
    let updatedPromptChildren = updatedChildren[1].children
    #expect(updatedPromptChildren[0].id == firstPromptChildren[0].id)
    #expect(updatedPromptChildren[0].isFocusable == false)
    #expect(graph.focusableNodes().contains { $0.id == firstPromptChildren[0].id } == false)

    let changedMetadataPrompt = AgentPrompt<String>(
      model.binding,
      configuration: AgentPromptConfiguration(
        isEnabled: false,
        metadata: AgentPromptMetadata(model: "two")
      ),
      actions: actions,
      leadingAccessory: { StatefulAccessory(probe: probe) },
      trailingAccessory: { AccessoryLeaf(name: "trailing") }
    )
    try graph.commit(graph.prepare(changedMetadataPrompt))
    let changedChildren = try #require(graph.root?.children.first?.children)
    #expect(changedChildren[0].id == firstChildren[0].id)
    #expect(changedChildren[1].children[0].id == firstPromptChildren[0].id)
    #expect(changedChildren[2].id == firstChildren[2].id)
  }

  @MainActor
  @Test
  func `Bound prompt supports empty accessories`() {
    let model = PromptModel(document: PromptDocument())
    let prompt = AgentPrompt<String>(model.binding, actions: PromptActionRecorder().actions)

    #expect(prompt.graphBody.first?.children.count == 1)
    #expect(prompt.graphBody.first?.children.first?.children.count == 1)
  }
}

@MainActor
private final class PromptModel {
  var document: PromptDocument

  init(document: PromptDocument) {
    self.document = document
  }

  var binding: Binding<PromptDocument> {
    Binding(get: { self.document }, set: { self.document = $0 })
  }
}

@MainActor
private final class PromptActionRecorder {
  var submitted: PromptDocument?
  var pasted = ""
  var diagnostics: [AgentPromptDiagnostic] = []

  var actions: AgentPromptActions<String> {
    AgentPromptActions(
      submit: { self.submitted = $0 },
      cancel: {},
      paste: { self.pasted = $0 },
      attach: { _ in },
      diagnostic: { self.diagnostics.append($0) }
    )
  }
}

@MainActor
private final class AccessoryProbe {
  var binding: Binding<Int>?
}

@MainActor
private struct StatefulAccessory: View {
  @State private var count = 0
  let probe: AccessoryProbe

  var graphBody: [NodeDescriptor] {
    probe.binding = $count
    NodeDescriptor(type: AccessoryValueLeaf.self, value: count)
  }
}

@MainActor
private struct AccessoryLeaf: View {
  let name: String

  var graphBody: [NodeDescriptor] {
    NodeDescriptor(type: AccessoryValueLeaf.self, value: name)
  }
}

private enum AccessoryValueLeaf {}
