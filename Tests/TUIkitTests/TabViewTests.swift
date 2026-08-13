//  TUIKit - Terminal UI Kit for Swift
//  TabViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing
@testable import TUIkit

/// Creates a render context sized for tab bar tests.
private func testContext(width: Int = 40, height: Int = 6) -> RenderContext {
  RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIkit.TUIContext())
}

/// A palette whose bar roles are four distinct RGB colors, so a pin can tell
/// the selected accent, the dim hint, and the tertiary label apart, and any
/// background fill shows up as an `48;2;` code.
private struct TabBarTestPalette: Palette {
  let id = "tab-bar-test"
  let name = "Tab Bar Test"
  let background = Color.hex(0x101010)
  let foreground = Color.hex(0xEEEEEE)
  let foregroundSecondary = Color.hex(0xAAAAAA)
  let foregroundTertiary = Color.hex(0x707070)
  let foregroundQuaternary = Color.hex(0x404040)
  let accent = Color.hex(0xD98BE8)
  let success = Color.hex(0x9FE7C4)
  let warning = Color.hex(0xF5A742)
  let error = Color.hex(0xE06C75)
  let info = Color.hex(0x56B6C2)
  let border = Color.hex(0x353535)
  let focusBackground = Color.hex(0x211A2B)
}

@MainActor
@Suite("TabView Tests", .serialized)
struct TabViewTests {
  @Test("Tab bar renders every label and marks the selection")
  func barRendersLabels() {
    var selection = "a"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let view = TabView(selection: binding, tabs: [
      TabItem("Alpha", value: "a", badge: "3"),
      TabItem("Beta", value: "b")
    ]) { value in Text("content-\(value)") }
    let buffer = renderToBuffer(view, context: testContext(width: 40, height: 6))
    let text = buffer.lines.joined(separator: "\n").stripped
    #expect(text.contains("Alpha"))
    #expect(text.contains("Beta"))
    #expect(text.contains("3"))
    #expect(text.contains("content-a"))
    #expect(!text.contains("content-b"))
  }

  @Test("Clicking a tab region changes the selection")
  func clickChangesSelection() throws {
    var selection = "a"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let tuiContext = TUIkit.TUIContext()
    let context = RenderContext(
      availableWidth: 40,
      availableHeight: 6,
      tuiContext: tuiContext,
      identity: ViewIdentity(path: "tabview-click-test")
    )
    let view = TabView(selection: binding, tabs: [
      TabItem("Alpha", value: "a"),
      TabItem("Beta", value: "b")
    ]) { value in Text("content-\(value)") }

    tuiContext.beginRenderPass()
    let buffer = renderToBuffer(view, context: context)
    tuiContext.interactionDispatcher.activate(regions: buffer.regions)
    let tabRegions = buffer.regions.filter { $0.id.hasPrefix("tab-") }
    #expect(tabRegions.count == 2)
    let betaRegion = try #require(tabRegions.first { $0.id.hasSuffix("-1") })

    _ = tuiContext.interactionDispatcher.dispatch(
      MouseEvent(action: .press(.left), column: betaRegion.rect.x, row: betaRegion.rect.y)
    )
    _ = tuiContext.interactionDispatcher.dispatch(
      MouseEvent(action: .release(.left), column: betaRegion.rect.x, row: betaRegion.rect.y)
    )

    #expect(selection == "b")
  }

  // MARK: - Edge Cases

  @Test("A single tab fills the available width and stays clickable")
  func singleTabFillsWidth() {
    let selection = "solo"
    let binding = Binding(get: { selection }, set: { _ in })
    let view = TabView(selection: binding, tabs: [
      TabItem("Solo", value: "solo")
    ]) { value in Text("content-\(value)") }
    let buffer = renderToBuffer(view, context: testContext(width: 40, height: 6))

    #expect(buffer.lines[0].stripped.contains("Solo"))
    #expect(buffer.regions.filter { $0.id.hasPrefix("tab-") }.count == 1)
  }

  @Test("More tabs than the available width stay inside the terminal width")
  func moreTabsThanWidthClampsToTheTerminal() {
    let selection = "A"
    let binding = Binding(get: { selection }, set: { _ in })
    let tabs = ["A", "B", "C", "D", "E"].map { TabItem($0, value: $0) }
    // A one-column content keeps the buffer on the bar's own width, so the
    // first line measures the bar and not the widest child of the stack.
    let view = TabView(selection: binding, tabs: tabs) { _ in Text("·") }
    let buffer = renderToBuffer(view, context: testContext(width: 3, height: 6))

    #expect(buffer.lines.count >= 1)
    #expect(buffer.lines[0].strippedLength == 3)
    let regions = buffer.regions.filter { $0.id.hasPrefix("tab-") }
    #expect(regions.count == 1)
    #expect(regions.allSatisfy { $0.rect.x >= 0 && $0.rect.maxX <= 3 })
  }

  @Test("A clamped tab bar keeps the selected tab and its click region")
  func clampedBarKeepsTheSelectedTab() throws {
    var selection = "E"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let tuiContext = TUIkit.TUIContext()
    let context = RenderContext(
      availableWidth: 4,
      availableHeight: 6,
      tuiContext: tuiContext,
      identity: ViewIdentity(path: "tabview-clamp-test")
    )
    let tabs = ["A", "B", "C", "D", "E"].map { TabItem($0, value: $0) }
    let view = TabView(selection: binding, tabs: tabs) { value in Text("content-\(value)") }

    tuiContext.beginRenderPass()
    let buffer = renderToBuffer(view, context: context)

    #expect(buffer.lines[0].stripped.contains("E"))
    #expect(!buffer.lines[0].stripped.contains("A"))
    let regions = buffer.regions.filter { $0.id.hasPrefix("tab-") }
    #expect(regions.count == 1)
    // The region keeps the tab's own index, so a click still selects its value.
    let region = try #require(regions.first)
    #expect(region.id.hasSuffix("-4"))
  }

  @Test("A label longer than its tab keeps the trailing ANSI reset instead of bleeding color")
  func longLabelTruncatesWithoutBleedingColor() {
    let selection = "a"
    let binding = Binding(get: { selection }, set: { _ in })
    let view = TabView(selection: binding, tabs: [
      TabItem("VeryLongLabelText", value: "a"),
      TabItem("B", value: "b")
    ]) { value in Text("content-\(value)") }
    let buffer = renderToBuffer(view, context: testContext(width: 10, height: 6))

    #expect(buffer.lines[0].strippedLength == 10)
    #expect(!buffer.lines[0].stripped.contains("VeryLongLabelText"))
    #expect(buffer.lines[0].contains(ANSIRenderer.reset))
  }

  // MARK: - Plain Bar Style

  @Test("The filled bar stays the default and keeps its fill")
  func filledBarKeepsItsFill() {
    let buffer = renderBar(selection: "a", width: 40)

    #expect(buffer.lines[0].contains("48;2;"))
  }

  @Test("The plain bar marks the selection with the rail and paints no fill")
  func plainBarMarksTheSelectionWithoutFill() {
    let palette = TabBarTestPalette()
    let buffer = renderPlainBar(selection: "a", width: 40)
    let bar = buffer.lines[0]

    #expect(bar.stripped.contains("\u{258E} ALPHA"))
    #expect(bar.stripped.contains("2 BETA"))
    #expect(!bar.stripped.contains("1 ALPHA"))
    #expect(
      bar.contains(
        ANSIRenderer.colorize("\u{258E} ALPHA", foreground: palette.accent, bold: true)
      )
    )
    #expect(!bar.contains("48;2;"))
  }

  @Test("The plain bar dims the key hint and keeps the label tertiary")
  func plainBarDimsTheKeyHint() {
    let palette = TabBarTestPalette()
    let bar = renderPlainBar(selection: "a", width: 40).lines[0]

    #expect(bar.contains(ANSIRenderer.colorize("2", foreground: palette.foregroundQuaternary)))
    #expect(bar.contains(ANSIRenderer.colorize("BETA", foreground: palette.foregroundTertiary)))
    #expect(!bar.contains(ANSIRenderer.colorize("2", foreground: palette.foregroundTertiary)))
  }

  @Test("A plain tab keeps its natural width and its click region")
  func plainTabKeepsItsClickRegion() throws {
    var selection = "a"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let tuiContext = TUIkit.TUIContext()
    let context = RenderContext(
      availableWidth: 40,
      availableHeight: 6,
      tuiContext: tuiContext,
      identity: ViewIdentity(path: "tabview-plain-click-test")
    )

    tuiContext.beginRenderPass()
    let view = plainTabView(selection: binding).tabBarStyle(.plain)
    let buffer = renderToBuffer(view, context: context)
    tuiContext.interactionDispatcher.activate(regions: buffer.regions)
    let regions = buffer.regions.filter { $0.id.hasPrefix("tab-") }
    #expect(regions.count == 2)
    let beta = try #require(regions.first { $0.id.hasSuffix("-1") })
    // The selected cell spends "▎ ALPHA" plus the four-column gap, so the
    // second cell starts where the first one ends and not at half the width.
    #expect(beta.rect.x == 11)

    _ = tuiContext.interactionDispatcher.dispatch(
      MouseEvent(action: .press(.left), column: beta.rect.x, row: beta.rect.y)
    )
    _ = tuiContext.interactionDispatcher.dispatch(
      MouseEvent(action: .release(.left), column: beta.rect.x, row: beta.rect.y)
    )

    #expect(selection == "b")
  }

  @Test("A plain bar narrower than its tabs keeps the selected tab inside the width")
  func plainBarClampsToTheTerminal() {
    let buffer = renderPlainBar(selection: "b", width: 8)
    let bar = buffer.lines[0]

    #expect(bar.strippedLength == 8)
    #expect(bar.stripped.contains("\u{258E} BETA"))
    #expect(!bar.stripped.contains("ALPHA"))
    let regions = buffer.regions.filter { $0.id.hasPrefix("tab-") }
    #expect(regions.count == 1)
    #expect(regions.allSatisfy { $0.rect.x >= 0 && $0.rect.maxX <= 8 })
  }

  // MARK: - Plain Bar Helpers

  /// A two-tab view whose tabs carry the digit keys that select them.
  private func plainTabView(selection: Binding<String>) -> some View {
    TabView(selection: selection, tabs: [
      TabItem("ALPHA", value: "a", hint: "1"),
      TabItem("BETA", value: "b", hint: "2")
    ]) { value in Text("·\(value)") }
  }

  /// Renders the two-tab bar in the default style over the test palette.
  ///
  /// - Parameters:
  ///   - selection: The value the bar shows as selected.
  ///   - width: The columns the bar may spend.
  /// - Returns: The rendered buffer, whose first line is the bar.
  private func renderBar(selection: String, width: Int) -> FrameBuffer {
    let binding = Binding(get: { selection }, set: { _ in })
    let view = plainTabView(selection: binding).palette(TabBarTestPalette())
    return renderToBuffer(view, context: testContext(width: width, height: 6))
  }

  /// Renders the two-tab bar in the plain style over the test palette.
  ///
  /// - Parameters:
  ///   - selection: The value the bar shows as selected.
  ///   - width: The columns the bar may spend.
  /// - Returns: The rendered buffer, whose first line is the bar.
  private func renderPlainBar(selection: String, width: Int) -> FrameBuffer {
    let binding = Binding(get: { selection }, set: { _ in })
    let view = plainTabView(selection: binding)
      .palette(TabBarTestPalette())
      .tabBarStyle(.plain)
    return renderToBuffer(view, context: testContext(width: width, height: 6))
  }
}
