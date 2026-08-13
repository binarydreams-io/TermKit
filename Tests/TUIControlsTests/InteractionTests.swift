import TUIFoundation
import Testing

@testable import TUIControls

@MainActor
struct InteractionTests {
    @Test("List keyboard and mouse selection ignore disabled rows")
    func listSelection() {
        let list = List(items: [
            ListItem(id: 1, label: "One"),
            ListItem(id: 2, label: "Two", isEnabled: false),
            ListItem(id: 3, label: "Three"),
        ])

        #expect(list.move(by: 1) == 3)
        #expect(list.selectCurrent() == 3)
        #expect(list.handleMouse(
            at: CellPoint(x: 1, y: 1),
            rowFrames: [2: CellRect(x: 0, y: 1, width: 5, height: 1)]
        ) == nil)
        #expect(list.selection.contains(3))
    }

    @Test("Topmost accepting mouse region handles the event")
    func hitRegionZOrder() {
        let recorder = InteractionRecorder()
        let frame = CellRect(x: 0, y: 0, width: 5, height: 2)
        let dispatcher = MouseDispatcher(regions: [
            MouseHitRegion(id: "back", frame: frame, zIndex: 0) { _ in
                recorder.values.append("back")
                return true
            },
            MouseHitRegion(id: "front", frame: frame, zIndex: 2) { _ in
                recorder.values.append("front")
                return true
            },
        ])

        let handled = dispatcher.dispatch(MouseEvent(location: .zero, action: .click(.primary)))

        #expect(handled == "front")
        #expect(recorder.values == ["front"])
    }

    @Test("Command dispatch uses the last enabled matching command")
    func commandDispatch() {
        let recorder = InteractionRecorder()
        let shortcut = KeyboardShortcut(.character("k"), modifiers: .control)
        let commands = KeyboardCommandSet([
            KeyboardCommand(id: "disabled", title: "Disabled", shortcut: shortcut, isEnabled: false) {
                recorder.values.append("disabled")
            },
            KeyboardCommand(id: "open", title: "Open", shortcut: shortcut) {
                recorder.values.append("open")
            },
        ])

        #expect(commands.dispatch(shortcut) == "open")
        #expect(recorder.values == ["open"])
    }
}

@MainActor
private final class InteractionRecorder {
    var values: [String] = []
}
