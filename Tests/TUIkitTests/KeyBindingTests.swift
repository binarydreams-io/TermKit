//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyBindingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context sized for the cheat sheet tests.
private func testContext(width: Int = 40, height: Int = 20) -> RenderContext {
  RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIkit.TUIContext())
}

// MARK: - KeyBinding Tests

@MainActor
@Suite("KeyBinding Tests")
struct KeyBindingTests {

  // The real consumer nests `.keyBinding` declarations inside a `VStack`
  // (see the phase-6 footer/cheat-sheet plan), so that's the form these
  // tests exercise. `VStack`'s two-pass layout renders each non-Layoutable
  // child twice — once to measure, once for real (`ChildInfo.measureChild`'s
  // render-to-measure fallback) — so `PreferenceModifier` must skip its
  // `setValue` side effect while `context.isMeasuring` is true, or every
  // binding would be collected twice. See `measurementPassSkipsSettingThePreference`.

  @Test("keyBinding declarations collect through preferences in tree order")
  func bindingsCollect() {
    var collected: [KeyBinding] = []
    let view = VStack {
      Text("a").keyBinding("a", "Analyze", group: "Project")
      Text("b").keyBinding("esc", "Back", group: "Project", order: 9)
    }
    .onPreferenceChange(KeyBindingsKey.self) { collected = $0 }
    _ = renderToBuffer(view, context: testContext())

    #expect(collected.map(\.label) == ["Analyze", "Back"])
    #expect(collected[0].triggerKey == .character("a"))
    #expect(collected[1].triggerKey == .escape)
  }

  @Test("Duplicate bindings with the same id are both collected")
  func duplicateBindingsBothCollected() {
    var collected: [KeyBinding] = []
    let view = VStack {
      Text("a1").keyBinding("a", "Analyze", group: "Project")
      Text("a2").keyBinding("a", "Analyze", group: "Project")
    }
    .onPreferenceChange(KeyBindingsKey.self) { collected = $0 }
    _ = renderToBuffer(view, context: testContext())

    #expect(collected.count == 2)
    #expect(collected[0].id == collected[1].id)
  }

  @Test("Collection follows tree order, not the order field")
  func collectionOrderIgnoresOrderField() {
    var collected: [KeyBinding] = []
    let view = VStack {
      Text("b").keyBinding("b", "DeclaredFirst", group: "Project", order: 10)
      Text("a").keyBinding("a", "DeclaredSecond", group: "Project", order: 0)
    }
    .onPreferenceChange(KeyBindingsKey.self) { collected = $0 }
    _ = renderToBuffer(view, context: testContext())

    // "DeclaredSecond" has the lower order value but was declared second in
    // the tree; a sort-by-order pass would put it first. It stays second,
    // because reduce only appends — sorting is the consumer's job.
    #expect(collected.map(\.label) == ["DeclaredFirst", "DeclaredSecond"])
  }

  @Test("Sibling views outside a stack also collect without a container")
  func siblingViewsWithoutAStackAlsoCollect() {
    // TupleView (a bare pair of siblings, no VStack) takes a different,
    // always-single-pass rendering path (`TupleView.childInfos` calls
    // `makeChildInfo` once per child, no separate measure pass). Keeping
    // this alongside the VStack-based tests covers both paths.
    @ViewBuilder
    func content() -> some View {
      Text("a").keyBinding("a", "Analyze", group: "Project")
      Text("b").keyBinding("esc", "Back", group: "Project")
    }

    var collected: [KeyBinding] = []
    let view = content().onPreferenceChange(KeyBindingsKey.self) { collected = $0 }
    _ = renderToBuffer(view, context: testContext())

    #expect(collected.map(\.label) == ["Analyze", "Back"])
  }

  @Test("A measurement-only render pass does not set the preference")
  func measurementPassSkipsSettingThePreference() {
    var collected: [KeyBinding] = []
    let view = Text("a").keyBinding("a", "Analyze")
      .onPreferenceChange(KeyBindingsKey.self) { collected = $0 }
    var context = testContext()
    context.isMeasuring = true
    _ = renderToBuffer(view, context: context)

    #expect(collected.isEmpty)
  }

  @Test("A single-character shortcut derives a character trigger key")
  func singleCharacterDerivesCharacterKey() {
    let binding = KeyBinding(shortcut: "A", label: "Shift A")
    #expect(binding.triggerKey == .character("A"))
  }

  @Test("Named shortcuts derive their matching keys")
  func namedShortcutsDeriveMatchingKeys() {
    #expect(KeyBinding(shortcut: "enter", label: "Confirm").triggerKey == .enter)
    #expect(KeyBinding(shortcut: "tab", label: "Next field").triggerKey == .tab)
    #expect(KeyBinding(shortcut: "space", label: "Toggle").triggerKey == .space)
  }

  @Test("A multi-character shortcut symbol has no derived trigger key")
  func multiCharacterShortcutHasNoTriggerKey() {
    let binding = KeyBinding(shortcut: "↑↓", label: "Navigate")
    #expect(binding.triggerKey == nil)
  }

  @Test("Shortcut symbols derive the same key as their word spellings")
  func shortcutSymbolsDeriveTheSameKeyAsWordSpellings() {
    // Aligned with StatusBarItem's derivation table (shared helper) so a
    // `Shortcut.*` constant — a single glyph like "↑" or "⎋" — derives its
    // named key instead of falling through to `.character`.
    #expect(KeyBinding(shortcut: Shortcut.arrowUp, label: "Up").triggerKey == .up)
    #expect(KeyBinding(shortcut: Shortcut.escape, label: "Close").triggerKey == .escape)
  }

  @Test("Cheat sheet renders group titles and every binding")
  func cheatSheetRendersGroups() {
    let sheet = KeyBindingCheatSheet(bindings: [
      KeyBinding(shortcut: "a", label: "Analyze", group: "Project"),
      KeyBinding(shortcut: "g", label: "Global scope", group: "Inventory"),
    ])
    let text = renderToBuffer(sheet, context: testContext(width: 60, height: 20))
      .lines.joined(separator: "\n").stripped
    #expect(text.contains("Project"))
    #expect(text.contains("Analyze"))
    #expect(text.contains("Inventory"))
    #expect(text.contains("g"))
  }

  @Test("Bindings without an explicit group render under a General title")
  func bindingsWithoutGroupRenderUnderGeneralTitle() {
    let sheet = KeyBindingCheatSheet(bindings: [
      KeyBinding(shortcut: "q", label: "Quit"),
    ])
    let text = renderToBuffer(sheet, context: testContext())
      .lines.joined(separator: "\n").stripped
    #expect(text.contains("General"))
    #expect(text.contains("Quit"))
  }

  @Test("Shortcuts are padded to the widest shortcut in their group")
  func shortcutsPadToGroupWidth() {
    let sheet = KeyBindingCheatSheet(bindings: [
      KeyBinding(shortcut: "a", label: "Analyze", group: "Project"),
      KeyBinding(shortcut: "esc", label: "Back", group: "Project"),
    ])
    let lines = renderToBuffer(sheet, context: testContext()).lines.map(\.stripped)

    #expect(lines.contains { $0.contains("a    Analyze") })
    #expect(lines.contains { $0.contains("esc  Back") })
  }

  @Test("An empty bindings array renders an empty cheat sheet")
  func emptyBindingsRenderEmptySheet() {
    let sheet = KeyBindingCheatSheet(bindings: [])
    let buffer = renderToBuffer(sheet, context: testContext())
    #expect(buffer.lines.isEmpty)
  }
}
