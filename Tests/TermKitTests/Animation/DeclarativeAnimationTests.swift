import Testing

@testable import TermKit

@MainActor
struct DeclarativeAnimationTests {
    fileprivate enum Leaf {}
    private let property = AnimationPropertyKey(rawValue: "amount")

    @Test("Value-scoped animation creates and retargets a mounted-node track")
    func valueScopedAnimationRetargetsFromPresentation() throws {
        let graph = ViewGraph()
        try commit(ValueView(value: 0, property: property), to: graph, at: .zero)
        let leaf = try #require(graph.root?.children.first?.children.first)

        try commit(ValueView(value: 10, property: property), to: graph, at: .zero)
        #expect(leaf.animationStatus(for: property) == .running)
        #expect(leaf.presentationValue(for: property, as: Double.self, at: .zero) == 0)

        let interruption = TimeInstant.zero.advanced(by: .milliseconds(400))
        let before = try #require(leaf.presentationValue(for: property, as: Double.self, at: interruption))
        try commit(ValueView(value: 20, property: property), to: graph, at: interruption)
        let after = leaf.presentationValue(for: property, as: Double.self, at: interruption)

        #expect(before == 4)
        #expect(after == before)
    }

    @Test("Removing an animatable property removes its mounted-node track")
    func removingPropertyRemovesTrack() throws {
        let graph = ViewGraph()
        try commit(ValueView(value: 0, property: property), to: graph, at: .zero)
        try commit(ValueView(value: 10, property: property), to: graph, at: .zero)
        let leaf = try #require(graph.root?.children.first?.children.first)

        try withTransaction(Transaction(animationTime: .zero)) {
            try graph.commit(graph.prepare(PlainView()))
        }

        #expect(leaf.animationStatus(for: property) == nil)
    }

    @Test("Removal transition stays noninteractive until its track completes")
    func removalTransitionCompletesPresentation() throws {
        let graph = ViewGraph()
        let transaction = Transaction(
            animation: .linear(duration: .seconds(1)),
            animationTime: .zero
        )
        try withTransaction(transaction) {
            try graph.commit(graph.prepare(TransitionView(isVisible: true)))
        }
        let inserted = try #require(graph.root?.children.first)
        _ = inserted.transitionPresentationSample(at: .zero.advanced(by: .seconds(1)))
        try withTransaction(transaction) {
            try graph.commit(graph.prepare(TransitionView(isVisible: false)))
        }
        let removed = try #require(graph.presentationRoots.first)

        #expect(removed.isPresentationOnly)
        #expect(removed.isInteractive == false)
        #expect(removed.removalTransitionSample(at: .zero.advanced(by: .milliseconds(500)))?.opacity == 0.5)
        #expect(graph.presentationNode(withID: removed.id) === removed)

        _ = removed.removalTransitionSample(at: .zero.advanced(by: .seconds(1)))
        #expect(graph.presentationNode(withID: removed.id) == nil)
    }

    @Test("Insertion transition samples its midpoint and becomes active at completion")
    func insertionTransitionCompletesPresentation() throws {
        let graph = ViewGraph()
        let transaction = Transaction(
            animation: .linear(duration: .seconds(1)),
            animationTime: .zero
        )

        try withTransaction(transaction) {
            try graph.commit(graph.prepare(TransitionView(isVisible: true)))
        }
        let inserted = try #require(graph.root?.children.first)

        #expect(inserted.presentationPhase == .inserting)
        #expect(inserted.transitionPresentationSample(at: .zero)?.opacity == 0)
        #expect(inserted.transitionPresentationSample(at: .zero.advanced(by: .milliseconds(500)))?.opacity == 0.5)
        #expect(inserted.transitionPresentationSample(at: .zero.advanced(by: .seconds(1)))?.opacity == 1)
        #expect(inserted.presentationPhase == .active)
        #expect(inserted.transitionPresentationSample(at: .zero.advanced(by: .seconds(1))) == nil)
    }

    @Test("Reinsertion reverses removal continuously and ignores stale completion")
    func reinsertionReversesRemovalContinuously() throws {
        let graph = ViewGraph()
        let animation = Animation.linear(duration: .seconds(1))
        try withTransaction(Transaction(animation: animation, animationTime: .zero)) {
            try graph.commit(graph.prepare(TransitionView(isVisible: true)))
        }
        let node = try #require(graph.root?.children.first)
        _ = node.transitionPresentationSample(at: .zero.advanced(by: .seconds(1)))

        try withTransaction(Transaction(animation: animation, animationTime: .zero.advanced(by: .seconds(1)))) {
            try graph.commit(graph.prepare(TransitionView(isVisible: false)))
        }
        let midpoint = TimeInstant.zero.advanced(by: .milliseconds(1_500))
        let before = try #require(node.transitionPresentationSample(at: midpoint)?.opacity)
        let staleToken = node.currentPresentationTransitionToken

        try withTransaction(Transaction(animation: animation, animationTime: midpoint)) {
            try graph.commit(graph.prepare(TransitionView(isVisible: true)))
        }
        let after = try #require(node.transitionPresentationSample(at: midpoint)?.opacity)

        #expect(before == 0.5)
        #expect(after == before)
        #expect(graph.completeTransition(for: node.id, token: staleToken) == false)
        #expect(graph.root?.children.first === node)
        _ = node.transitionPresentationSample(at: midpoint.advanced(by: .seconds(1)))
        #expect(node.presentationPhase == .active)
    }

    @Test("Disabled transition animation completes insertion and removal immediately")
    func disabledTransitionCompletesImmediately() throws {
        let graph = ViewGraph()
        let transaction = Transaction(
            animation: .linear(duration: .seconds(1)),
            animationsEnabled: false,
            animationTime: .zero
        )

        try withTransaction(transaction) {
            try graph.commit(graph.prepare(TransitionView(isVisible: true)))
        }
        let node = try #require(graph.root?.children.first)
        #expect(node.presentationPhase == .active)

        try withTransaction(transaction) {
            try graph.commit(graph.prepare(TransitionView(isVisible: false)))
        }
        #expect(graph.presentationNode(withID: node.id) == nil)
        #expect(graph.node(withID: node.id) == nil)
    }

    private func commit(_ view: ValueView, to graph: ViewGraph, at instant: TimeInstant) throws {
        try withTransaction(Transaction(animationTime: instant)) {
            try graph.commit(graph.prepare(view.animation(.linear(duration: .seconds(1)), value: view.value)))
        }
    }
}

@MainActor
private struct ValueView: View {
    let value: Double
    let property: AnimationPropertyKey

    var graphBody: [NodeDescriptor] {
        NodeDescriptor(type: DeclarativeAnimationTests.Leaf.self)
            .animatableValue(value, for: property)
    }
}

@MainActor
private struct PlainView: View {
    var graphBody: [NodeDescriptor] {
        NodeDescriptor(type: DeclarativeAnimationTests.Leaf.self)
    }
}

@MainActor
private struct TransitionView: View {
    let isVisible: Bool

    var graphBody: [NodeDescriptor] {
        if isVisible {
            NodeDescriptor(
                type: DeclarativeAnimationTests.Leaf.self,
                focus: FocusMetadata(isFocusable: true),
                hitTest: HitTestMetadata(isEnabled: true)
            )
            .transition(.opacity)
        }
    }
}
