import Testing

@testable import TermKit

@MainActor
@Suite(
    "Section 15 scalability performance",
    .disabled(
        if: termKitPerformanceTestsEnabled == false,
        "Set TERMKIT_RUN_PERFORMANCE_TESTS=1 and use a release build."
    )
)
struct ScalabilityPerformanceTests {
    @Test("A 10,000-item conversation renders only its lazy visible range")
    func lazyConversation() throws {
        let itemCount = 10_000
        let items = (0..<itemCount).map { "Transcript item \($0)" }
        let state = ConversationViewportState(
            viewportExtent: 20,
            itemExtent: 1,
            itemCount: itemCount,
            overscan: 2
        )
        let viewport = ConversationViewport(items: items, state: state)
        let context = try AgentRenderContext(width: 120, scheme: .dark)
        let result = measureBenchmark(
            name: "10,000-item lazy conversation render",
            warmupCount: 10,
            sampleCount: 100,
            operation: { _ in viewport.render(in: context) }
        )
        let output = viewport.render(in: context)

        print(result.report(budgetMilliseconds: 8))
        #expect(output.semantics.children.count <= 24)
        #expect(output.cells.height <= 48)
        #expect(output.plainText.contains("Transcript item 9999"))
        #expect(output.plainText.contains("Transcript item 0") == false)
        #expect(result.percentile95Milliseconds < 8)
    }

    @Test("One tool-row mutation stays local in a mounted 10,000-item transcript")
    func localToolRowMutation() throws {
        let context = try AgentRenderContext(width: 120, scheme: .dark)
        let changedIndex = 5_000
        let harness = try ToolTranscriptHarness(
            itemCount: 10_000,
            visibleIndex: changedIndex,
            context: context
        )
        var contractIsValid = true

        let result = try measureBenchmark(
            name: "10,000-item mounted tool-row local invalidation",
            warmupCount: 20,
            sampleCount: 200,
            operation: { index in
                try harness.mutateRow(
                    at: changedIndex,
                    to: index.isMultiple(of: 2) ? .running : .completed
                )
            },
            inspect: { mutation in
                contractIsValid =
                    contractIsValid
                    && mutation.mountedItemCount <= 24
                    && mutation.reconciledItemCount <= 24
                    && mutation.changedItemCount == 1
                    && mutation.layoutCount == 1
                    && mutation.paintCount == 1
                    && mutation.paintedCellCount == context.width
                    && mutation.output.semantics.state.contains(.busy)
                        == (mutation.state == .running)
            }
        )

        print(result.report(budgetMilliseconds: 8))
        #expect(harness.transcriptItemCount == 10_000)
        #expect(harness.mountedItemCount <= 24)
        #expect(contractIsValid, "The mutation escaped the lazy mounted range or laid out and painted extra rows.")
        #expect(harness.row(at: changedIndex - 1).state == .completed)
        #expect(harness.row(at: changedIndex + 1).state == .completed)
        #expect(
            result.percentile95Milliseconds < 8,
            Comment(
                rawValue: result.failureMessage(
                    budgetMilliseconds: 8,
                    guidance: "Inspect visible-range reconciliation and tool-row-local layout and paint."
                )
            )
        )
    }

    @Test("One runtime row invalidation scans one row instead of the full surface")
    func oneRowDamage() throws {
        let size = CellSize(width: 120, height: 40)
        let row = CellRect(x: 0, y: 21, width: size.width, height: 1)
        let harness = try RuntimeFrameHarness(size: size)

        let result = try harness.localizedFrame(index: 0, rect: row)

        #expect(result.presentation.stats.scannedCellCount == size.width)
        #expect(result.presentation.stats.changedCellCount == size.width)
        #expect(result.presentation.stats.scannedCellCount < size.cellCount)
        #expect(result.presentation.didWrite)
        #expect(harness.view.layoutCount == 1)
        #expect(harness.view.paintCount == 1)
    }

    @Test("Interner growth is bounded and rebuild retains only live cells")
    func boundedInternerRebuild() throws {
        let limits = InternerLimits(
            rebuildEntryCount: 8,
            maximumEntryCount: 16,
            rebuildByteCount: 1_024,
            maximumByteCount: 2_048
        )
        let session = BenchmarkTerminalSession()
        let presenter = FramePresenter(session: session, internerLimits: limits)
        let liveIdentifier = try presenter.withRenderResources { resources in
            try resources.graphemes.intern("x")
        }
        let surface = Surface(
            size: CellSize(width: 20, height: 2),
            fill: PackedCell(graphemeID: liveIdentifier, styleID: .default, displayWidth: 1)
        )
        _ = try presenter.present(surface)
        try presenter.withRenderResources { resources in
            for grapheme in ["a", "b", "c", "d", "e", "f"] {
                _ = try resources.graphemes.intern(grapheme)
            }
        }
        let peak = presenter.resources.graphemes.stats
        session.resetCounters()

        let result = try presenter.present(surface)
        let rebuilt = presenter.resources.graphemes.stats

        #expect(peak.requiresRebuild)
        #expect(peak.entryCount == limits.rebuildEntryCount)
        #expect(peak.entryCount <= limits.maximumEntryCount)
        #expect(peak.estimatedByteCount <= limits.maximumByteCount)
        #expect(result.stats.rebuiltInterners)
        #expect(result.stats.wasFullRepaint)
        #expect(rebuilt.entryCount == 2)
        #expect(rebuilt.estimatedByteCount <= limits.maximumByteCount)
        #expect(session.logicalWriteCount == 1)
    }
}

@MainActor
private final class ToolTranscriptHarness {
    private enum TranscriptRoot {}
    private enum MountedToolRow {}

    private var viewport: ConversationViewport<ToolCallRow<Int>>
    private let context: AgentRenderContext
    private let graph = ViewGraph()
    private var mountedRows: [Int: ToolCallRow<Int>] = [:]

    init(itemCount: Int, visibleIndex: Int, context: AgentRenderContext) throws {
        var state = ConversationViewportState(
            viewportExtent: 20,
            itemExtent: 1,
            itemCount: itemCount,
            overscan: 2,
            initiallyPinnedToBottom: false
        )
        state.scroll(to: Double(visibleIndex - 10))
        viewport = ConversationViewport(
            items: (0..<itemCount).map { index in
                ToolCallRow(id: index, label: "Tool call \(index)", state: .completed)
            },
            state: state
        )
        self.context = context

        let range = visibleRange
        mountedRows.reserveCapacity(range.count)
        for index in range {
            mountedRows[index] = viewport.items[index]
            _ = viewport.items[index].render(in: context)
        }
        try graph.commit(graph.prepare(descriptor(for: range)))
        graph.clearDirtyFlags()
    }

    var transcriptItemCount: Int { viewport.items.count }
    var mountedItemCount: Int { graph.root?.children.count ?? 0 }

    func row(at index: Int) -> ToolCallRow<Int> {
        viewport.items[index]
    }

    func mutateRow(at index: Int, to state: ToolCallState) throws -> ToolTranscriptMutation {
        precondition(visibleRange.contains(index), "The benchmark mutation must target a mounted row.")
        viewport.items[index].state = state

        let range = visibleRange
        let plan = try graph.prepare(descriptor(for: range))
        let reconciledItemCount = plan.updateCount - 1
        precondition(plan.insertionCount == 0 && plan.removalCount == 0)
        try graph.commit(plan)

        var changedRows: [(Int, ToolCallRow<Int>)] = []
        changedRows.reserveCapacity(1)
        for mountedIndex in range {
            let row = viewport.items[mountedIndex]
            if mountedRows[mountedIndex] != row {
                changedRows.append((mountedIndex, row))
            }
        }
        precondition(changedRows.count == 1, "The benchmark must change exactly one mounted row.")

        let layoutCount = graph.root?.children.filter { $0.dirtyFlags.contains(.layout) }.count ?? 0
        var paintCount = 0
        var paintedCellCount = 0
        var output: AgentRenderOutput?
        for changed in changedRows {
            let rendered = changed.1.render(in: context)
            paintCount += 1
            paintedCellCount += rendered.cells.width * rendered.cells.height
            mountedRows[changed.0] = changed.1
            output = rendered
        }
        graph.clearDirtyFlags()
        return ToolTranscriptMutation(
            state: state,
            mountedItemCount: range.count,
            reconciledItemCount: reconciledItemCount,
            changedItemCount: changedRows.count,
            layoutCount: layoutCount,
            paintCount: paintCount,
            paintedCellCount: paintedCellCount,
            output: output!
        )
    }

    private var visibleRange: Range<Int> {
        viewport.state.visiblePlan().visibleRange
    }

    private func descriptor(for range: Range<Int>) -> NodeDescriptor {
        NodeDescriptor(
            type: TranscriptRoot.self,
            children: range.map { index in
                NodeDescriptor(
                    type: MountedToolRow.self,
                    key: viewport.items[index].id,
                    value: viewport.items[index],
                    dirtyOnUpdate: mountedRows[index] == viewport.items[index] ? [] : .layout
                )
            },
            dirtyOnUpdate: []
        )
    }
}

private struct ToolTranscriptMutation {
    let state: ToolCallState
    let mountedItemCount: Int
    let reconciledItemCount: Int
    let changedItemCount: Int
    let layoutCount: Int
    let paintCount: Int
    let paintedCellCount: Int
    let output: AgentRenderOutput
}
