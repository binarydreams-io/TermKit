//  TUIkit - Terminal UI Kit for Swift
//  InteractionDispatcherTests.swift
//
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Interaction Dispatcher Tests")
struct InteractionDispatcherTests {
    @Test("Topmost target activates only after release on the same target")
    func topmostSameTargetClick() {
        let dispatcher = InteractionDispatcher()
        var actions: [String] = []
        dispatcher.registerClick(id: "bottom") { actions.append("bottom") }
        dispatcher.registerClick(id: "top") { actions.append("top") }
        dispatcher.activate(regions: [
            region("bottom", x: 0, width: 4),
            region("top", x: 1, width: 2),
        ])

        _ = dispatcher.dispatch(mouse(.press(.left), column: 1))
        _ = dispatcher.dispatch(mouse(.release(.left), column: 0))
        #expect(actions.isEmpty)

        _ = dispatcher.dispatch(mouse(.press(.left), column: 1))
        _ = dispatcher.dispatch(mouse(.release(.left), column: 1))
        #expect(actions == ["top"])
    }

    @Test("Scroll resolves the topmost registered callback")
    func scrollCallback() {
        let dispatcher = InteractionDispatcher()
        var directions: [MouseEvent.ScrollDirection] = []
        dispatcher.registerScroll(id: "bottom") { _ in directions.append(.up) }
        dispatcher.registerScroll(id: "top") { directions.append($0) }
        dispatcher.activate(regions: [
            region("bottom", x: 0, width: 3),
            region("top", x: 0, width: 3),
        ])

        _ = dispatcher.dispatch(mouse(.scroll(.down), column: 1))

        #expect(directions == [.down])
    }

    @Test("Render reset removes stale callbacks")
    func renderReset() {
        let dispatcher = InteractionDispatcher()
        var clickCount = 0
        dispatcher.registerClick(id: "stale") { clickCount += 1 }
        dispatcher.activate(regions: [region("stale", x: 0, width: 1)])

        dispatcher.beginRenderPass()
        dispatcher.activate(regions: [region("stale", x: 0, width: 1)])
        _ = dispatcher.dispatch(mouse(.press(.left), column: 0))
        _ = dispatcher.dispatch(mouse(.release(.left), column: 0))

        #expect(clickCount == 0)
    }

    @Test("Synthetic click keys use InputHandler guards")
    func syntheticKeyUsesInputPipeline() {
        let context = TUIContext()
        var quitCount = 0
        let inputHandler = InputHandler(
            statusBar: context.statusBar,
            keyEventDispatcher: context.keyEventDispatcher,
            interactionDispatcher: context.interactionDispatcher,
            focusManager: context.focusManager,
            paletteManager: context.paletteManager,
            appearanceManager: context.appearanceManager,
            onQuit: { quitCount += 1 }
        )
        context.statusBar.quitBehavior = .rootOnly
        context.statusBar.push(context: "modal", items: [])
        context.interactionDispatcher.registerClick(id: "quit", key: .character("q"))
        context.interactionDispatcher.activate(regions: [region("quit", x: 0, width: 1)])

        inputHandler.handle(.mouse(mouse(.press(.left), column: 0)))
        inputHandler.handle(.mouse(mouse(.release(.left), column: 0)))
        #expect(quitCount == 0)

        context.statusBar.pop(context: "modal")
        inputHandler.handle(.mouse(mouse(.press(.left), column: 0)))
        inputHandler.handle(.mouse(mouse(.release(.left), column: 0)))
        #expect(quitCount == 1)
    }

    private func region(_ id: String, x: Int, width: Int) -> InteractionRegion {
        InteractionRegion(id: id, rect: TerminalCellRect(x: x, y: 0, width: width, height: 1))
    }

    private func mouse(_ action: MouseEvent.Action, column: Int) -> MouseEvent {
        MouseEvent(action: action, column: column, row: 0)
    }
}

@MainActor
@Suite("Mouse Interaction View Tests")
struct MouseInteractionViewTests {
    @Test("Render loop activates regions from the final frame")
    func renderLoopActivatesFinalRegions() throws {
        let context = TUIContext()
        let terminal = MockTerminal()
        terminal.size = (width: 20, height: 8)
        let renderer = RenderLoop(
            app: InteractionMapApp(),
            terminal: terminal,
            statusBar: context.statusBar,
            appHeader: context.appHeader,
            focusManager: context.focusManager,
            paletteManager: context.paletteManager,
            appearanceManager: context.appearanceManager,
            tuiContext: context
        )

        renderer.render()

        let region = try #require(context.interactionDispatcher.activeRegions.last)
        #expect(region.rect.x >= 0)
        #expect(region.rect.maxX <= terminal.size.width)
        #expect(region.rect.y >= 0)
        #expect(region.rect.maxY <= terminal.size.height)
    }

    @Test("onClick registers the full rendered bounds")
    func onClickBoundsAndAction() throws {
        let context = TUIContext()
        var clickCount = 0
        context.beginRenderPass()
        let buffer = renderToBuffer(
            Text("click").onClick { clickCount += 1 },
            context: renderContext(context)
        )
        context.interactionDispatcher.activate(regions: buffer.regions)
        let clickRegion = try #require(buffer.regions.last)

        #expect(clickRegion.rect == TerminalCellRect(x: 0, y: 0, width: buffer.width, height: buffer.height))
        _ = context.interactionDispatcher.dispatch(MouseEvent(action: .press(.left), column: 0, row: 0))
        _ = context.interactionDispatcher.dispatch(MouseEvent(action: .release(.left), column: 0, row: 0))
        #expect(clickCount == 1)
    }

    @Test("Button click focuses before activation")
    func buttonFocusesBeforeActivation() throws {
        let context = TUIContext()
        var focusedAtActivation: String?
        context.beginRenderPass()
        let buffer = renderToBuffer(
            HStack {
                Button("First") {}.focusID("first")
                Button("Second") {
                    focusedAtActivation = context.focusManager.currentFocusedID
                }.focusID("second")
            },
            context: renderContext(context)
        )
        context.focusManager.endRenderPass()
        context.interactionDispatcher.activate(regions: buffer.regions)
        let secondRegion = try #require(buffer.regions.first { $0.id.contains("second") })

        click(secondRegion, dispatcher: context.interactionDispatcher)

        #expect(focusedAtActivation == "second")
    }

    @Test("Toggle click focuses before changing its binding")
    func toggleFocusesBeforeActivation() throws {
        let context = TUIContext()
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })
        context.beginRenderPass()
        let buffer = renderToBuffer(
            HStack {
                Button("First") {}.focusID("first")
                Toggle("Toggle", isOn: binding).focusID("toggle")
            },
            context: renderContext(context)
        )
        context.focusManager.endRenderPass()
        context.interactionDispatcher.activate(regions: buffer.regions)
        let toggleRegion = try #require(buffer.regions.first { $0.id.contains("toggle") })

        click(toggleRegion, dispatcher: context.interactionDispatcher)

        #expect(context.focusManager.currentFocusedID == "toggle")
        #expect(isOn)
    }

    @Test("Presented modal excludes background click registrations")
    func modalBlocksBackgroundClicks() throws {
        let context = TUIContext()
        var backgroundClicks = 0
        var modalClicks = 0
        context.beginRenderPass()
        let buffer = renderToBuffer(
            Text("base")
                .onClick { backgroundClicks += 1 }
                .modal(isPresented: .constant(true)) {
                    Text("modal").onClick { modalClicks += 1 }
                },
            context: renderContext(context)
        )
        context.interactionDispatcher.activate(regions: buffer.regions)
        let modalRegion = try #require(buffer.regions.last)

        _ = context.interactionDispatcher.dispatch(MouseEvent(action: .press(.left), column: 0, row: 0))
        _ = context.interactionDispatcher.dispatch(MouseEvent(action: .release(.left), column: 0, row: 0))
        click(modalRegion, dispatcher: context.interactionDispatcher)

        #expect(backgroundClicks == 0)
        #expect(modalClicks == 1)
    }

    private func renderContext(_ context: TUIContext) -> RenderContext {
        RenderContext(
            availableWidth: 40,
            availableHeight: 10,
            tuiContext: context,
            identity: ViewIdentity(path: "test")
        )
    }

    private func click(_ region: InteractionRegion, dispatcher: InteractionDispatcher) {
        let column = region.rect.x
        let row = region.rect.y
        _ = dispatcher.dispatch(MouseEvent(action: .press(.left), column: column, row: row))
        _ = dispatcher.dispatch(MouseEvent(action: .release(.left), column: column, row: row))
    }
}

@MainActor
private struct InteractionMapApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("click").onClick {}
        }
    }
}
