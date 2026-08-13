import Testing
import TUIAnimation
import TUIControls
import TUIDesign
import TUIFoundation
import TUIRenderer
import TUITerminal

@testable import TUIRuntime

@MainActor
struct SelectListRuntimeTests {
    @Test("Runtime routes selection, pointer activation, and footer shortcuts")
    func runtimeInteraction() throws {
        let recorder = SelectListRuntimeRecorder()
        let list = SelectList(
            items: [
                SelectListItem(id: 1, title: "One", group: "Numbers"),
                SelectListItem(id: 2, title: "Two", details: "Second", group: "Numbers"),
                SelectListItem(id: 3, title: "Three", group: "More"),
            ],
            footerActions: [
                SelectListFooterAction(
                    title: "Create",
                    shortcut: KeyboardShortcut(.character("n"), modifiers: .control)
                ) { recorder.events.append("footer") }
            ],
            onActivate: { recorder.events.append("item-\($0)") }
        )
        let presenter = FramePresenter(session: FakeTerminalSession())
        let runtime = TUIRuntime(
            view: list.view(),
            presenter: presenter,
            terminalSize: CellSize(width: 20, height: 3),
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)

        try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .down))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .down))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .enter))))
        try runtime.process(.input(.key(TerminalKeyEvent(key: .text("n"), modifiers: .control))))
        _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

        #expect(list.selectedID == 3)
        #expect(recorder.events == ["item-3", "footer"])
        #expect(surfaceLines(presenter) == ["More", "Three", "Create [Ctrl+N]"])

        try runtime.process(.input(.mouse(TerminalMouseEvent(
            action: .release(.left),
            position: TerminalCellPoint(column: 2, row: 1)
        ))))
        #expect(recorder.events == ["item-3", "footer", "item-3"])
    }
}

@MainActor
private final class SelectListRuntimeRecorder {
    var events: [String] = []
}

@MainActor
private func surfaceLines(_ presenter: FramePresenter) -> [String] {
    guard let surface = presenter.frontSurface else { return [] }
    return (0..<surface.size.height).map { y in
        (0..<surface.size.width).compactMap { x -> String? in
            let cell = surface[CellPoint(x: x, y: y)]
            guard cell.isContinuation == false else { return nil }
            return presenter.resources.graphemes.value(for: cell.graphemeID)
        }.joined().trimmingCharacters(in: .whitespaces)
    }
}
