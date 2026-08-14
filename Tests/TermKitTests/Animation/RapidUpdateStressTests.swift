import Testing

@testable import TermKit

@MainActor
struct RapidUpdateStressTests {
    private enum Root {}
    private enum Row {}
    private enum RetainedState {}

    @Test("Rapid overlapping updates preserve graph, state, lifecycle, focus, and animation invariants")
    func rapidOverlappingUpdates() throws {
        let operationCount = 768
        let animation = Animation.linear(duration: .milliseconds(120))
        let property = AnimationPropertyKey(rawValue: "stress-value")
        let stateKey = StateKey<Int>(RetainedState.self)
        let lifecycle = LifecycleCounts()
        let graph = ViewGraph()
        let focus = FocusManager()
        var clock = DeterministicTimeSource()
        var random = StressRandom(seed: 0x19_07_5EED_CAFE_BEEF)
        let model = StressModel()
        var expectedLifecycle = LifecycleSnapshot()
        var expectedNodes: [String: NodeID] = [:]
        var expectedState: [NodeID: Int] = [:]
        var registeredFocus: Set<Int> = []
        var staleTokens: [(NodeID, PresentationTransitionToken)] = []

        focus.register(FocusTarget(id: "source", order: -1))
        #expect(focus.requestFocus("source"))

        @MainActor func descriptor() -> NodeDescriptor {
            let children = model.order.compactMap { index -> NodeDescriptor? in
                guard model.visible[index] else { return nil }
                return NodeDescriptor(
                    type: Row.self,
                    key: "row-\(index)",
                    branch: model.branch[index] ? 1 : 0,
                    value: index,
                    focus: FocusMetadata(isFocusable: true),
                    hitTest: HitTestMetadata(isEnabled: true),
                    lifecycle: lifecycle.callbacks
                )
                .animatableValue(model.target[index], for: property)
                .transition(.opacity)
            }
            return NodeDescriptor(type: Root.self, children: children, lifecycle: lifecycle.callbacks)
        }

        @MainActor func commitModel() throws {
            try withTransaction(Transaction(animation: animation, animationTime: clock.current)) {
                #expect(Transaction.current.animationTime == clock.current)
                let plan = try graph.prepare(descriptor())
                expectedLifecycle.mounts += plan.insertionCount
                expectedLifecycle.updates += plan.updateCount
                expectedLifecycle.removals += plan.removalCount
                try graph.commit(plan)
            }
            #expect(lifecycle.snapshot == expectedLifecycle)
        }

        @MainActor func synchronizeAndCheck(step: Int) throws {
            let active = try #require(graph.root?.children)
            let activeIndexes = Set(active.compactMap { $0.value(as: Int.self) })
            let graphIDs = Set(active.map(\.id) + graph.presentationRoots.map(\.id))

            for (identity, id) in expectedNodes where graphIDs.contains(id) == false {
                expectedNodes.removeValue(forKey: identity)
                expectedState.removeValue(forKey: id)
            }

            for index in registeredFocus.subtracting(activeIndexes) {
                focus.unregister(FocusID(rawValue: "row-\(index)"))
            }
            for index in activeIndexes {
                focus.register(
                    FocusTarget(
                        id: FocusID(rawValue: "row-\(index)"),
                        scopeID: "stress-scope",
                        order: model.order.firstIndex(of: index) ?? 0
                    )
                )
            }
            registeredFocus = activeIndexes

            for node in active {
                let index = try #require(node.value(as: Int.self))
                let identity = "\(index):\(model.branch[index] ? 1 : 0)"
                if let expectedID = expectedNodes[identity] {
                    #expect(node.id == expectedID, "Step \(step) replaced retained identity \(identity)")
                } else {
                    expectedNodes[identity] = node.id
                    expectedState[node.id] = step + 1
                    node.setState(step + 1, for: stateKey)
                }
                #expect(node.state(for: stateKey) == expectedState[node.id])
                #expect(node.isPresentationOnly == false)
                #expect(node.isFocusable)
                #expect(node.acceptsHitTesting)
                node.cache(
                    size: CellSize(width: 2, height: 1),
                    frame: CellRect(x: index * 3, y: 0, width: 2, height: 1)
                )
                #expect(graph.hitTest(CellPoint(x: index * 3, y: 0)) === node)
            }

            let activeIDs = Set(active.map(\.id))
            #expect(activeIDs.count == active.count)
            #expect(Set(graph.focusableNodes().map(\.id)) == activeIDs)
            for removed in graph.presentationRoots {
                #expect(removed.isPresentationOnly)
                #expect(removed.isFocusable == false)
                #expect(removed.acceptsHitTesting == false)
                #expect(activeIDs.contains(removed.id) == false)
                if let index = removed.value(as: Int.self) {
                    #expect(graph.hitTest(CellPoint(x: index * 3, y: 0)) !== removed)
                }
            }

            #expect(graphIDs.count == active.count + graph.presentationRoots.count)
        }

        try commitModel()
        try synchronizeAndCheck(step: 0)

        for step in 1...operationCount {
            let index = random.int(in: 0..<model.visible.count)
            switch random.int(in: 0..<8) {
            case 0:
                model.visible[index].toggle()
                try commitModel()
            case 1:
                model.branch[index].toggle()
                try commitModel()
            case 2:
                if model.visible[index],
                    let node = graph.root?.children.first(where: { $0.value(as: Int.self) == index })
                {
                    let before = try #require(node.presentationValue(for: property, as: Double.self, at: clock.current))
                    model.target[index] = Double(random.int(in: -40..<41))
                    try commitModel()
                    let after = try #require(node.presentationValue(for: property, as: Double.self, at: clock.current))
                    #expect(after == before, "Step \(step) retarget jumped from its current presentation")
                } else {
                    model.target[index] = Double(random.int(in: -40..<41))
                    try commitModel()
                }
            case 3:
                let other = random.int(in: 0..<model.order.count)
                model.order.swapAt(index, other)
                try commitModel()
            case 4:
                model.visible[index] = true
                try commitModel()
                try synchronizeAndCheck(step: step)
                let node = try #require(graph.root?.children.first(where: { $0.value(as: Int.self) == index }))
                clock.advance(by: .milliseconds(1))
                _ = graph.sampleMountedAttributes(at: clock.current)
                model.visible[index] = false
                try commitModel()
                let staleToken = node.currentPresentationTransitionToken
                staleTokens.append((node.id, staleToken))
                #expect(node.isPresentationOnly)
                #expect(node.isInteractive == false)
                #expect(graph.hitTest(CellPoint(x: index * 3, y: 0)) !== node)
                model.visible[index] = true
                try commitModel()
                #expect(graph.root?.children.first(where: { $0.value(as: Int.self) == index }) === node)
                #expect(graph.completeTransition(for: node.id, token: staleToken) == false)
            case 5:
                if let node = graph.root?.children.first(where: { $0.value(as: Int.self) == index }) {
                    let value = step * 17 + index
                    node.setState(value, for: stateKey)
                    expectedState[node.id] = value
                }
                try commitModel()
            case 6:
                model.visible[index] = true
                try commitModel()
                try synchronizeAndCheck(step: step)
                #expect(focus.requestFocus("source"))
                focus.activateScope(FocusScope(id: "stress-scope", trapsFocus: true), initialFocus: FocusID(rawValue: "row-\(index)"))
                #expect(focus.focusedID == FocusID(rawValue: "row-\(index)"))
                model.visible[index] = false
                try commitModel()
                try synchronizeAndCheck(step: step)
                #expect(focus.focusedID != FocusID(rawValue: "row-\(index)"))
                #expect(focus.deactivateScope("stress-scope"))
                #expect(focus.focusedID == "source")
                model.visible[index] = true
                try commitModel()
            default:
                clock.advance(by: .milliseconds(Int64(random.int(in: 1..<31))))
                _ = graph.sampleMountedAttributes(at: clock.current)
                try commitModel()
            }

            if step.isMultiple(of: 3) {
                clock.advance(by: .milliseconds(Int64(random.int(in: 1..<18))))
                _ = graph.sampleMountedAttributes(at: clock.current)
            }
            try synchronizeAndCheck(step: step)
        }

        model.visible = Array(repeating: true, count: model.visible.count)
        model.branch = Array(repeating: false, count: model.branch.count)
        model.order = Array(model.order.indices)
        try commitModel()
        try synchronizeAndCheck(step: operationCount + 1)
        clock.advance(by: .seconds(1))
        #expect(graph.sampleMountedAttributes(at: clock.current) == 0)
        #expect(graph.presentationRoots.isEmpty)

        let finalChildren = try #require(graph.root?.children)
        #expect(finalChildren.compactMap { $0.value(as: Int.self) } == model.order)
        #expect(Set(finalChildren.map(\.id)).count == model.visible.count)
        #expect(finalChildren.allSatisfy { $0.parent === graph.root })
        #expect(finalChildren.allSatisfy { graph.node(withID: $0.id) === $0 })
        #expect(finalChildren.allSatisfy { $0.presentationPhase == .active })
        #expect(finalChildren.allSatisfy { $0.state(for: stateKey) == expectedState[$0.id] })
        #expect(graph.focusableNodes().map(\.id) == finalChildren.map(\.id))
        #expect(lifecycle.snapshot == expectedLifecycle)
        for (id, token) in staleTokens {
            #expect(graph.completeTransition(for: id, token: token) == false)
        }
    }
}

@MainActor
private final class LifecycleCounts {
    private(set) var snapshot = LifecycleSnapshot()

    var callbacks: NodeLifecycle {
        NodeLifecycle(
            onMount: { [self] _ in snapshot.mounts += 1 },
            onUpdate: { [self] _ in snapshot.updates += 1 },
            onRemove: { [self] _ in snapshot.removals += 1 }
        )
    }
}

private struct LifecycleSnapshot: Equatable {
    var mounts = 0
    var updates = 0
    var removals = 0
}

@MainActor
private final class StressModel {
    var visible = Array(repeating: true, count: 6)
    var branch = Array(repeating: false, count: 6)
    var target = Array(repeating: 0.0, count: 6)
    var order = Array(0..<6)
}

private struct StressRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func int(in range: Range<Int>) -> Int {
        precondition(range.isEmpty == false)
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return range.lowerBound + Int(value % UInt64(range.count))
    }
}
