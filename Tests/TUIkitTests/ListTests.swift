//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

@MainActor
private func createTestContext(width: Int = 80, height: Int = 24) -> RenderContext {
    let focusManager = FocusManager()
    var environment = EnvironmentValues()
    environment.focusManager = focusManager

    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    )
}

// MARK: - List Rendering Tests

@MainActor
@Suite("List Rendering Tests")
struct ListRenderingTests {

    @Test("Empty list shows placeholder")
    func emptyListPlaceholder() {
        let context = createTestContext()

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("No items"))
    }

    @Test("Custom empty placeholder is shown")
    func customEmptyPlaceholder() {
        let context = createTestContext()

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }
        .listEmptyPlaceholder("Nothing here")

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("Nothing here"))
    }

    @Test("List renders ForEach items")
    func listRendersForEachItems() {
        let context = createTestContext()

        struct Item: Identifiable {
            let id: String
            let name: String
        }
        let items = [
            Item(id: "1", name: "First"),
            Item(id: "2", name: "Second"),
            Item(id: "3", name: "Third"),
        ]

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("First"))
        #expect(content.contains("Second"))
        #expect(content.contains("Third"))
    }

    @Test("A plain list draws no frame and starts its rows at column 0")
    func plainListDrawsNoFrame() {
        let context = createTestContext(width: 40, height: 10)

        struct Item: Identifiable {
            let id: String
            let name: String
        }
        let items = [Item(id: "1", name: "First"), Item(id: "2", name: "Second")]

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }
        .listStyle(PlainListStyle())

        let buffer = renderToBuffer(list, context: context)
        let lines = buffer.lines.map(\.stripped)

        // `renderContainer` reads a nil border style as "use the appearance
        // default", so a plain list used to open with a `╭───` row and carry
        // a `│` down its leading edge, which pushed every row one column
        // right of the column header a caller drew above it.
        for glyph in "┌┐└┘├┤┬┴┼─│╭╮╰╯╔╗╚╝╠╣╦╩╬═║" {
            #expect(!lines.joined().contains(glyph))
        }
        // The first rendered row is a row, not a frame, and the only column
        // before its text is the row's own leading pad.
        #expect(lines.first?.hasPrefix(" First") == true)
        #expect(lines.dropFirst().first?.hasPrefix(" Second") == true)
    }

    @Test("Selected item has accent indicator")
    func selectedItemIndicator() {
        let context = createTestContext()

        struct Item: Identifiable {
            let id: String
            let name: String
        }
        let items = [
            Item(id: "1", name: "First"),
            Item(id: "2", name: "Second"),
        ]

        var selection: String? = "2"
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        // Selected item should have a background color (ANSI 48;2 = RGB background)
        #expect(content.contains("[48;2;"))
    }

    @Test("Scroll indicators appear when needed")
    func scrollIndicatorsAppear() {
        struct Item: Identifiable {
            let id: Int
            let name: String
        }
        // Create list with more items than will fit in available height
        let items = (0..<20).map { Item(id: $0, name: "Item \($0)") }

        var selection: Int?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }

        // Use a small height context so scrolling is triggered
        let context = createTestContext(width: 40, height: 8)
        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        // Should have "more below" indicator since we have 20 items in height 8
        #expect(content.contains("▼") || content.contains("more below"))
    }

    @Test("Disabled list modifier works")
    func disabledListModifier() {
        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }.disabled()

        #expect(list.isDisabled == true)
    }

    @Test("Multi-selection list can be created")
    func multiSelectionListCreation() {
        var selection: Set<String> = []
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            Text("Item")
        }

        #expect(list.selectionMode == .multi)
    }

    @Test("Single-selection list can be created")
    func singleSelectionListCreation() {
        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            Text("Item")
        }

        #expect(list.selectionMode == .single)
    }

    @Test("List respects frame width constraint")
    func listRespectsFrameWidth() {
        let context = createTestContext(width: 80)

        var selection: String?
        let list = List(
            "Items",
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { item in
                Text(item)
            }
        }
        .frame(width: 20)

        let buffer = renderToBuffer(list, context: context)

        // The list should be constrained to 20 characters width
        #expect(buffer.width == 20, "Expected width 20, got \(buffer.width)")

        // The border should also be 20 characters wide (not just padded)
        let firstLine = buffer.lines.first ?? ""
        #expect(firstLine.strippedLength == 20, "Border should be 20 chars wide")
    }

    @Test("Two Lists in HStack both render")
    func twoListsInHStack() {
        // Use wider terminal to match real usage, with explicit width like WindowGroup
        var context = createTestContext(width: 160, height: 40)
        context.hasExplicitWidth = true

        var sel1: String?
        var sel2: Set<String> = []

        let items: [(String, String, String)] = [
            ("1", "README.md", "📄"), ("2", "Package.swift", "📦"),
            ("3", "Sources", "📁"), ("4", "Tests", "📁"),
            ("5", ".gitignore", "📄"), ("6", "LICENSE", "📄"),
            ("7", "docs", "📁"), ("8", "plans", "📁"),
            ("9", ".swiftlint.yml", "⚙️"), ("10", ".github", "📁"),
            ("11", "Makefile", "📄"), ("12", ".claude", "📁"),
        ]

        let view = HStack(spacing: 2) {
            List("Single Selection", selection: Binding(get: { sel1 }, set: { sel1 = $0 })) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 1) {
                        Text(item.2)
                        Text(item.1)
                    }
                }
            }
            List("Multi Selection", selection: Binding(get: { sel2 }, set: { sel2 = $0 })) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 1) {
                        Text(item.2)
                        Text(item.1)
                    }
                }
            }
        }

        let buffer = renderToBuffer(view, context: context)
        let allContent = buffer.lines.map { $0.stripped }.joined()

        #expect(allContent.contains("Single Selection"), "Should contain first list title")
        #expect(allContent.contains("Multi Selection"), "Should contain second list title, got buffer width \(buffer.width)")
        #expect(buffer.width <= 160, "Buffer should not exceed available width 160, got \(buffer.width)")

        // All lines should have the same visible width (consistent borders)
        let lineWidths = buffer.lines.map { $0.strippedLength }
        let maxLineWidth = lineWidths.max() ?? 0
        let minLineWidth = lineWidths.filter { $0 > 0 }.min() ?? 0
        #expect(
            minLineWidth == maxLineWidth,
            "All lines should have same width but min=\(minLineWidth) max=\(maxLineWidth)"
        )
    }

    @Test("Row click survives padding and border, focuses, and selects on release")
    func mouseRowClick() throws {
        let tuiContext = TUIContext()
        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(["zero", "one", "two", "three", "four"], id: \.self) { item in
                Text(item)
            }
        }
        .focusID("mouse-list")
        .padding(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
        let context = RenderContext(
            availableWidth: 30,
            availableHeight: 10,
            tuiContext: tuiContext,
            identity: ViewIdentity(path: "mouse-list-test")
        )

        tuiContext.beginRenderPass()
        tuiContext.focusManager.register(ActionHandler(focusID: "other", action: {}))
        let buffer = renderToBuffer(list, context: context)
        tuiContext.focusManager.endRenderPass()
        tuiContext.interactionDispatcher.activate(regions: buffer.regions)
        let rowRegion = try #require(buffer.regions.first { $0.id == "list-row-interaction-mouse-list-1" })
        let indicatorRow = try #require(buffer.lines.firstIndex { $0.contains("▼") })

        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .press(.left), column: rowRegion.rect.x, row: indicatorRow)
        )
        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .release(.left), column: rowRegion.rect.x, row: indicatorRow)
        )
        #expect(selection == nil)
        #expect(tuiContext.focusManager.currentFocusedID == "other")

        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .press(.left), column: rowRegion.rect.x, row: rowRegion.rect.y)
        )
        #expect(selection == nil)
        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .release(.left), column: rowRegion.rect.x, row: rowRegion.rect.y)
        )

        #expect(selection == "one")
        #expect(tuiContext.focusManager.currentFocusedID == "mouse-list")
        #expect(rowRegion.rect.x >= 3)
        #expect(rowRegion.rect.y >= 2)
    }

    @Test("Mouse wheel moves three rows without selecting and keeps focus visible")
    func mouseWheelNavigation() throws {
        let tuiContext = TUIContext()
        var selection: Int?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(Array(0..<10), id: \.self) { item in
                Text(item == 0 ? String(repeating: "Tall row ", count: 16) : "Item \(item)")
            }
        }
        .focusID("wheel-list")
        let context = RenderContext(
            availableWidth: 30,
            availableHeight: 8,
            tuiContext: tuiContext,
            identity: ViewIdentity(path: "wheel-list-test")
        )

        tuiContext.beginRenderPass()
        var buffer = renderToBuffer(list, context: context)
        tuiContext.focusManager.endRenderPass()
        tuiContext.interactionDispatcher.activate(regions: buffer.regions)
        let scrollRegion = try #require(buffer.regions.first { $0.id == "list-scroll-interaction-wheel-list" })
        let tallRowRegion = try #require(buffer.regions.first { $0.id == "list-row-interaction-wheel-list-0" })
        try #require(tallRowRegion.rect.height >= 4)

        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .scroll(.down), column: scrollRegion.rect.x, row: scrollRegion.rect.y)
        )
        #expect(selection == nil)

        tuiContext.beginRenderPass()
        buffer = renderToBuffer(list, context: context)
        tuiContext.focusManager.endRenderPass()
        tuiContext.interactionDispatcher.activate(regions: buffer.regions)
        let visibleRowIDs = Set(buffer.regions.lazy.map(\.id).filter { $0.contains("list-row-interaction-wheel-list") })

        #expect(visibleRowIDs.contains("list-row-interaction-wheel-list-3"))
        #expect(visibleRowIDs.contains("list-row-interaction-wheel-list-0") == false)
        #expect(selection == nil)
    }
}
