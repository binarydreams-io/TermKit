//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ChartTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context sized for a short chart viewport.
private func testContext(width: Int = 40, height: Int = 5) -> RenderContext {
    RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIkit.TUIContext())
}

// MARK: - Chart Tests

@MainActor
@Suite("Chart Tests")
struct ChartTests {
    @Test("Sparkline maps values to block glyphs")
    func sparklineMapsValues() {
        let buffer = renderToBuffer(Sparkline(values: [0, 0.5, 1]), context: testContext())
        let glyphs = Array(buffer.lines[0].stripped.trimmingCharacters(in: .whitespaces))
        #expect(glyphs.count == 3)
        #expect(glyphs.first == "▁")
        #expect(glyphs[1] == "▅")
        #expect(glyphs.last == "█")
    }

    @Test("Sparkline of equal or empty values renders flat without crashing")
    func sparklineHandlesDegenerateInput() {
        _ = renderToBuffer(Sparkline(values: []), context: testContext())
        let buffer = renderToBuffer(Sparkline(values: [0, 0]), context: testContext())
        #expect(buffer.lines[0].stripped.contains("▁▁"))
    }

    @Test("Sparkline treats non-finite values as zero instead of trapping")
    func sparklineHandlesNonFiniteValues() {
        let buffer = renderToBuffer(
            Sparkline(values: [.nan, 10, .infinity]),
            context: testContext()
        )
        let glyphs = Array(buffer.lines[0].stripped.trimmingCharacters(in: .whitespaces))
        #expect(glyphs.count == 3)
        #expect(glyphs[0] == "▁") // .nan sanitized to 0
        #expect(glyphs[1] == "█") // 10 is the only finite, positive value: it's the maximum
        #expect(glyphs[2] == "▁") // .infinity sanitized to 0
    }

    @Test("BarChart renders one row per item with a proportional bar")
    func barChartRendersRows() {
        let buffer = renderToBuffer(
            BarChart(items: [.init(label: "swiftui-pro", value: 100), .init(label: "pdf", value: 50)]),
            context: testContext(width: 40, height: 5)
        )
        #expect(buffer.height == 2)
        let first = buffer.lines[0].stripped
        let second = buffer.lines[1].stripped
        #expect(first.contains("swiftui-pro"))
        let firstBar = first.filter { $0 == "█" }.count
        let secondBar = second.filter { $0 == "█" }.count
        #expect(firstBar == secondBar * 2)
    }

    @Test("BarChart with no items renders an empty, zero-height buffer")
    func barChartEmptyItemsHasZeroHeight() {
        let buffer = renderToBuffer(BarChart(items: []), context: testContext())
        #expect(buffer.height == 0)
    }

    @Test("BarChart renders a zero value as an all-empty track")
    func barChartZeroValueRendersEmptyTrack() {
        let buffer = renderToBuffer(
            BarChart(items: [.init(label: "a", value: 10), .init(label: "b", value: 0)]),
            context: testContext(width: 40, height: 5)
        )
        let zeroRow = buffer.lines[1].stripped
        #expect(!zeroRow.contains("█"))
        #expect(zeroRow.contains("░"))
    }

    @Test("BarChart renders a negative value as an all-empty track")
    func barChartNegativeValueRendersEmptyTrack() {
        let buffer = renderToBuffer(
            BarChart(items: [.init(label: "a", value: 10), .init(label: "b", value: -5)]),
            context: testContext(width: 40, height: 5)
        )
        let negativeRow = buffer.lines[1].stripped
        #expect(!negativeRow.contains("█"))
        #expect(negativeRow.contains("-5"))
    }

    @Test("BarChart renders without crashing at a very narrow width")
    func barChartHandlesNarrowWidth() {
        let buffer = renderToBuffer(
            BarChart(items: [.init(label: "very-long-label-name", value: 1234), .init(label: "x", value: 5678)]),
            context: testContext(width: 8, height: 5)
        )
        #expect(buffer.height == 2)
    }

    @Test("BarChart treats non-finite values as zero instead of trapping")
    func barChartHandlesNonFiniteValues() {
        let buffer = renderToBuffer(
            BarChart(items: [
                .init(label: "a", value: 10),
                .init(label: "b", value: .nan),
                .init(label: "c", value: .infinity),
            ]),
            context: testContext(width: 40, height: 5)
        )
        #expect(buffer.height == 3)
        let nanRow = buffer.lines[1].stripped
        let infinityRow = buffer.lines[2].stripped
        #expect(!nanRow.contains("█"))
        #expect(nanRow.contains("0"))
        #expect(!infinityRow.contains("█"))
        #expect(infinityRow.contains("0"))
    }

    @Test("BarChart prints a value outside the integer range instead of trapping")
    func barChartHandlesValuesOutsideTheIntegerRange() {
        let buffer = renderToBuffer(
            BarChart(items: [
                .init(label: "a", value: 1e30),
                .init(label: "b", value: 10),
            ]),
            context: testContext(width: 40, height: 5)
        )
        #expect(buffer.height == 2)
        #expect(buffer.lines[0].stripped.contains("1e+30"))
        #expect(buffer.lines[1].stripped.contains("10"))
    }
}
