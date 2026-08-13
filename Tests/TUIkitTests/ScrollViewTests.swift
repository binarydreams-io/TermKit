//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context sized for a short scroll viewport.
private func testContext(width: Int = 40, height: Int = 5) -> RenderContext {
    RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIkit.TUIContext())
}

/// Creates seven single-line rows so the content overflows a five-line viewport.
@MainActor
private func sevenLineContent() -> some View {
    VStack(alignment: .leading) {
        Text("l0")
        Text("l1")
        Text("l2")
        Text("l3")
        Text("l4")
        Text("l5")
        Text("l6")
    }
}

// MARK: - ScrollView Tests

@MainActor
@Suite("ScrollView Tests", .serialized)
struct ScrollViewTests {

    @Test("Content shorter than the viewport is padded to the viewport height")
    func shortContentIsPadded() {
        let view = ScrollView { Text("one") }
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.height == 5)
        #expect(buffer.lines[0].stripped.contains("one"))
    }

    @Test("Offset clips the top of the content")
    func offsetClipsTop() {
        var offset = 2
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)
            .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines[0].stripped.contains("l2"))
        #expect(buffer.height == 5)
    }

    @Test("Metrics report content height, maximum offset, and page size")
    func metricsReportGeometry() {
        var metrics = ScrollMetrics()
        let binding = Binding(get: { metrics }, set: { metrics = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollMetrics(binding)
        _ = renderToBuffer(view, context: testContext())

        #expect(metrics.contentHeight == 7)
        #expect(metrics.viewportHeight == 5)
        #expect(metrics.maximumOffset == 2)
        #expect(metrics.pageSize == 3)
    }

    @Test("Offset beyond the maximum clamps to the maximum")
    func offsetClampsToMaximum() {
        var offset = 99
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)
            .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines[0].stripped.contains("l2"))
    }

    @Test("Offset below zero clamps to the first content row")
    func negativeOffsetClampsToZero() {
        var offset = -4
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)
            .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines[0].stripped.contains("l0"))
        #expect(buffer.height == 5)
    }

    @Test("A viewport without available height keeps one row")
    func zeroAvailableHeightKeepsOneRow() {
        var metrics = ScrollMetrics()
        let binding = Binding(get: { metrics }, set: { metrics = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollMetrics(binding)
        let buffer = renderToBuffer(view, context: testContext(height: 0))

        #expect(buffer.height == 1)
        #expect(metrics.viewportHeight == 1)
        #expect(metrics.maximumOffset == 6)
        #expect(metrics.pageSize == 1)
    }

    @Test("Clamping never writes back through the offset binding")
    func clampingDoesNotWriteBackTheOffset() {
        var offset = 99
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)
        _ = renderToBuffer(view, context: testContext())

        #expect(offset == 99)
    }

    @Test("Content shorter than the viewport reports no scroll room")
    func shortContentReportsNoScrollRoom() {
        var metrics = ScrollMetrics()
        let binding = Binding(get: { metrics }, set: { metrics = $0 })
        let view = ScrollView { Text("one") }
            .scrollMetrics(binding)
        _ = renderToBuffer(view, context: testContext())

        #expect(metrics.contentHeight == 1)
        #expect(metrics.viewportHeight == 5)
        #expect(metrics.maximumOffset == 0)
    }

    @Test("Empty content still fills the viewport")
    func emptyContentFillsTheViewport() {
        var metrics = ScrollMetrics()
        let binding = Binding(get: { metrics }, set: { metrics = $0 })
        let view = ScrollView { EmptyView() }
            .scrollMetrics(binding)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.height == 5)
        #expect(metrics.contentHeight == 0)
        #expect(metrics.maximumOffset == 0)
    }

    @Test("Every viewport line is padded to one visible width")
    func viewportLinesShareOneVisibleWidth() {
        let view = ScrollView { sevenLineContent() }
            .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines.count == 5)
        #expect(buffer.lines.allSatisfy { $0.strippedLength == buffer.width })
    }

    @Test("Viewport lines keep the trailing ANSI reset of the widest content line")
    func viewportLinesKeepTheTrailingANSIReset() {
        let view = ScrollView { sevenLineContent() }
            .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines[0].contains(ANSIRenderer.reset))
    }

    @Test("Interaction regions translate into viewport coordinates")
    func regionsTranslateIntoViewportCoordinates() {
        var offset = 2
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView {
            VStack(alignment: .leading) {
                Text("l0")
                Text("l1")
                Text("l2")
                Button("tap") {}
                Text("l4")
                Text("l5")
                Text("l6")
            }
        }
        .scrollOffset(binding)
        .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        let buttonRegion = buffer.regions.first { $0.id.contains("button") }
        #expect(buttonRegion?.rect.y == 1)
        #expect(buffer.regions.allSatisfy { $0.rect.y >= 0 && $0.rect.maxY <= buffer.height })
    }

    @Test("Regions scrolled out of the viewport are dropped")
    func regionsOutsideTheViewportAreDropped() {
        var offset = 2
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView {
            VStack(alignment: .leading) {
                Button("tap") {}
                Text("l1")
                Text("l2")
                Text("l3")
                Text("l4")
                Text("l5")
                Text("l6")
            }
        }
        .scrollOffset(binding)
        .scrollIndicators(false)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(!buffer.regions.contains { $0.id.contains("button") })
    }

    @Test("Metrics carry the pre-clip content regions")
    func metricsCarryPreClipContentRegions() {
        var metrics = ScrollMetrics()
        let metricsBinding = Binding(get: { metrics }, set: { metrics = $0 })
        var offset = 2
        let offsetBinding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView {
            VStack(alignment: .leading) {
                Text("l0")
                Text("l1")
                Text("l2")
                Button("tap") {}
                Text("l4")
                Text("l5")
                Text("l6")
            }
        }
        .scrollOffset(offsetBinding)
        .scrollMetrics(metricsBinding)
        _ = renderToBuffer(view, context: testContext())

        let buttonRegion = metrics.contentRegions.first { $0.id.contains("button") }
        #expect(buttonRegion?.rect.y == 3)
    }

    @Test("Measurement passes leave the metrics binding untouched")
    func measurementDoesNotWriteMetrics() {
        var metrics = ScrollMetrics()
        let binding = Binding(get: { metrics }, set: { metrics = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollMetrics(binding)
        var context = testContext()
        context.isMeasuring = true
        _ = renderToBuffer(view, context: context)

        #expect(metrics == ScrollMetrics())
    }

    // MARK: - Indicators

    @Test("Indicators appear only on the overflowing edges")
    func indicatorsMarkOverflow() {
        var offset = 1
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines.first?.stripped.contains("▲") == true)
        #expect(buffer.lines.last?.stripped.contains("▼") == true)
    }

    @Test("Indicators stay off when content fits the viewport exactly")
    func indicatorsAbsentWhenContentFitsExactly() {
        let view = ScrollView {
            VStack(alignment: .leading) {
                Text("l0")
                Text("l1")
                Text("l2")
                Text("l3")
                Text("l4")
            }
        }
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines.allSatisfy { !$0.stripped.contains("▲") && !$0.stripped.contains("▼") })
    }

    @Test("Only the top indicator appears when the offset is at the maximum")
    func indicatorsShowOnlyTopAtMaximumOffset() {
        var offset = 2
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)
        let buffer = renderToBuffer(view, context: testContext())

        #expect(buffer.lines.first?.stripped.contains("▲") == true)
        #expect(buffer.lines.last?.stripped.contains("▼") == false)
    }

    @Test("A one-line viewport that overflows on both edges keeps the down indicator")
    func indicatorsInSingleLineViewportPreferDownArrow() {
        var offset = 1
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView {
            VStack(alignment: .leading) {
                Text("l0")
                Text("l1")
                Text("l2")
            }
        }
        .scrollOffset(binding)
        let buffer = renderToBuffer(view, context: testContext(height: 1))

        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped.contains("▼") == true)
        #expect(buffer.lines[0].stripped.contains("▲") == false)
    }

    @Test("A content region under the top indicator is dropped, not left clickable")
    func indicatorOverlayDropsUnderlyingRegion() {
        var offset = 3
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let view = ScrollView {
            VStack(alignment: .leading) {
                Text("l0")
                Text("l1")
                Text("l2")
                Button("tap") {}
                Text("l4")
                Text("l5")
                Text("l6")
                Text("l7")
                Text("l8")
            }
        }
        .scrollOffset(binding)
        let buffer = renderToBuffer(view, context: testContext())

        // Nine content rows in a five-row viewport put maximumOffset at 4,
        // so offset 3 keeps both edges overflowing (both indicators show),
        // and the button's content row (index 3) lands exactly on viewport
        // row 0 — the row the top indicator overlays.
        #expect(buffer.lines.first?.stripped.contains("▲") == true)
        #expect(buffer.lines.last?.stripped.contains("▼") == true)
        #expect(!buffer.regions.contains { $0.id.contains("button") })
    }

    // MARK: - Mouse Wheel

    @Test("Mouse wheel scroll region covers the viewport and moves the offset")
    func wheelScrollAdjustsOffset() throws {
        var offset = 0
        let binding = Binding(get: { offset }, set: { offset = $0 })
        let tuiContext = TUIkit.TUIContext()
        let context = RenderContext(
            availableWidth: 40,
            availableHeight: 5,
            tuiContext: tuiContext,
            identity: ViewIdentity(path: "scrollview-wheel-test")
        )
        let view = ScrollView { sevenLineContent() }
            .scrollOffset(binding)

        tuiContext.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.interactionDispatcher.activate(regions: buffer.regions)
        let scrollRegion = try #require(buffer.regions.first { $0.id.hasPrefix("scrollview-scroll-") })

        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .scroll(.down), column: scrollRegion.rect.x, row: scrollRegion.rect.y)
        )

        // Content is 7 rows in a 5-row viewport, so maximumOffset is 2. A
        // +3 wheel tick from 0 clamps to that maximum instead of reaching 3.
        #expect(offset == 2)
    }

    @Test("Wheel scroll without a binding persists the offset in the state box across renders")
    func wheelScrollPersistsInStateBoxAcrossRenders() throws {
        let tuiContext = TUIkit.TUIContext()
        let context = RenderContext(
            availableWidth: 40,
            availableHeight: 5,
            tuiContext: tuiContext,
            identity: ViewIdentity(path: "scrollview-state-box-test")
        )
        let view = ScrollView { sevenLineContent() }
            .scrollIndicators(false)

        tuiContext.beginRenderPass()
        var buffer = renderToBuffer(view, context: context)
        tuiContext.interactionDispatcher.activate(regions: buffer.regions)
        let scrollRegion = try #require(buffer.regions.first { $0.id.hasPrefix("scrollview-scroll-") })
        #expect(buffer.lines[0].stripped.contains("l0"))

        _ = tuiContext.interactionDispatcher.dispatch(
            MouseEvent(action: .scroll(.down), column: scrollRegion.rect.x, row: scrollRegion.rect.y)
        )

        tuiContext.beginRenderPass()
        buffer = renderToBuffer(view, context: context)
        tuiContext.interactionDispatcher.activate(regions: buffer.regions)

        #expect(buffer.lines[0].stripped.contains("l2"))
    }
}
