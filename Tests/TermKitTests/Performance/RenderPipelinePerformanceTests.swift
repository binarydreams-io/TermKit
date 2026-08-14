import Testing

@testable import TermKit

@MainActor
@Suite(
    "Section 15 render pipeline performance",
    .disabled(
        if: termKitPerformanceTestsEnabled == false,
        "Set TERMKIT_RUN_PERFORMANCE_TESTS=1 and use a release build."
    )
)
struct RenderPipelinePerformanceTests {
    @Test("Localized 120x40 animation stays below the p95 frame budget")
    func localizedAnimation() throws {
        let size = CellSize(width: 120, height: 40)
        let damageRect = CellRect(x: 52, y: 18, width: 16, height: 3)
        let harness = try RuntimeFrameHarness(size: size)
        var contractIsValid = true

        let result = try measureBenchmark(
            name: "localized 120x40 graph/layout/paint/present",
            warmupCount: 30,
            sampleCount: 240,
            operation: { index in
                try harness.localizedFrame(index: index, rect: damageRect)
            },
            inspect: { frame in
                contractIsValid =
                    contractIsValid
                    && frame.presentation.didWrite
                    && frame.presentation.stats.scannedCellCount == damageRect.cellCount
                    && frame.presentation.stats.changedCellCount == damageRect.cellCount
                    && frame.presentation.stats.operationCount > 0
            }
        )

        print(result.report(budgetMilliseconds: 8))
        #expect(
            contractIsValid,
            "The localized benchmark stopped exercising changed cells or exceeded its damage rectangle."
        )
        #expect(result.samplesNanoseconds.count == 240, "The benchmark did not retain every measured frame.")
        #expect(harness.view.descriptorCount == 270)
        #expect(harness.view.layoutCount == 270)
        #expect(harness.view.paintCount == 270)
        #expect(harness.view.animatedPaintCount == 270)
        #expect(harness.session.logicalWriteCount == 270)
        #expect(
            result.percentile95Milliseconds < 8,
            Comment(
                rawValue: result.failureMessage(
                    budgetMilliseconds: 8,
                    guidance: "Inspect localized surface painting, damage scanning, diff generation, and ANSI encoding."
                )
            )
        )
    }

    @Test("Declarative paint animation skips reconciliation and layout")
    func declarativePaintAnimation() throws {
        let size = CellSize(width: 16, height: 40)
        let view = DeclarativePaintBenchmarkView()
        let session = BenchmarkTerminalSession()
        let runtime = Runtime(
            view: view,
            presenter: FramePresenter(session: session),
            terminalSize: size,
            timeSource: DeterministicTimeSource()
        )
        try runtime.start()
        _ = try runtime.renderIfDue(at: .zero)
        var transaction = Transaction(animation: .linear(duration: .seconds(10)), animationTime: .zero)
        withTransaction(transaction) {
            view.color = LinearRGBA(.white)
            transaction = Transaction.current
            runtime.invalidate(transaction: transaction)
        }
        var instant = TimeInstant.zero.advanced(by: FrameScheduler.minimumFrameInterval)
        _ = try runtime.renderIfDue(at: instant)
        let revision = runtime.graph.revision
        let evaluationCount = view.evaluationCount
        var counters = try #require(runtime.incrementalCounters)
        var phasesAreValid = true
        var damageIsValid = true
        var visitsAreValid = true
        var semanticsAreValid = true

        let operation: (Int) throws -> RuntimeFrameResult = { _ in
            instant = instant.advanced(by: FrameScheduler.minimumFrameInterval)
            guard let frame = try runtime.renderIfDue(at: instant) else {
                preconditionFailure("A declarative animation frame was not due.")
            }
            return frame
        }
        let inspect: (RuntimeFrameResult) -> Void = { frame in
            let phasesAreIncremental =
                frame.stats.reconciliationDuration == .zero
                && frame.stats.layoutDuration == .zero
                && frame.graphRevision == revision
            let nextCounters = runtime.incrementalCounters
            let paintVisits = (nextCounters?.paintVisitCount ?? 0) - counters.paintVisitCount
            let damageIsBounded =
                frame.presentation.stats.scannedCellCount > 0
                && frame.presentation.stats.scannedCellCount <= size.width
                && frame.presentation.stats.changedCellCount <= size.width
            let semanticsAreComplete =
                frame.semantics.node(withID: "row-0") != nil
                && frame.semantics.node(withID: "row-5000") != nil
                && frame.semantics.node(withID: "row-9999") != nil
            phasesAreValid = phasesAreValid && phasesAreIncremental
            damageIsValid = damageIsValid && damageIsBounded
            visitsAreValid = visitsAreValid && paintVisits <= 3
            semanticsAreValid = semanticsAreValid && semanticsAreComplete
            counters = nextCounters ?? counters
        }
        let result = try measureBenchmark(
            name: "declarative 10,000-row localized paint animation",
            warmupCount: 30,
            sampleCount: 240,
            operation: operation,
            inspect: inspect
        )

        print(result.report(budgetMilliseconds: 8))
        #expect(phasesAreValid)
        #expect(damageIsValid)
        #expect(visitsAreValid)
        #expect(semanticsAreValid)
        #expect(view.evaluationCount == evaluationCount)
        #expect(result.percentile95Milliseconds < 8)
    }

    @Test("A 200x60 full repaint stays below one 60 Hz frame")
    func fullRepaint() throws {
        let size = CellSize(width: 200, height: 60)
        let harness = try RuntimeFrameHarness(size: size)
        var contractIsValid = true

        let result = try measureBenchmark(
            name: "200x60 full graph/layout/paint/present",
            warmupCount: 5,
            sampleCount: 30,
            operation: { index in
                try harness.fullRepaintFrame(index: index)
            },
            inspect: { frame in
                contractIsValid =
                    contractIsValid
                    && frame.presentation.didWrite
                    && frame.presentation.stats.scannedCellCount == size.cellCount
                    && frame.presentation.stats.changedCellCount == size.cellCount
            }
        )

        print(result.report(budgetMilliseconds: 16.67))
        #expect(contractIsValid, "The full-repaint benchmark did not repaint and scan all 12,000 cells.")
        #expect(
            result.percentile95Milliseconds < 16.67,
            Comment(
                rawValue: result.failureMessage(
                    budgetMilliseconds: 16.67,
                    guidance: "Inspect full-surface painting, invalidated-copy creation, diff generation, and ANSI encoding."
                )
            )
        )
    }

    @Test("An unchanged frame emits no operations and performs no write")
    func unchangedFrame() throws {
        let harness = try RuntimeFrameHarness(size: CellSize(width: 120, height: 40))
        let graphRevision = harness.runtime.graph.revision

        let result = try harness.runtime.renderIfDue(at: harness.instant)

        #expect(result == nil)
        #expect(harness.view.descriptorCount == 0)
        #expect(harness.view.layoutCount == 0)
        #expect(harness.view.paintCount == 0)
        #expect(harness.runtime.graph.revision == graphRevision)
        #expect(harness.session.logicalWriteCount == 0)
        #expect(harness.session.presentedByteCount == 0)
    }

    @Test("An ordinary changed frame performs one logical in-memory write")
    func oneLogicalWrite() throws {
        let harness = try RuntimeFrameHarness(size: CellSize(width: 120, height: 40))

        let result = try harness.localizedFrame(
            index: 0,
            rect: CellRect(x: 20, y: 10, width: 8, height: 2)
        )

        #expect(result.presentation.didWrite)
        #expect(result.presentation.stats.operationCount > 0)
        #expect(harness.session.logicalWriteCount == 1)
        #expect(harness.session.presentedByteCount == result.presentation.stats.encodedByteCount)
    }
}

@MainActor
private final class DeclarativePaintBenchmarkView: View {
    private static let changedIndex = 20
    var color = LinearRGBA(.black)
    private(set) var evaluationCount = 0

    var graphBody: [NodeDescriptor] {
        evaluationCount += 1
        let rows = (0..<10_000).map { index in
            var row = NodeDescriptor(
                type: Text.self,
                key: index,
                primitive: Text("row \(index)", id: SemanticID(rawValue: "row-\(index)")),
                dirtyOnUpdate: .layout
            )
            if index == Self.changedIndex {
                row = row.presentationValue(color, for: .foregroundColor)
            }
            return row
        }
        return [
            NodeDescriptor(
                type: VStack.self,
                primitive: LayoutPrimitive.stack(StackLayout(axis: .vertical, horizontalAlignment: .leading)),
                children: rows,
                dirtyOnUpdate: .layout
            )
        ]
    }
}
