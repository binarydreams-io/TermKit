/// Reports why a reconciliation operation cannot proceed.
public enum ReconciliationPlanError: Error, Equatable {
    /// The plan or transaction belongs to another graph.
    case wrongGraph
    /// The graph that created the operation no longer exists.
    case graphDeallocated
    /// The operation no longer matches the graph revision or active transaction.
    case stale
    /// The operation was already consumed.
    case consumed
    /// Another commit, frame, or lifecycle callback is active.
    case reentrantCommit
}

/// Describes the changes needed to reconcile a view graph.
@MainActor
public final class ReconciliationPlan {
    /// The number of nodes that the plan inserts.
    public let insertionCount: Int
    /// The number of existing nodes that the plan updates.
    public let updateCount: Int
    /// The number of nodes that the plan removes.
    public let removalCount: Int

    fileprivate weak var graph: ViewGraph?
    fileprivate let revision: UInt64
    fileprivate var root: PlannedNode?
    fileprivate var removedRoot: MountedNode?
    fileprivate var isConsumed: Bool

    fileprivate init(
        graph: ViewGraph,
        revision: UInt64,
        root: PlannedNode?,
        removedRoot: MountedNode?,
        counts: PlanCounts
    ) {
        self.graph = graph
        self.revision = revision
        self.root = root
        self.removedRoot = removedRoot
        insertionCount = counts.insertions
        updateCount = counts.updates
        removalCount = counts.removals
        isConsumed = false
    }
}

/// Represents an applied commit that awaits completion or rollback.
@MainActor
public final class ViewGraphCommit {
    fileprivate weak var graph: ViewGraph?
    fileprivate let snapshot: CommitSnapshot
    fileprivate let createdNodes: [MountedNode]
    fileprivate var lifecycleEvents: [LifecycleEvent]
    fileprivate var completionActions: [MountedNodeAttributeAction]
    fileprivate var isConsumed: Bool

    fileprivate init(
        graph: ViewGraph,
        snapshot: CommitSnapshot,
        createdNodes: [MountedNode],
        lifecycleEvents: [LifecycleEvent],
        completionActions: [MountedNodeAttributeAction]
    ) {
        self.graph = graph
        self.snapshot = snapshot
        self.createdNodes = createdNodes
        self.lifecycleEvents = lifecycleEvents
        self.completionActions = completionActions
        isConsumed = false
    }
}

/// Represents a frame transaction that can finish or roll back.
@MainActor
public final class ViewGraphFrame {
    /// Captures a dirty node's state at the start of a frame.
    public struct DirtyNode {
        /// The dirty mounted node.
        public let node: MountedNode
        /// The flags produced directly by the node before the frame.
        public let localDirtyFlags: DirtyFlags
        /// The flags aggregated into the node before the frame.
        public let dirtyFlags: DirtyFlags
        /// The node's frame before the frame transaction.
        public let oldFrame: CellRect?
        /// The node's paint bounds before the frame transaction.
        public let oldPaintBounds: CellRect

        fileprivate let generation: UInt64
    }

    /// The nodes currently captured as dirty for this frame.
    public fileprivate(set) var dirtyNodes: [DirtyNode]
    fileprivate weak var graph: ViewGraph?
    fileprivate let snapshot: CommitSnapshot
    fileprivate var isConsumed = false

    fileprivate init(graph: ViewGraph, snapshot: CommitSnapshot, dirtyNodes: [DirtyNode]) {
        self.graph = graph
        self.snapshot = snapshot
        self.dirtyNodes = dirtyNodes
    }
}

/// Contains the result of sampling mounted node attributes.
@MainActor
public struct MountedNodeAttributeSamplingResult {
    /// The number of attributes that require further sampling.
    public let activeCount: Int
    let frameDemand: MountedFrameDemand?
    /// Actions to run after the sampled changes are accepted.
    public let completionActions: [MountedNodeAttributeAction]
}

/// Reconciles declarative descriptors into a mounted node tree.
@MainActor
public final class ViewGraph {
    /// Handles invalidation with a node and dirty flags.
    public typealias InvalidationHandler = @MainActor (_ node: MountedNode, _ flags: DirtyFlags) -> Void
    /// Handles invalidation with a node, dirty flags, and transaction context.
    public typealias InvalidationContextHandler =
        @MainActor (
            _ node: MountedNode,
            _ flags: DirtyFlags,
            _ context: (any Sendable)?
        ) -> Void

    /// The active mounted root.
    public private(set) var root: MountedNode?
    /// Roots retained only for presentation transitions.
    public private(set) var presentationRoots: [MountedNode]
    /// The revision incremented after each completed commit.
    public private(set) var revision: UInt64
    /// The environment used to expand the graph.
    public private(set) var environment: EnvironmentValues
    /// A callback invoked when a mounted node is invalidated.
    public var invalidationHandler: InvalidationHandler?
    /// A callback invoked with invalidation transaction context.
    public var invalidationContextHandler: InvalidationContextHandler?

    private var nextNodeID: UInt64
    private var activeNodes: [NodeID: MountedNode]
    private var activeCommit: ViewGraphCommit?
    private var activeFrame: ViewGraphFrame?
    private var isRunningLifecycle: Bool
    private var isRestoringSnapshot: Bool

    /// Creates an empty view graph.
    public init(invalidationHandler: InvalidationHandler? = nil) {
        root = nil
        presentationRoots = []
        revision = 0
        environment = EnvironmentValues()
        self.invalidationHandler = invalidationHandler
        nextNodeID = 1
        activeNodes = [:]
        activeCommit = nil
        activeFrame = nil
        isRunningLifecycle = false
        isRestoringSnapshot = false
    }

    /// Prepares a reconciliation plan for an optional root descriptor.
    public func prepare(_ descriptor: NodeDescriptor?) throws -> ReconciliationPlan {
        guard activeCommit == nil, activeFrame == nil else {
            throw ReconciliationPlanError.reentrantCommit
        }
        var counts = PlanCounts()
        var claimedPresentationNodes: Set<NodeID> = []
        let expandedDescriptor = try descriptor.map { descriptor in
            let existingRoot = root?.identity == descriptor.identity ? root : nil
            return try expand(descriptor, reusing: existingRoot, environment: environment)
        }
        let normalizedDescriptor = try expandedDescriptor.map(normalize)

        let plannedRoot: PlannedNode?
        let removedRoot: MountedNode?
        switch (normalizedDescriptor, root) {
        case let (.some(descriptor), .some(root)) where descriptor.identity == root.identity:
            plannedRoot = plan(
                descriptor,
                reusing: root,
                presentationParentID: nil,
                canReusePresentation: false,
                claimedPresentationNodes: &claimedPresentationNodes,
                counts: &counts
            )
            removedRoot = nil
        case let (.some(descriptor), .some(root)):
            plannedRoot = plan(
                descriptor,
                reusing: nil,
                presentationParentID: nil,
                canReusePresentation: true,
                claimedPresentationNodes: &claimedPresentationNodes,
                counts: &counts
            )
            removedRoot = root
            counts.removals += root.subtreeCount
        case let (.some(descriptor), .none):
            plannedRoot = plan(
                descriptor,
                reusing: nil,
                presentationParentID: nil,
                canReusePresentation: true,
                claimedPresentationNodes: &claimedPresentationNodes,
                counts: &counts
            )
            removedRoot = nil
        case let (.none, .some(root)):
            plannedRoot = nil
            removedRoot = root
            counts.removals += root.subtreeCount
        case (.none, .none):
            plannedRoot = nil
            removedRoot = nil
        }

        return ReconciliationPlan(
            graph: self,
            revision: revision,
            root: plannedRoot,
            removedRoot: removedRoot,
            counts: counts
        )
    }

    /// Prepares a reconciliation plan for a declarative root view.
    public func prepare<V: View>(_ view: V) throws -> ReconciliationPlan {
        let descriptors = buildViewGraph { view }
        precondition(descriptors.count <= 1, "A view graph must have at most one root descriptor.")
        return try prepare(descriptors.first)
    }

    /// Sets an environment value and optionally invalidates dependent nodes.
    public func setEnvironment<Key: EnvironmentKey>(
        _ value: Key.Value,
        for key: Key.Type,
        invalidatesDependents: Bool = true
    ) {
        guard environment[key] != value else { return }
        environment[key] = value
        guard invalidatesDependents else { return }
        let dependency = EnvironmentDependencyKey(key)
        for node in activeNodes.values where node.environmentDependencies.contains(dependency) {
            invalidate(node, flags: .structure)
        }
    }

    /// Samples mounted attributes and immediately runs completion actions.
    @discardableResult
    public func sampleMountedAttributes(at instant: TimeInstant) -> Int {
        let result = sampleMountedAttributesDeferringCompletions(at: instant)
        for action in result.completionActions {
            action()
        }
        return result.activeCount
    }

    /// Samples mounted attributes and returns deferred completion actions.
    public func sampleMountedAttributesDeferringCompletions(
        at instant: TimeInstant
    ) -> MountedNodeAttributeSamplingResult {
        let activeRoots = root.map { [$0] } ?? []
        return sampleMountedAttributesDeferringCompletions(
            at: instant,
            roots: activeRoots + presentationRoots
        )
    }

    func sampleMountedAttributesDeferringCompletions(
        at instant: TimeInstant,
        roots: [MountedNode]
    ) -> MountedNodeAttributeSamplingResult {
        var sampledNodeIDs: Set<NodeID> = []
        var activeCount = 0
        var frameDemand: MountedFrameDemand?
        var completionActions: [MountedNodeAttributeAction] = []
        for node in roots {
            activeCount += sampleMountedAttributes(
                in: node,
                at: instant,
                sampledNodeIDs: &sampledNodeIDs,
                frameDemand: &frameDemand,
                completionActions: &completionActions
            )
        }
        return MountedNodeAttributeSamplingResult(
            activeCount: activeCount,
            frameDemand: frameDemand,
            completionActions: completionActions
        )
    }

    /// Applies and finishes a reconciliation plan.
    public func commit(_ plan: ReconciliationPlan) throws {
        let commit = try beginCommit(plan)
        try finishCommit(commit)
    }

    /// Applies a plan and starts a commit transaction.
    public func beginCommit(_ plan: ReconciliationPlan) throws -> ViewGraphCommit {
        guard let planGraph = plan.graph else {
            throw ReconciliationPlanError.graphDeallocated
        }
        guard planGraph === self else {
            throw ReconciliationPlanError.wrongGraph
        }
        guard isRunningLifecycle == false else {
            throw ReconciliationPlanError.reentrantCommit
        }
        guard activeCommit == nil, activeFrame == nil else {
            throw ReconciliationPlanError.reentrantCommit
        }
        guard plan.isConsumed == false else {
            throw ReconciliationPlanError.consumed
        }
        guard plan.revision == revision else {
            throw ReconciliationPlanError.stale
        }

        let snapshot = makeCommitSnapshot()
        for nodeSnapshot in snapshot.nodes {
            nodeSnapshot.node.prepareMetadataForFrame()
        }
        var lifecycleEvents: [LifecycleEvent] = []
        var attributeEvents: [AttributeEvent] = []
        var removedNodes: [MountedNode] = []
        let reclaimedNodeIDs = Set(plan.root?.reclaimedPresentationRoots.map(\.id) ?? [])
        presentationRoots.removeAll { reclaimedNodeIDs.contains($0.id) }
        let newRoot = plan.root.map {
            apply(
                $0,
                parent: nil,
                removedNodes: &removedNodes,
                lifecycleEvents: &lifecycleEvents,
                attributeEvents: &attributeEvents
            )
        }

        if let removedRoot = plan.removedRoot {
            removedNodes.append(removedRoot)
        }
        for removedNode in removedNodes {
            let retirement = retire(
                removedNode,
                lifecycleEvents: &lifecycleEvents,
                attributeEvents: &attributeEvents
            )
            presentationRoots.append(contentsOf: retirement.presentationRoots)
            if let retainedNode = retirement.retainedNode {
                presentationRoots.append(retainedNode)
            }
        }

        root = newRoot
        rebuildActiveNodeIndex()
        var completionActions: [MountedNodeAttributeAction] = []
        for event in attributeEvents {
            completionActions.append(contentsOf: event.run())
        }
        plan.isConsumed = true
        plan.root = nil
        plan.removedRoot = nil

        let previousNodeIDs = Set(snapshot.nodes.map { $0.node.id })
        let createdNodes = allMountedNodes().filter { previousNodeIDs.contains($0.id) == false }
        let commit = ViewGraphCommit(
            graph: self,
            snapshot: snapshot,
            createdNodes: createdNodes,
            lifecycleEvents: lifecycleEvents,
            completionActions: completionActions
        )
        activeCommit = commit
        return commit
    }

    /// Finishes a commit and runs its completion actions.
    public func finishCommit(_ commit: ViewGraphCommit) throws {
        let actions = try finishCommitDeferringCompletions(commit)
        for action in actions {
            action()
        }
    }

    /// Finishes a commit and returns its deferred completion actions.
    public func finishCommitDeferringCompletions(
        _ commit: ViewGraphCommit
    ) throws -> [MountedNodeAttributeAction] {
        try validate(commit)
        revision &+= 1
        activeCommit = nil
        commit.isConsumed = true

        isRunningLifecycle = true
        defer { isRunningLifecycle = false }
        for event in commit.lifecycleEvents {
            event.run()
        }
        commit.lifecycleEvents = []
        let completionActions = commit.completionActions
        commit.completionActions = []
        return completionActions
    }

    /// Restores the graph state from before a commit transaction.
    public func rollbackCommit(_ commit: ViewGraphCommit) throws {
        try validate(commit)

        isRestoringSnapshot = true
        defer { isRestoringSnapshot = false }
        for node in commit.createdNodes {
            node.graph = nil
            node.parent = nil
            node.children = []
        }
        for nodeSnapshot in commit.snapshot.nodes {
            nodeSnapshot.node.restore(nodeSnapshot.snapshot, graph: self)
        }
        root = commit.snapshot.root
        presentationRoots = commit.snapshot.presentationRoots
        nextNodeID = commit.snapshot.nextNodeID
        rebuildActiveNodeIndex()

        activeCommit = nil
        commit.isConsumed = true
        commit.lifecycleEvents = []
        commit.completionActions = []
    }

    /// Consumes a plan without applying it.
    public func discard(_ plan: ReconciliationPlan) throws {
        guard let planGraph = plan.graph else {
            throw ReconciliationPlanError.graphDeallocated
        }
        guard planGraph === self else {
            throw ReconciliationPlanError.wrongGraph
        }
        guard plan.isConsumed == false else {
            throw ReconciliationPlanError.consumed
        }
        plan.isConsumed = true
        plan.root = nil
        plan.removedRoot = nil
    }

    /// Starts a frame transaction for all mounted nodes.
    public func beginFrame() throws -> ViewGraphFrame {
        try beginFrame(nodes: allMountedNodes())
    }

    func beginFrame(nodes: [MountedNode]) throws -> ViewGraphFrame {
        guard activeCommit == nil, activeFrame == nil, isRunningLifecycle == false else {
            throw ReconciliationPlanError.reentrantCommit
        }
        let snapshot = makeCommitSnapshot(nodes: nodes)
        let dirtyNodes = snapshot.nodes.compactMap { nodeSnapshot -> ViewGraphFrame.DirtyNode? in
            let node = nodeSnapshot.node
            guard node.dirtyFlags.isEmpty == false else { return nil }
            return ViewGraphFrame.DirtyNode(
                node: node,
                localDirtyFlags: node.localDirtyFlags,
                dirtyFlags: node.dirtyFlags,
                oldFrame: node.cachedFrame,
                oldPaintBounds: node.paintBounds,
                generation: node.dirtyGeneration
            )
        }
        for nodeSnapshot in snapshot.nodes {
            nodeSnapshot.node.prepareMetadataForFrame()
        }
        let frame = ViewGraphFrame(graph: self, snapshot: snapshot, dirtyNodes: dirtyNodes)
        activeFrame = frame
        return frame
    }

    /// Finishes a frame and clears unchanged dirty state.
    public func finishFrame(_ frame: ViewGraphFrame) throws {
        try validate(frame)
        for dirtyNode in frame.dirtyNodes where dirtyNode.node.dirtyGeneration == dirtyNode.generation {
            dirtyNode.node.localDirtyFlags.subtract(dirtyNode.localDirtyFlags)
            dirtyNode.node.dirtyFlags.subtract(dirtyNode.dirtyFlags)
        }
        activeFrame = nil
        frame.isConsumed = true
    }

    /// Replaces a frame's dirty-node capture with the current dirty state.
    public func captureDirtyState(for frame: ViewGraphFrame) throws {
        try validate(frame)
        let oldGeometry = Dictionary(
            uniqueKeysWithValues: frame.snapshot.nodes.map {
                ($0.node.id, ($0.snapshot.cachedFrame, $0.snapshot.paintBounds))
            }
        )
        frame.dirtyNodes = allMountedNodes().compactMap { node in
            guard node.dirtyFlags.isEmpty == false else { return nil }
            let geometry = oldGeometry[node.id]
            return ViewGraphFrame.DirtyNode(
                node: node,
                localDirtyFlags: node.localDirtyFlags,
                dirtyFlags: node.dirtyFlags,
                oldFrame: geometry?.0 ?? node.cachedFrame,
                oldPaintBounds: geometry?.1 ?? node.paintBounds,
                generation: node.dirtyGeneration
            )
        }
    }

    func captureDirtyState(for frame: ViewGraphFrame, nodes: [MountedNode]) throws {
        try validate(frame)
        let oldGeometry = Dictionary(
            uniqueKeysWithValues: frame.snapshot.nodes.map {
                ($0.node.id, ($0.snapshot.cachedFrame, $0.snapshot.paintBounds))
            }
        )
        frame.dirtyNodes = nodes.compactMap { node in
            guard node.dirtyFlags.isEmpty == false else { return nil }
            let geometry = oldGeometry[node.id]
            return ViewGraphFrame.DirtyNode(
                node: node,
                localDirtyFlags: node.localDirtyFlags,
                dirtyFlags: node.dirtyFlags,
                oldFrame: geometry?.0 ?? node.cachedFrame,
                oldPaintBounds: geometry?.1 ?? node.paintBounds,
                generation: node.dirtyGeneration
            )
        }
    }

    /// Restores the graph state from before a frame transaction.
    public func rollbackFrame(_ frame: ViewGraphFrame) throws {
        try validate(frame)
        isRestoringSnapshot = true
        defer { isRestoringSnapshot = false }
        for nodeSnapshot in frame.snapshot.nodes {
            nodeSnapshot.node.restore(nodeSnapshot.snapshot, graph: self)
        }
        root = frame.snapshot.root
        presentationRoots = frame.snapshot.presentationRoots
        nextNodeID = frame.snapshot.nextNodeID
        rebuildActiveNodeIndex()
        activeFrame = nil
        frame.isConsumed = true
    }

    /// Returns the active node with an identifier.
    public func node(withID id: NodeID) -> MountedNode? {
        activeNodes[id]
    }

    /// Returns a retained presentation node with an identifier.
    public func presentationNode(withID id: NodeID) -> MountedNode? {
        for root in presentationRoots {
            if let match = root.firstNode(withID: id) {
                return match
            }
        }
        return nil
    }

    /// Completes the current presentation transition for a node.
    @discardableResult
    public func completeTransition(for id: NodeID) -> Bool {
        guard let node = node(withID: id) ?? presentationNode(withID: id) else { return false }
        return completeTransition(for: id, token: node.currentPresentationTransitionToken)
    }

    /// Completes a node's presentation transition if the token is current.
    @discardableResult
    public func completeTransition(for id: NodeID, token: PresentationTransitionToken) -> Bool {
        guard token.nodeID == id else { return false }
        if let node = activeNodes[id] {
            return node.completePresentationTransitionIfCurrent(token)
        }
        if let index = presentationRoots.firstIndex(where: { $0.id == id }) {
            let node = presentationRoots[index]
            guard node.presentationPhase == .removing,
                node.currentPresentationTransitionToken == token
            else { return false }
            presentationRoots.remove(at: index)
            node.detachFromGraph()
            return true
        }

        for root in presentationRoots {
            if let node = root.firstNode(withID: id),
                node.presentationPhase == .removing,
                node.currentPresentationTransitionToken == token,
                let node = root.removePresentationDescendant(withID: id)
            {
                node.detachFromGraph()
                return true
            }
        }
        return false
    }

    /// Invalidates an active node with the specified dirty flags.
    public func invalidate(_ id: NodeID, flags: DirtyFlags) {
        guard let node = activeNodes[id] else { return }
        invalidate(node, flags: flags)
    }

    /// Clears dirty flags in the active tree and optionally presentation trees.
    public func clearDirtyFlags(includingPresentation: Bool = false) {
        root?.clearDirtySubtree()
        if includingPresentation {
            for root in presentationRoots {
                root.clearDirtySubtree()
            }
        }
    }

    /// Returns active nodes that can receive focus.
    ///
    /// - Complexity: O(*n* x *h*) for *n* nodes with maximum ancestor depth *h*.
    public func focusableNodes() -> [MountedNode] {
        root?.activeDepthFirstNodes.filter(\.isFocusable) ?? []
    }

    /// Returns the frontmost active node that accepts a point.
    public func hitTest(_ point: CellPoint) -> MountedNode? {
        root?.hitTest(point)
    }

    func invalidate(_ node: MountedNode, flags: DirtyFlags) {
        guard flags.isEmpty == false, node.graph === self else { return }
        if isRestoringSnapshot == false {
            invalidationHandler?(node, flags)
            invalidationContextHandler?(node, flags, ViewInvalidationContext.transaction)
        }
        node.markDirty(flags)
        var current = node.parent
        while let target = current {
            target.markAggregateDirty(flags)
            current = target.parent
        }
    }

    private func normalize(_ descriptor: NodeDescriptor) throws -> NodeDescriptor {
        var descriptor = descriptor
        var firstIndexes: [StructuralIdentity: Int] = [:]
        var children: [NodeDescriptor] = []
        children.reserveCapacity(descriptor.children.count)

        for (index, child) in descriptor.children.enumerated() {
            let indexedChild = child.atIndex(index)
            if let firstIndex = firstIndexes[indexedChild.identity] {
                throw DuplicateIdentityDiagnostic(
                    parent: descriptor.identity,
                    identity: indexedChild.identity,
                    firstIndex: firstIndex,
                    duplicateIndex: index
                )
            }
            firstIndexes[indexedChild.identity] = index
            children.append(try normalize(indexedChild))
        }
        descriptor.children = children
        return descriptor
    }

    private func expand(
        _ input: NodeDescriptor,
        reusing existingNode: MountedNode?,
        environment inheritedEnvironment: EnvironmentValues
    ) throws -> NodeDescriptor {
        var descriptor = input
        if let scope = descriptor.expansionScope {
            var unscopedDescriptor = descriptor
            unscopedDescriptor.expansionScope = nil
            return try scope(existingNode) {
                try expand(unscopedDescriptor, reusing: existingNode, environment: inheritedEnvironment)
            }
        }
        var childEnvironment = inheritedEnvironment
        descriptor.environmentTransform?(&childEnvironment)
        descriptor.effectiveEnvironment = childEnvironment

        if let evaluate = descriptor.bodyEvaluator {
            let context = BodyEvaluationContext(
                identity: descriptor.identity,
                existingNode: existingNode,
                environment: childEnvironment
            )
            descriptor.children = evaluate(context)
            if let mutation = context.mutation {
                throw mutation
            }
            descriptor.environmentDependencies = context.environmentDependencies
            descriptor.preferenceDependencies = context.preferenceDependencies
            descriptor.evaluatedDynamicPropertyValues = context.values
            descriptor.dynamicPropertyLocations = context.locations
            descriptor.observationToken = context.observationToken
        }

        var availableChildren: [StructuralIdentity: MountedNode] = [:]
        if let existingNode {
            for child in existingNode.children {
                availableChildren[child.identity] = child
            }
        }
        var resolvedPreferences = descriptor.emittedPreferences
        descriptor.children = try descriptor.children.enumerated().map { index, child in
            let indexedChild = child.atIndex(index)
            let existingChild = availableChildren[indexedChild.identity]
            let expandedChild = try expand(indexedChild, reusing: existingChild, environment: childEnvironment)
            resolvedPreferences.reduce(expandedChild.resolvedPreferences)
            return expandedChild
        }
        descriptor.resolvedPreferences = resolvedPreferences
        return descriptor
    }

    private func sampleMountedAttributes(
        in node: MountedNode,
        at instant: TimeInstant,
        sampledNodeIDs: inout Set<NodeID>,
        frameDemand: inout MountedFrameDemand?,
        completionActions: inout [MountedNodeAttributeAction]
    ) -> Int {
        guard sampledNodeIDs.insert(node.id).inserted else { return 0 }
        var activeCount = 0
        for attribute in node.mountedNodeAttributes.values {
            let sample = attribute.sample(on: node, at: instant)
            if let attribute = attribute as? any MountedFrameDemandAttribute,
                let demand = attribute.frameDemand(after: instant)
            {
                frameDemand = frameDemand?.merging(demand) ?? demand
            }
            completionActions.append(contentsOf: sample.completionActions)
            if sample.isActive { activeCount += 1 }
            if sample.dirtyFlags.isEmpty == false {
                node.markDirty(sample.dirtyFlags)
                var current = node.parent
                while let target = current {
                    target.markAggregateDirty(sample.dirtyFlags)
                    current = target.parent
                }
            }
        }
        for child in node.children {
            activeCount += sampleMountedAttributes(
                in: child,
                at: instant,
                sampledNodeIDs: &sampledNodeIDs,
                frameDemand: &frameDemand,
                completionActions: &completionActions
            )
        }
        return activeCount
    }

    func requiresStructureSampling(at instant: TimeInstant) -> Bool {
        var pending = presentationRoots
        if let root {
            pending.append(root)
        }
        while let node = pending.popLast() {
            if node.mountedNodeAttributes.values.contains(where: { attribute in
                (attribute as? any MountedStructureSamplingAttribute)?
                    .requiresStructureSampling(on: node, at: instant) == true
            }) {
                return true
            }
            pending.append(contentsOf: node.children)
        }
        return false
    }

    private func plan(
        _ descriptor: NodeDescriptor,
        reusing activeNode: MountedNode?,
        presentationParentID: NodeID?,
        canReusePresentation: Bool,
        claimedPresentationNodes: inout Set<NodeID>,
        counts: inout PlanCounts
    ) -> PlannedNode {
        let presentationNode =
            activeNode == nil && canReusePresentation
            ? reusablePresentationNode(
                matching: descriptor.identity,
                parentID: presentationParentID,
                excluding: claimedPresentationNodes
            )
            : nil
        if let presentationNode {
            claimedPresentationNodes.insert(presentationNode.id)
        }
        let existing = activeNode ?? presentationNode

        if existing == nil {
            counts.insertions += 1
        } else {
            counts.updates += 1
        }

        var availableChildren: [StructuralIdentity: MountedNode] = [:]
        if let existing {
            for child in existing.children {
                availableChildren[child.identity] = child
            }
        }

        var children: [PlannedNode] = []
        children.reserveCapacity(descriptor.children.count)
        for childDescriptor in descriptor.children {
            let matchedNode = availableChildren.removeValue(forKey: childDescriptor.identity)
            children.append(
                plan(
                    childDescriptor,
                    reusing: matchedNode,
                    presentationParentID: existing?.id,
                    canReusePresentation: existing != nil,
                    claimedPresentationNodes: &claimedPresentationNodes,
                    counts: &counts
                )
            )
        }

        let removedChildren = existing?.children.filter { availableChildren[$0.identity] != nil } ?? []
        for child in removedChildren {
            counts.removals += child.subtreeCount
        }
        return PlannedNode(
            descriptor: descriptor,
            existing: existing,
            reclaimedPresentationRoot: presentationNode,
            children: children,
            removedChildren: removedChildren
        )
    }

    private func reusablePresentationNode(
        matching identity: StructuralIdentity,
        parentID: NodeID?,
        excluding claimedNodes: Set<NodeID>
    ) -> MountedNode? {
        let matches = presentationRoots.filter {
            $0.identity == identity
                && $0.presentationParentID == parentID
                && claimedNodes.contains($0.id) == false
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func apply(
        _ plannedNode: PlannedNode,
        parent: MountedNode?,
        removedNodes: inout [MountedNode],
        lifecycleEvents: inout [LifecycleEvent],
        attributeEvents: inout [AttributeEvent]
    ) -> MountedNode {
        let node: MountedNode
        let oldChildIDs: [NodeID]
        if let existing = plannedNode.existing {
            node = existing
            oldChildIDs = existing.children.map(\.id)
            let previousAttributes = existing.mountedNodeAttributes
            node.apply(plannedNode.descriptor)
            if plannedNode.reclaimedPresentationRoot != nil {
                node.reclaimFromPresentation()
            }
            node.markDirty(plannedNode.descriptor.dirtyOnUpdate)
            attributeEvents.append(
                AttributeEvent(
                    node,
                    previous: plannedNode.reclaimedPresentationRoot == nil ? previousAttributes : [:],
                    current: node.mountedNodeAttributes
                )
            )
            lifecycleEvents.append(.update(node, plannedNode.descriptor.lifecycle.onUpdate))
        } else {
            node = MountedNode(id: allocateNodeID(), descriptor: plannedNode.descriptor, graph: self)
            oldChildIDs = []
            attributeEvents.append(AttributeEvent(node, previous: [:], current: node.mountedNodeAttributes))
            lifecycleEvents.append(.mount(node, plannedNode.descriptor.lifecycle.onMount))
        }
        node.parent = parent
        node.graph = self

        for removedChild in plannedNode.removedChildren {
            guard let index = oldChildIDs.firstIndex(of: removedChild.id) else { continue }
            removedChild.retainPresentationPlacement(
                PresentationPlacement(
                    parentID: node.id,
                    siblingIndex: index,
                    previousSiblingID: index > 0 ? oldChildIDs[index - 1] : nil,
                    nextSiblingID: index + 1 < oldChildIDs.count ? oldChildIDs[index + 1] : nil
                )
            )
        }

        let children = plannedNode.children.map {
            apply(
                $0,
                parent: node,
                removedNodes: &removedNodes,
                lifecycleEvents: &lifecycleEvents,
                attributeEvents: &attributeEvents
            )
        }
        node.children = children
        let newChildIDs = children.map(\.id)
        if oldChildIDs != newChildIDs || plannedNode.removedChildren.isEmpty == false {
            node.markDirty(.structure)
        }
        removedNodes.append(contentsOf: plannedNode.removedChildren)
        return node
    }

    private func retire(
        _ node: MountedNode,
        lifecycleEvents: inout [LifecycleEvent],
        attributeEvents: inout [AttributeEvent]
    ) -> Retirement {
        let wasPresentationOnly = node.isPresentationOnly
        let parent = node.parent
        let presentationParentID = parent?.id
        let siblings = parent?.children ?? [node]
        let siblingIndex = siblings.firstIndex(where: { $0 === node }) ?? 0
        let placement =
            node.presentationPlacement
            ?? PresentationPlacement(
                parentID: presentationParentID,
                siblingIndex: siblingIndex,
                previousSiblingID: siblingIndex > 0 ? siblings[siblingIndex - 1].id : nil,
                nextSiblingID: siblingIndex + 1 < siblings.count ? siblings[siblingIndex + 1].id : nil
            )
        let childRetirements = node.children.map {
            retire($0, lifecycleEvents: &lifecycleEvents, attributeEvents: &attributeEvents)
        }
        var presentationRoots = childRetirements.flatMap(\.presentationRoots)
        let retainedChildren = childRetirements.compactMap(\.retainedNode)
        node.children = []
        node.parent = nil
        if wasPresentationOnly == false {
            attributeEvents.append(AttributeEvent(node, previous: node.mountedNodeAttributes, current: [:]))
            lifecycleEvents.append(.remove(node, node.lifecycle.onRemove))
        }
        switch node.removalPolicy {
        case .immediate:
            node.detachFromGraph()
            for child in retainedChildren {
                child.parent = nil
                presentationRoots.append(child)
            }
            return Retirement(retainedNode: nil, presentationRoots: presentationRoots)
        case .retainForTransition:
            node.children = retainedChildren
            for child in retainedChildren {
                child.parent = node
            }
            node.presentationParentID = presentationParentID
            node.prepareForRemoval(placement: placement)
            node.markPresentationOnly()
            return Retirement(retainedNode: node, presentationRoots: presentationRoots)
        }
    }

    private func allocateNodeID() -> NodeID {
        precondition(nextNodeID != 0, "The view graph exhausted its node identifier space.")
        defer { nextNodeID &+= 1 }
        return NodeID(rawValue: nextNodeID)
    }

    private func rebuildActiveNodeIndex() {
        activeNodes.removeAll(keepingCapacity: true)
        guard let root else { return }
        for node in root.activeDepthFirstNodes {
            activeNodes[node.id] = node
        }
    }

    private func validate(_ commit: ViewGraphCommit) throws {
        guard let commitGraph = commit.graph else {
            throw ReconciliationPlanError.graphDeallocated
        }
        guard commitGraph === self else {
            throw ReconciliationPlanError.wrongGraph
        }
        guard commit.isConsumed == false else {
            throw ReconciliationPlanError.consumed
        }
        guard activeCommit === commit else {
            throw ReconciliationPlanError.stale
        }
    }

    private func validate(_ frame: ViewGraphFrame) throws {
        guard let frameGraph = frame.graph else {
            throw ReconciliationPlanError.graphDeallocated
        }
        guard frameGraph === self else {
            throw ReconciliationPlanError.wrongGraph
        }
        guard frame.isConsumed == false else {
            throw ReconciliationPlanError.consumed
        }
        guard activeFrame === frame else {
            throw ReconciliationPlanError.stale
        }
    }

    private func makeCommitSnapshot() -> CommitSnapshot {
        makeCommitSnapshot(nodes: allMountedNodes())
    }

    private func makeCommitSnapshot(nodes: [MountedNode]) -> CommitSnapshot {
        CommitSnapshot(
            root: root,
            presentationRoots: presentationRoots,
            nextNodeID: nextNodeID,
            nodes: nodes.map { CommitNodeSnapshot(node: $0, snapshot: $0.makeSnapshot()) }
        )
    }

    private func allMountedNodes() -> [MountedNode] {
        var seen: Set<NodeID> = []
        var nodes: [MountedNode] = []
        for root in [root].compactMap({ $0 }) + presentationRoots {
            for node in root.depthFirstNodes where seen.insert(node.id).inserted {
                nodes.append(node)
            }
        }
        return nodes
    }
}

@MainActor
private struct CommitSnapshot {
    let root: MountedNode?
    let presentationRoots: [MountedNode]
    let nextNodeID: UInt64
    let nodes: [CommitNodeSnapshot]
}

@MainActor
private struct CommitNodeSnapshot {
    let node: MountedNode
    let snapshot: MountedNode.Snapshot
}

private struct PlanCounts {
    var insertions = 0
    var updates = 0
    var removals = 0
}

@MainActor
private struct Retirement {
    let retainedNode: MountedNode?
    let presentationRoots: [MountedNode]
}

@MainActor
private final class PlannedNode {
    let descriptor: NodeDescriptor
    let existing: MountedNode?
    let reclaimedPresentationRoot: MountedNode?
    let children: [PlannedNode]
    let removedChildren: [MountedNode]

    init(
        descriptor: NodeDescriptor,
        existing: MountedNode?,
        reclaimedPresentationRoot: MountedNode?,
        children: [PlannedNode],
        removedChildren: [MountedNode]
    ) {
        self.descriptor = descriptor
        self.existing = existing
        self.reclaimedPresentationRoot = reclaimedPresentationRoot
        self.children = children
        self.removedChildren = removedChildren
    }

    var reclaimedPresentationRoots: [MountedNode] {
        (reclaimedPresentationRoot.map { [$0] } ?? []) + children.flatMap(\.reclaimedPresentationRoots)
    }
}

@MainActor
private enum LifecycleEvent {
    case mount(MountedNode, NodeLifecycle.Handler?)
    case update(MountedNode, NodeLifecycle.Handler?)
    case remove(MountedNode, NodeLifecycle.Handler?)
    func run() {
        switch self {
        case let (.mount(node, handler)), let (.update(node, handler)), let (.remove(node, handler)):
            handler?(node)
        }
    }
}

@MainActor
private struct AttributeEvent {
    let node: MountedNode
    let previous: [AnyHashable: any MountedNodeAttribute]
    let current: [AnyHashable: any MountedNodeAttribute]

    init(
        _ node: MountedNode,
        previous: [AnyHashable: any MountedNodeAttribute],
        current: [AnyHashable: any MountedNodeAttribute]
    ) {
        self.node = node
        self.previous = previous
        self.current = current
    }

    func run() -> [MountedNodeAttributeAction] {
        var actions: [MountedNodeAttributeAction] = []
        for (id, attribute) in previous where current[id] == nil {
            actions.append(contentsOf: attribute.remove(from: node))
        }
        for (id, attribute) in current {
            actions.append(contentsOf: attribute.apply(to: node, replacing: previous[id]))
            node.markDirty(attribute.stagedDirtyFlags)
            var currentNode = node.parent
            while let target = currentNode {
                target.markAggregateDirty(attribute.stagedDirtyFlags)
                currentNode = target.parent
            }
        }
        return actions
    }
}

@MainActor
extension MountedNode {
    fileprivate var subtreeCount: Int {
        1 + children.reduce(0) { $0 + $1.subtreeCount }
    }

    fileprivate var activeDepthFirstNodes: [MountedNode] {
        [self] + children.flatMap(\.activeDepthFirstNodes)
    }

    fileprivate var depthFirstNodes: [MountedNode] {
        [self] + children.flatMap(\.depthFirstNodes)
    }

    fileprivate func firstNode(withID id: NodeID) -> MountedNode? {
        if self.id == id { return self }
        for child in children {
            if let match = child.firstNode(withID: id) {
                return match
            }
        }
        return nil
    }

    fileprivate func removePresentationDescendant(withID id: NodeID) -> MountedNode? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: index)
        }
        for child in children {
            if let match = child.removePresentationDescendant(withID: id) {
                return match
            }
        }
        return nil
    }

    fileprivate func clearDirtySubtree() {
        localDirtyFlags = []
        dirtyFlags = []
        for child in children {
            child.clearDirtySubtree()
        }
    }

    fileprivate func hitTest(_ point: CellPoint) -> MountedNode? {
        let orderedChildren = children.enumerated().sorted {
            let lhs = ($0.element.hitTestMetadata.zIndex, $0.offset)
            let rhs = ($1.element.hitTestMetadata.zIndex, $1.offset)
            return lhs > rhs
        }
        for (_, child) in orderedChildren {
            if let match = child.hitTest(point) {
                return match
            }
        }
        guard acceptsHitTesting else { return nil }
        let bounds = paintBounds.isEmpty ? cachedFrame : paintBounds
        return bounds?.contains(point) == true ? self : nil
    }
}
