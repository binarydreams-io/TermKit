@testable import TermKit
import Testing

@MainActor
struct OverlayHitTestRuntimeTests {
  @Test
  func `A non-modal overlay occludes the content it covers`() throws {
    let recorder = OverlayHitTestRecorder()
    let list = makeList(recorder: recorder)
    let host = ViewOverlayHost()
    // The custom overlay centers: a 4 by 1 content on a 20 by 3 terminal
    // covers the cells 8 to 11 on row 1.
    host.present(OverlayPresentation(id: "cover", content: AnyView(Text("OVER"))))
    let runtime = Runtime(
      view: list.view(),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 20, height: 3),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    // A click on a covered cell reaches nothing beneath the overlay.
    try runtime.process(.input(mouse(.release(.left), x: 9, y: 1)))
    #expect(recorder.events.isEmpty)

    // A click outside the overlay still activates the row under it.
    try runtime.process(.input(mouse(.release(.left), x: 2, y: 2)))
    #expect(recorder.events == ["item-2"])
  }

  @Test
  func `A modal overlay blocks clicks outside its own bounds`() throws {
    let recorder = OverlayHitTestRecorder()
    let list = makeList(recorder: recorder)
    let host = ViewOverlayHost()
    host.present(OverlayPresentation(id: "modal", content: AnyView(Text("MODAL")), isModal: true))
    let runtime = Runtime(
      view: list.view(),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 20, height: 3),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(.input(mouse(.release(.left), x: 2, y: 2)))
    #expect(recorder.events.isEmpty)

    host.dismiss("modal")
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    try runtime.process(.input(mouse(.release(.left), x: 2, y: 2)))
    #expect(recorder.events == ["item-2"])
  }

  private func makeList(recorder: OverlayHitTestRecorder) -> SelectList<Int> {
    SelectList(
      items: [
        SelectListItem(id: 1, title: "One", group: "Numbers"),
        SelectListItem(id: 2, title: "Two", group: "Numbers")
      ],
      onActivate: { recorder.events.append("item-\($0)") }
    )
  }

  private func mouse(_ action: TerminalMouseAction, x: Int, y: Int) -> TerminalInputEvent {
    .mouse(
      TerminalMouseEvent(
        action: action,
        position: TerminalCellPoint(column: x, row: y)
      )
    )
  }
}

@MainActor
private final class OverlayHitTestRecorder {
  var events: [String] = []
}
