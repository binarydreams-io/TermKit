import TUIFoundation
import TUILayout
import TUIRenderer
import Testing

@testable import TUIControls

struct SemanticRenderingTests {
    @Test("Text leaf retains its primitive and measures terminal cells")
    @MainActor
    func textLeafDescriptorAndSizing() throws {
        let text = Text("界x")
        let descriptor = try #require(text.graphBody.first)

        #expect(descriptor.primitive(as: Text.self) == text)
        #expect(descriptor.dirtyOnUpdate.contains(.layout))
        #expect(text.sizeThatFits(.unspecified) == CellSize(width: 3, height: 1))
        #expect(text.sizeThatFits(ProposedCellSize(width: 2)) == CellSize(width: 2, height: 1))
    }

    @Test("Button leaf publishes interaction metadata")
    @MainActor
    func buttonLeafDescriptor() throws {
        let button = Button("Run") {}
        let descriptor = try #require(button.graphBody.first)

        #expect(descriptor.primitive(as: Button.self) != nil)
        #expect(descriptor.focus.isFocusable)
        #expect(descriptor.hitTest.isEnabled)
        #expect(descriptor.dirtyOnUpdate.contains(.layout))
        #expect(button.sizeThatFits(.unspecified) == CellSize(width: 3, height: 1))
    }

    @Test("Text paints cells and publishes a semantic node")
    func textPaintAndSemantics() throws {
        var surface = TUIRenderer.Surface(size: CellSize(width: 8, height: 1))
        var resources = ControlRenderResources()
        let context = PaintContext(clip: surface.bounds)

        let node = try Text("Hi", id: "greeting").paint(
            into: &surface,
            context: context,
            resources: &resources
        )

        #expect(resources.graphemes.value(for: surface[.zero].graphemeID) == "H")
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 1, y: 0)].graphemeID) == "i")
        #expect(node.role == .text)
        #expect(node.label == "Hi")
        #expect(node.frame == CellRect(x: 0, y: 0, width: 2, height: 1))
    }

    @Test("Unicode clusters use foundation widths and preserve adjacent surface cells")
    func unicodeWidthAndAdjacentCells() throws {
        var surface = TUIRenderer.Surface(size: CellSize(width: 12, height: 1))
        var resources = ControlRenderResources()

        _ = try Text("❤️x👩‍💻y1️⃣z🇺🇦q").paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )

        #expect(SurfaceTextPainter.cellWidth(of: "❤️x👩‍💻y1️⃣z🇺🇦q") == 12)
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 2, y: 0)].graphemeID) == "x")
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 5, y: 0)].graphemeID) == "y")
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 8, y: 0)].graphemeID) == "z")
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 11, y: 0)].graphemeID) == "q")
    }

    @Test("A clipped wide grapheme paints a visible one-cell fallback")
    func clippedWideGraphemeFallback() throws {
        var surface = TUIRenderer.Surface(size: CellSize(width: 1, height: 1))
        var resources = ControlRenderResources()

        _ = try Text("界").paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )

        #expect(resources.graphemes.value(for: surface[.zero].graphemeID) == "�")
        #expect(surface[.zero].displayWidth == 1)
    }

    @Test("Semantic tree exposes control state and actions")
    @MainActor
    func semanticTree() {
        let list = List(
            id: "files",
            items: [ListItem(id: "a", label: "A"), ListItem(id: "b", label: "B", isEnabled: false)],
            selection: Selection(values: ["a"]),
            currentID: "a"
        )
        let tree = SemanticTree(roots: [list.semanticNode()])

        #expect(tree.nodes(withRole: .listItem).count == 2)
        #expect(tree.node(withID: "files-item-0")?.state.contains(.selected) == true)
        #expect(tree.node(withID: "files-item-1")?.actions.isEmpty == true)
    }

    @Test("List semantic identifiers do not collide when item descriptions match")
    @MainActor
    func collisionSafeListSemanticIDs() {
        struct ID: Hashable, Sendable, CustomStringConvertible {
            let value: Int
            var description: String { "same" }
        }
        let list = List(items: [
            ListItem(id: ID(value: 1), label: "One"),
            ListItem(id: ID(value: 2), label: "Two"),
        ])

        #expect(list.semanticNode().children.map(\.id) == ["list-item-0", "list-item-1"])
    }
}
