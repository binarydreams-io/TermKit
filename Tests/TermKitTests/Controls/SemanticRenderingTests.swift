import Testing

@testable import TermKit

struct SemanticRenderingTests {
    @Test("Progress bar clips deterministically and exposes its value")
    @MainActor
    func progressBarClippingAndSemantics() throws {
        var surface = Surface(size: CellSize(width: 4, height: 1))
        var resources = ControlRenderResources()
        let bar = ProgressBar(value: 0.5, id: "playback", label: "Playback")

        let node = try bar.paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds, frameSize: CellSize(width: 8, height: 1)),
            resources: &resources
        )

        let text = (0..<4).map {
            resources.graphemes.value(for: surface[CellPoint(x: $0, y: 0)].graphemeID) ?? ""
        }.joined()
        #expect(text == "━━━━")
        #expect(node.role == .progressIndicator)
        #expect(node.label == "Playback")
        #expect(node.value == "50%")
        #expect(node.actions.isEmpty)
        #expect(node.frame == CellRect(x: 0, y: 0, width: 8, height: 1))
    }

    @Test("Adjustable progress bar clamps semantic changes")
    @MainActor
    func adjustableProgressBar() {
        let model = ProgressValueModel(value: 0.9)
        let bar = ProgressBar(value: model.binding, adjustmentStep: 0.2)

        #expect(bar.handleSemanticAction(.increment))
        #expect(model.value == 1)
        #expect(bar.handleSemanticAction(.decrement))
        #expect(model.value == 0.8)
        #expect(bar.handleSemanticAction(.activate) == false)
    }

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
        var surface = Surface(size: CellSize(width: 8, height: 1))
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
        var surface = Surface(size: CellSize(width: 12, height: 1))
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
        var surface = Surface(size: CellSize(width: 1, height: 1))
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
            items: [ListItem(id: "a", label: "A"), ListItem(id: "b", label: "B", isEnabled: false)],
            id: "files",
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

@MainActor
private final class ProgressValueModel {
    var value: Double

    init(value: Double) {
        self.value = value
    }

    var binding: Binding<Double> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
