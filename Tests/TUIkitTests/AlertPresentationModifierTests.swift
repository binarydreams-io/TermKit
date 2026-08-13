//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AlertPresentationModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT  dimming, centering, and alert rendering.
//

import Testing
@testable import TUIkit

@MainActor
@Suite("AlertPresentationModifier Tests")
struct AlertPresentationModifierTests {
  /// Helper to create a RenderContext with default test settings.
  private func testContext() -> RenderContext {
    RenderContext(
      availableWidth: 80,
      availableHeight: 24,
      tuiContext: TUIContext()
    )
  }

  /// Helper to render a view to a FrameBuffer.
  private func render(_ view: some View) -> FrameBuffer {
    renderToBuffer(view, context: testContext())
  }

  @Test("Alert not presented shows only base content")
  func notPresentedShowsBase() {
    let isPresented = Binding.constant(false)
    let view = Text("Base Content")
      .alert("Title", isPresented: isPresented, actions: { EmptyView() }, message: { Text("Message") })

    let buffer = render(view)
    let content = buffer.lines.joined(separator: "\n").stripped

    #expect(content.contains("Base Content"))
    #expect(!content.contains("Title"))
    #expect(!content.contains("Message"))
  }

  @Test("Alert presented shows dimmed base with alert overlay")
  func presentedShowsAlert() {
    let isPresented = Binding.constant(true)
    let view = VStack {
      Text("Base Content")
      Text("More base text")
    }
    .alert("Alert Title", isPresented: isPresented, actions: { EmptyView() }, message: { Text("Alert Message") })

    let buffer = render(view)

    // Alert content should be present
    let stripped = buffer.lines.joined(separator: "\n").stripped
    #expect(stripped.contains("Alert Title"))
    #expect(stripped.contains("Alert Message"))

    // At least some content should have dim codes (from dimmed base)
    // The dimmed modifier wraps content, so check for dim in raw output
    let rawContent = buffer.lines.joined(separator: "\n")
    #expect(rawContent.contains("\u{1B}[")) // Contains ANSI codes
  }

  @Test("Alert with actions renders action buttons")
  func alertWithActions() {
    let isPresented = Binding.constant(true)
    let view = Text("Base")
      .alert("Warning", isPresented: isPresented, actions: {
        Button("Yes") {}
        Button("No") {}
      }, message: { Text("Are you sure?") })

    let buffer = render(view)
    let content = buffer.lines.joined(separator: "\n").stripped

    #expect(content.contains("Warning"))
    #expect(content.contains("Are you sure?"))
    #expect(content.contains("Yes"))
    #expect(content.contains("No"))
  }

  @Test("Alert actions preserve distinct clickable regions")
  func alertActionsAreClickable() {
    let tuiContext = TUIContext()
    var actions: [String] = []
    tuiContext.beginRenderPass()
    let context = RenderContext(
      availableWidth: 80,
      availableHeight: 24,
      tuiContext: tuiContext,
      identity: ViewIdentity(path: "alert")
    )
    let view = Text("Base")
      .alert("Warning", isPresented: .constant(true), actions: {
        Button("Yes") { actions.append("yes") }
        Button("No") { actions.append("no") }
      }, message: { Text("Continue?") })

    let buffer = renderToBuffer(view, context: context)
    let regions = buffer.regions.sorted { $0.rect.x < $1.rect.x }

    #expect(regions.count == 2)
    #expect(Set(regions.map(\.id)).count == 2)
    tuiContext.interactionDispatcher.activate(regions: regions)
    for region in regions {
      _ = tuiContext.interactionDispatcher.dispatch(
        MouseEvent(action: .press(.left), column: region.rect.x, row: region.rect.y)
      )
      _ = tuiContext.interactionDispatcher.dispatch(
        MouseEvent(action: .release(.left), column: region.rect.x, row: region.rect.y)
      )
    }
    #expect(Set(actions) == ["yes", "no"])
  }

  @Test("Alert without message renders title and actions only")
  func alertWithoutMessage() {
    let isPresented = Binding.constant(true)
    let view = Text("Base")
      .alert("Just Title", isPresented: isPresented, actions: {
        Button("OK") {}
      })

    let buffer = render(view)
    let content = buffer.lines.joined(separator: "\n").stripped

    #expect(content.contains("Just Title"))
    #expect(content.contains("OK"))
  }

  @Test("Alert respects custom colors")
  func customColors() {
    let isPresented = Binding.constant(true)
    let view = Text("Base")
      .alert(
        "Custom",
        isPresented: isPresented,
        actions: { EmptyView() },
        message: { Text("Message") },
        borderColor: .red,
        titleColor: .yellow
      )

    let buffer = render(view)
    let content = buffer.lines.joined(separator: "\n")

    // Should contain ANSI color codes (non-empty buffer with styling)
    #expect(!buffer.isEmpty)
    #expect(content.contains("\u{1B}["))
  }

  @Test("Toggle isPresented switches between states")
  func togglePresentation() {
    @State var showAlert = false

    let view1 = Text("Content")
      .alert("Alert", isPresented: $showAlert, actions: { EmptyView() }, message: { Text("Test") })

    let buffer1 = render(view1)
    let content1 = buffer1.lines.joined(separator: "\n").stripped

    // Initially not shown
    #expect(!content1.contains("Alert"))

    // Toggle to show
    showAlert = true
    let view2 = Text("Content")
      .alert("Alert", isPresented: $showAlert, actions: { EmptyView() }, message: { Text("Test") })

    let buffer2 = render(view2)
    let content2 = buffer2.lines.joined(separator: "\n").stripped

    // Now shown
    #expect(content2.contains("Alert"))
  }
}
