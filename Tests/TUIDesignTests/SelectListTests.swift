import TUIControls
import TUIFoundation
import TUIRenderer
import Testing

@testable import TUIDesign

@MainActor
struct SelectListTests {
    @Test("Filtering matches details, groups, and search terms")
    func filteringAndGrouping() {
        let list = SelectList(items: [
            SelectListItem(id: 1, title: "Open file", details: "Choose a document", group: "File"),
            SelectListItem(id: 2, title: "Toggle theme", group: "View", searchTerms: ["appearance"]),
            SelectListItem(id: 3, title: "Close", group: "File", isEnabled: false),
        ])

        list.setQuery("appearance")

        #expect(list.filteredItems.map(\.id) == [2])
        #expect(list.groups.map(\.title) == ["View"])
        #expect(list.selectedID == 2)
    }

    @Test("Navigation skips disabled items and computes scroll-to-selection")
    func navigationAndScroll() {
        let list = SelectList(items: [
            SelectListItem(id: 1, title: "One"),
            SelectListItem(id: 2, title: "Two", isEnabled: false),
            SelectListItem(id: 3, title: "Three"),
            SelectListItem(id: 4, title: "Four"),
        ])

        #expect(list.move(by: 1) == 3)
        #expect(list.move(by: 1) == 4)
        #expect(list.scrollOffset(viewportHeight: 2, currentOffset: 0) == 2)
    }

    @Test("Mouse selection and semantic state share the same selection model")
    func mouseAndSemantics() {
        let list = SelectList(
            id: "choices",
            items: [
                SelectListItem(id: "a", title: "Alpha"),
                SelectListItem(id: "b", title: "Beta", isCurrentValue: true),
            ]
        )
        let frames = ["a": CellRect(x: 0, y: 0, width: 10, height: 1)]

        #expect(list.handleMouse(at: CellPoint(x: 2, y: 0), rowFrames: frames) == "a")
        #expect(list.semanticNode().children.first?.state.contains(.selected) == true)
    }

    @Test("Semantic identifiers remain unique when item descriptions collide")
    func collisionSafeSemanticIDs() {
        struct ID: Hashable, Sendable, CustomStringConvertible {
            let value: Int
            var description: String { "same" }
        }
        let list = SelectList(items: [
            SelectListItem(id: ID(value: 1), title: "One"),
            SelectListItem(id: ID(value: 2), title: "Two"),
        ])

        #expect(list.semanticNode().children.map(\.id) == ["select-list-item-0", "select-list-item-1"])
    }

    @Test("View adapter owns keyboard, mouse, and footer action dispatch")
    func viewInputAdapter() {
        let recorder = CommandRecorder()
        let list = SelectList(
            items: [
                SelectListItem(id: 1, title: "One"),
                SelectListItem(id: 2, title: "Two"),
            ],
            footerActions: [
                SelectListFooterAction(title: "Create", shortcut: KeyboardShortcut(.character("n"))) {
                    recorder.values.append("footer")
                }
            ],
            onActivate: { recorder.values.append("item-\($0)") }
        )
        let view = list.view()

        #expect(view.handleControlInput(.moveDown))
        #expect(list.selectedID == 2)
        #expect(view.activate(at: CellPoint(x: 0, y: 0)))
        #expect(view.handleKeyboardShortcut(KeyboardShortcut(.character("n"))))
        #expect(recorder.values == ["item-1", "footer"])
        #expect(view.graphBody.first?.focus.isFocusable == true)
    }

    @Test("Paint renders grouped details, current marker, states, and footer")
    func groupedDetailsPaint() throws {
        let list = SelectList(
            items: [
                SelectListItem(id: 1, title: "Alpha", details: "First detail", group: "Letters"),
                SelectListItem(
                    id: 2,
                    title: "Beta",
                    details: "Current detail",
                    group: "Letters",
                    isEnabled: false,
                    isCurrentValue: true
                ),
            ],
            footerActions: [
                SelectListFooterAction(title: "Create", shortcut: KeyboardShortcut(.character("n")))
            ]
        )
        var resources = ControlRenderResources()
        var surface = TUIRenderer.Surface(size: CellSize(width: 30, height: 6))

        let semantics = try list.view().paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )

        #expect(lines(in: surface, resources: resources) == [
            "Letters", "Alpha", "First detail", "▌ Beta", "Current detail", "Create [N]",
        ])
        #expect(style(at: CellPoint(x: 2, y: 1), in: surface, resources: resources).attributes.contains(.inverse))
        #expect(style(at: CellPoint(x: 2, y: 3), in: surface, resources: resources).attributes.contains(.dim))
        #expect(semantics.children[0].state == [.selected])
        #expect(semantics.children[1].state == [.current, .disabled])
    }

    @Test("Paint scrolls an offscreen selection into a bounded grouped viewport")
    func offscreenSelectionPaint() throws {
        let list = SelectList(items: [
            SelectListItem(id: 1, title: "One", group: "First"),
            SelectListItem(id: 2, title: "Two", details: "Second detail", group: "First"),
            SelectListItem(id: 3, title: "Three", group: "Second"),
        ])
        _ = list.select(at: 2)
        var resources = ControlRenderResources()
        var surface = TUIRenderer.Surface(size: CellSize(width: 20, height: 2))

        _ = try list.view().paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )

        #expect(lines(in: surface, resources: resources) == ["Second", "Three"])
        #expect(list.scrollOffset(viewportHeight: 2, currentOffset: 100) == 4)
    }

    @Test("Mouse navigation uses painted grouped rows and executes footer actions")
    func groupedMouseAndFooterActions() throws {
        let recorder = CommandRecorder()
        let list = SelectList(
            items: [
                SelectListItem(id: 1, title: "One", details: "Detail", group: "Group"),
                SelectListItem(id: 2, title: "Disabled", isEnabled: false),
            ],
            footerActions: [SelectListFooterAction(title: "Create") { recorder.values.append("footer") }],
            onActivate: { recorder.values.append("item-\($0)") }
        )
        let view = list.view()
        var resources = ControlRenderResources()
        var surface = TUIRenderer.Surface(size: CellSize(width: 20, height: 5))
        _ = try view.paint(into: &surface, context: PaintContext(clip: surface.bounds), resources: &resources)

        #expect(view.activate(at: CellPoint(x: 1, y: 2)))
        #expect(view.activate(at: CellPoint(x: 1, y: 3)) == false)
        #expect(view.activate(at: CellPoint(x: 1, y: 4)))
        #expect(recorder.values == ["item-1", "footer"])
    }
}

private func lines(
    in surface: TUIRenderer.Surface,
    resources: ControlRenderResources
) -> [String] {
    (0..<surface.size.height).map { y in
        (0..<surface.size.width).compactMap { x -> String? in
            let cell = surface[CellPoint(x: x, y: y)]
            guard cell.isContinuation == false else { return nil }
            return resources.graphemes.value(for: cell.graphemeID)
        }.joined().trimmingCharacters(in: .whitespaces)
    }
}

private func style(
    at point: CellPoint,
    in surface: TUIRenderer.Surface,
    resources: ControlRenderResources
) -> CellStyle {
    resources.styles.value(for: surface[point].styleID) ?? .default
}

@MainActor
struct CommandPaletteTests {
    @Test("Command palette delegates filtering and dispatch to SelectList")
    func adapter() {
        let recorder = CommandRecorder()
        let palette = CommandPalette(commands: [
            PaletteCommand(id: "open", title: "Open file", keywords: ["document"]) {
                recorder.values.append("open")
            },
            PaletteCommand(id: "close", title: "Close file") {
                recorder.values.append("close")
            },
        ])

        palette.query = "document"
        let selected = palette.activateSelection()

        #expect(palette.selectList.filteredItems.map(\.id) == ["open"])
        #expect(selected == "open")
        #expect(recorder.values == ["open"])
    }
}

@MainActor
private final class CommandRecorder {
    var values: [String] = []
}
