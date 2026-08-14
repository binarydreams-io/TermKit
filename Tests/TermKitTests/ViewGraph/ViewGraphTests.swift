@testable import TermKit
import Testing

@MainActor
struct ViewGraphTests {
  private enum Root {}
  private enum Row {}
  private enum AlternateRow {}
  private enum CounterState {}
  private enum SnapshotMetadata: NodeMetadataKey {
    typealias Value = SnapshotMetadataValue
  }

  private struct Primitive: Equatable, Sendable {
    var text: String
  }

  @Test
  func `structural identity uses position for unkeyed nodes and preserves keyed identity across reorder`() {
    let first = StructuralIdentity(type: Row.self, index: 0)
    let second = StructuralIdentity(type: Row.self, index: 1)
    let keyedFirst = StructuralIdentity(type: Row.self, key: "row", index: 0)
    let keyedSecond = StructuralIdentity(type: Row.self, key: "row", index: 4)

    #expect(first != second)
    #expect(keyedFirst == keyedSecond)
    #expect(keyedFirst != StructuralIdentity(type: Row.self, key: "row", index: 0, branch: 1))
  }

  @Test
  func `nested branch identity preserves the full path`() {
    let first = StructuralIdentity(type: Row.self).inBranch(0).inBranch(31)
    let second = StructuralIdentity(type: Row.self).inBranch(1).inBranch(0)

    #expect(first != second)
    #expect(first.branchPath == [0, 31])
    #expect(second.branchPath == [1, 0])
  }

  @Test
  func `Structural identity diagnostics use the consolidated module name`() {
    let identity = StructuralIdentity(type: Text.self)

    #expect(identity.description == "TermKit.Text(index=0)")
  }

  @Test
  func `keyed reorder preserves nodes and state`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("a"), row("b")])))
    let firstChildren = try #require(graph.root?.children)
    let stateKey = StateKey<Int>(CounterState.self)
    firstChildren[0].setState(42, for: stateKey)
    graph.clearDirtyFlags()

    try graph.commit(graph.prepare(root(children: [row("b"), row("a")])))
    let reordered = try #require(graph.root?.children)

    #expect(reordered.map(\.id) == [firstChildren[1].id, firstChildren[0].id])
    #expect(reordered[1].state(for: stateKey) == 42)
    #expect(graph.root?.dirtyFlags.contains(.structure) == true)
  }

  @Test
  func `state mutation invalidates structure`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("a")])))
    graph.clearDirtyFlags()
    let child = try #require(graph.root?.children.first)
    let stateKey = StateKey<Int>(CounterState.self)

    child.setState(1, for: stateKey)
    #expect(child.dirtyFlags == .structure)
    #expect(graph.root?.dirtyFlags == .structure)

    graph.clearDirtyFlags()
    child.removeState(for: stateKey)
    #expect(child.dirtyFlags == .structure)
    #expect(graph.root?.dirtyFlags == .structure)
  }

  @Test
  func `update replaces primitive while preserving node ID`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(NodeDescriptor(type: Root.self, primitive: Primitive(text: "first"))))
    let root = try #require(graph.root)

    try graph.commit(graph.prepare(NodeDescriptor(type: Root.self, primitive: Primitive(text: "second"))))

    #expect(graph.root?.id == root.id)
    #expect(graph.root?.primitive(as: Primitive.self) == Primitive(text: "second"))
  }

  @Test
  func `rollback restores primitive snapshot`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(NodeDescriptor(type: Root.self, primitive: Primitive(text: "committed"))))
    let root = try #require(graph.root)
    let commit = try graph.beginCommit(
      graph.prepare(
        NodeDescriptor(type: Root.self, primitive: Primitive(text: "staged"))
      )
    )

    #expect(root.primitive(as: Primitive.self) == Primitive(text: "staged"))
    try graph.rollbackCommit(commit)

    #expect(graph.root === root)
    #expect(root.primitive(as: Primitive.self) == Primitive(text: "committed"))
  }

  @Test
  func `rollback restores frame snapshotting metadata reference`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(NodeDescriptor(type: Root.self)))
    let root = try #require(graph.root)
    let committed = SnapshotMetadataValue(value: 1)
    root.setMetadata(committed, for: SnapshotMetadata.self)
    let commit = try graph.beginCommit(graph.prepare(NodeDescriptor(type: Root.self)))
    let staged = try #require(root.metadata(for: SnapshotMetadata.self))

    #expect(staged !== committed)
    staged.value = 2
    try graph.rollbackCommit(commit)

    #expect(root.metadata(for: SnapshotMetadata.self) === committed)
    #expect(committed.value == 1)
  }

  @Test
  func `presentation only removal retains primitive`() throws {
    let graph = ViewGraph()
    let descriptor = NodeDescriptor(
      type: Row.self,
      primitive: Primitive(text: "retained"),
      removalPolicy: .retainForTransition
    )
    try graph.commit(graph.prepare(descriptor))
    let root = try #require(graph.root)

    try graph.commit(graph.prepare(nil))

    #expect(graph.presentationNode(withID: root.id) === root)
    #expect(root.isPresentationOnly)
    #expect(root.primitive(as: Primitive.self) == Primitive(text: "retained"))
  }

  @Test
  func `presentation removal retains deterministic sibling placement`() throws {
    let graph = ViewGraph()
    let retained = NodeDescriptor(
      type: Row.self,
      key: "middle",
      removalPolicy: .retainForTransition
    )
    try graph.commit(graph.prepare(root(children: [row("first"), retained, row("last")])))
    let children = try #require(graph.root?.children)
    let removed = children[1]

    try graph.commit(graph.prepare(root(children: [row("first"), row("last")])))

    #expect(
      removed.presentationPlacement
        == PresentationPlacement(
          parentID: graph.root?.id,
          siblingIndex: 1,
          previousSiblingID: children[0].id,
          nextSiblingID: children[2].id
        )
    )
  }

  @Test
  func `stale removal token cannot delete reclaimed node`() throws {
    let graph = ViewGraph()
    let retained = NodeDescriptor(
      type: Row.self,
      key: "retained",
      removalPolicy: .retainForTransition
    )
    try graph.commit(graph.prepare(root(children: [retained])))
    let node = try #require(graph.root?.children.first)
    try graph.commit(graph.prepare(root(children: [])))
    let removalToken = node.currentPresentationTransitionToken

    try graph.commit(graph.prepare(root(children: [retained])))

    #expect(graph.completeTransition(for: node.id, token: removalToken) == false)
    #expect(graph.node(withID: node.id) === node)
    #expect(node.presentationPhase == .active)
  }

  @Test
  func `invalidation handler receives originating node and flags once`() throws {
    var invalidations: [(MountedNode, DirtyFlags)] = []
    let graph = ViewGraph { node, flags in
      invalidations.append((node, flags))
    }
    try graph.commit(graph.prepare(root(children: [row("origin")])))
    let child = try #require(graph.root?.children.first)
    graph.clearDirtyFlags()

    child.invalidate(.layout)

    #expect(invalidations.count == 1)
    #expect(invalidations.first?.0 === child)
    #expect(invalidations.first?.1 == .layout)
    #expect(graph.root?.dirtyFlags == .layout)
  }

  @Test
  func `changing conditional branch replaces node`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("conditional", branch: 0)])))
    let originalID = try #require(graph.root?.children.first?.id)

    try graph.commit(graph.prepare(root(children: [row("conditional", branch: 1)])))
    let replacementID = try #require(graph.root?.children.first?.id)

    #expect(replacementID != originalID)
    #expect(graph.presentationNode(withID: originalID) == nil)
  }

  @Test
  func `lifecycle runs after commit and not for discarded plan`() throws {
    let graph = ViewGraph()
    var mountedRootVisible = false
    var discardedMountCount = 0
    let descriptor = NodeDescriptor(
      type: Root.self,
      lifecycle: NodeLifecycle(onMount: { node in
        mountedRootVisible = graph.root === node
      })
    )

    let plan = try graph.prepare(descriptor)
    #expect(mountedRootVisible == false)
    try graph.commit(plan)
    #expect(mountedRootVisible)

    let discarded = try graph.prepare(
      NodeDescriptor(
        type: AlternateRow.self,
        lifecycle: NodeLifecycle(onMount: { _ in discardedMountCount += 1 })
      )
    )
    try graph.discard(discarded)
    #expect(discardedMountCount == 0)
    #expect(graph.root?.identity == descriptor.identity)
  }

  @Test
  func `staged commit rolls back graph mutation and lifecycle`() throws {
    let graph = ViewGraph()
    let stateKey = StateKey<Int>(CounterState.self)
    var updateCount = 0
    var mountCount = 0
    var removalCount = 0
    let originalDescriptor = NodeDescriptor(
      type: Row.self,
      key: "a",
      lifecycle: NodeLifecycle(onRemove: { _ in removalCount += 1 })
    )
    try graph.commit(graph.prepare(root(children: [originalDescriptor])))
    let originalRoot = try #require(graph.root)
    let originalChild = try #require(originalRoot.children.first)
    originalRoot.setState(7, for: stateKey)
    originalChild.setState(42, for: stateKey)
    originalChild.cache(
      size: CellSize(width: 4, height: 1),
      frame: CellRect(x: 0, y: 0, width: 4, height: 1)
    )
    graph.clearDirtyFlags()
    let revision = graph.revision
    let descriptor = NodeDescriptor(
      type: Root.self,
      value: "staged",
      children: [
        NodeDescriptor(
          type: AlternateRow.self,
          lifecycle: NodeLifecycle(onMount: { _ in mountCount += 1 })
        )
      ],
      lifecycle: NodeLifecycle(onUpdate: { _ in updateCount += 1 })
    )
    let commit = try graph.beginCommit(graph.prepare(descriptor))
    let stagedRoot = try #require(graph.root)
    let stagedChildID = try #require(stagedRoot.children.first?.id)
    stagedRoot.setState(99, for: stateKey)
    stagedRoot.cache(
      size: CellSize(width: 8, height: 2),
      frame: CellRect(x: 0, y: 0, width: 8, height: 2)
    )
    try graph.rollbackCommit(commit)

    #expect(graph.root === originalRoot)
    #expect(graph.root?.value(as: String.self) == nil)
    #expect(originalRoot.state(for: stateKey) == 7)
    #expect(graph.root?.children.first === originalChild)
    #expect(originalChild.state(for: stateKey) == 42)
    #expect(originalChild.cachedSize == CellSize(width: 4, height: 1))
    #expect(originalChild.cachedFrame == CellRect(x: 0, y: 0, width: 4, height: 1))
    #expect(graph.revision == revision)
    #expect(updateCount == 0)
    #expect(mountCount == 0)
    #expect(removalCount == 0)

    try graph.commit(graph.prepare(descriptor))
    #expect(graph.root?.children.first?.id == stagedChildID)
  }

  @Test
  func `staged commit finalizes revision and lifecycle only on finish`() throws {
    let graph = ViewGraph()
    var mountCount = 0
    let descriptor = NodeDescriptor(
      type: Root.self,
      lifecycle: NodeLifecycle(onMount: { _ in mountCount += 1 })
    )
    let commit = try graph.beginCommit(graph.prepare(descriptor))

    #expect(graph.root?.identity == descriptor.identity)
    #expect(graph.revision == 0)
    #expect(mountCount == 0)

    try graph.finishCommit(commit)

    #expect(graph.revision == 1)
    #expect(mountCount == 1)
  }

  @Test
  func `lifecycle rejects reentrant commit with typed error`() throws {
    let graph = ViewGraph()
    var deferredPlan: ReconciliationPlan?
    var commitError: ReconciliationPlanError?
    let descriptor = NodeDescriptor(
      type: Root.self,
      lifecycle: NodeLifecycle(onMount: { _ in
        do {
          let plan = try graph.prepare(NodeDescriptor(type: AlternateRow.self))
          deferredPlan = plan
          try graph.commit(plan)
        } catch let error as ReconciliationPlanError {
          commitError = error
        } catch {
          Issue.record(error)
        }
      })
    )

    try graph.commit(graph.prepare(descriptor))

    #expect(commitError == .reentrantCommit)
    #expect(graph.root?.identity == descriptor.identity)
    try graph.commit(#require(deferredPlan))
    #expect(graph.root?.identity.type == AlternateRow.self)
  }

  @Test
  func `plan does not outlive its graph unsafely`() throws {
    var graph: ViewGraph? = ViewGraph()
    weak var weakGraph: ViewGraph?
    weakGraph = graph
    let plan = try #require(graph).prepare(NodeDescriptor(type: Root.self))

    graph = nil

    #expect(weakGraph == nil)
    #expect(throws: ReconciliationPlanError.graphDeallocated) {
      try ViewGraph().commit(plan)
    }
  }

  @Test
  func `dirty flags coalesce and propagate to ancestors`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("a")])))
    graph.clearDirtyFlags()
    let child = try #require(graph.root?.children.first)

    child.invalidate(.paint)
    child.invalidate(.layout)
    child.invalidate(.paint)

    #expect(child.dirtyFlags == .layout)
    #expect(graph.root?.dirtyFlags == .layout)
    #expect(child.dirtyFlags.contains(.paint))
  }

  @Test
  func `incremental frame tracks local and aggregate dirty state`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("a")])))
    graph.clearDirtyFlags()
    let root = try #require(graph.root)
    let child = try #require(root.children.first)

    child.invalidate(.paint)

    #expect(child.localDirtyFlags == .paint)
    #expect(child.dirtyFlags == .paint)
    #expect(root.localDirtyFlags.isEmpty)
    #expect(root.dirtyFlags == .paint)
  }

  @Test
  func `incremental frame rolls back geometry metadata and dirty state`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("a")])))
    graph.clearDirtyFlags()
    let child = try #require(graph.root?.children.first)
    let originalMetadata = SnapshotMetadataValue(value: 1)
    child.setMetadata(originalMetadata, for: SnapshotMetadata.self)
    child.cache(size: CellSize(width: 2, height: 1), frame: CellRect(x: 1, y: 1, width: 2, height: 1))
    child.invalidate(.paint)
    let revision = graph.revision
    let frame = try graph.beginFrame()
    let stagedMetadata = try #require(child.metadata(for: SnapshotMetadata.self))
    stagedMetadata.value = 2
    child.cache(size: CellSize(width: 4, height: 1), frame: CellRect(x: 3, y: 2, width: 4, height: 1))

    try graph.rollbackFrame(frame)

    #expect(child.cachedFrame == CellRect(x: 1, y: 1, width: 2, height: 1))
    #expect(child.metadata(for: SnapshotMetadata.self) === originalMetadata)
    #expect(child.localDirtyFlags == .paint)
    #expect(child.dirtyFlags == .paint)
    #expect(graph.revision == revision)
  }

  @Test
  func `incremental frame clears only unchanged dirty generations`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("a")])))
    graph.clearDirtyFlags()
    let child = try #require(graph.root?.children.first)
    child.invalidate(.paint)
    let revision = graph.revision
    let frame = try graph.beginFrame()

    child.invalidate(.layout)
    try graph.finishFrame(frame)

    #expect(child.localDirtyFlags == .layout)
    #expect(child.dirtyFlags == .layout)
    #expect(graph.root?.dirtyFlags == .layout)
    #expect(graph.revision == revision)
  }

  @Test
  func `retained node detaches from focus and hit testing until transition completes`() throws {
    let graph = ViewGraph()
    let interactive = NodeDescriptor(
      type: Row.self,
      key: "interactive",
      focus: FocusMetadata(isFocusable: true),
      hitTest: HitTestMetadata(isEnabled: true),
      removalPolicy: .retainForTransition
    )
    try graph.commit(graph.prepare(root(children: [interactive])))
    let removed = try #require(graph.root?.children.first)
    removed.cache(
      size: CellSize(width: 4, height: 1),
      frame: CellRect(x: 0, y: 0, width: 4, height: 1)
    )
    #expect(graph.focusableNodes().map(\.id) == [removed.id])
    #expect(graph.hitTest(CellPoint(x: 1, y: 0))?.id == removed.id)

    try graph.commit(graph.prepare(root(children: [])))

    #expect(removed.isPresentationOnly)
    #expect(removed.isFocusable == false)
    #expect(removed.acceptsHitTesting == false)
    #expect(graph.focusableNodes().isEmpty)
    #expect(graph.hitTest(CellPoint(x: 1, y: 0)) == nil)
    #expect(graph.presentationNode(withID: removed.id) === removed)
    #expect(graph.completeTransition(for: removed.id))
    #expect(graph.presentationNode(withID: removed.id) == nil)
  }

  @Test
  func `removal detaches immediately by default`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(root(children: [row("removed")])))
    let removed = try #require(graph.root?.children.first)

    try graph.commit(graph.prepare(root(children: [])))

    #expect(removed.isPresentationOnly == false)
    #expect(removed.graph == nil)
    #expect(graph.presentationNode(withID: removed.id) == nil)
    #expect(graph.completeTransition(for: removed.id) == false)
  }

  @Test
  func `retained parent does not retain default children`() throws {
    let graph = ViewGraph()
    let descriptor = NodeDescriptor(
      type: Root.self,
      children: [row("child")],
      removalPolicy: .retainForTransition
    )
    try graph.commit(graph.prepare(descriptor))
    let root = try #require(graph.root)
    let child = try #require(root.children.first)

    try graph.commit(graph.prepare(nil))

    #expect(root.isPresentationOnly)
    #expect(root.children.isEmpty)
    #expect(child.isPresentationOnly == false)
    #expect(child.graph == nil)
    #expect(graph.presentationNode(withID: child.id) == nil)
  }

  @Test
  func `retained node reinsertion preserves identity and state`() throws {
    let graph = ViewGraph()
    let stateKey = StateKey<Int>(CounterState.self)
    let retainedRow = NodeDescriptor(
      type: Row.self,
      key: "retained",
      removalPolicy: .retainForTransition
    )
    try graph.commit(graph.prepare(root(children: [retainedRow])))
    let original = try #require(graph.root?.children.first)
    original.setState(42, for: stateKey)

    try graph.commit(graph.prepare(root(children: [])))
    #expect(graph.presentationNode(withID: original.id) === original)

    try graph.commit(graph.prepare(root(children: [retainedRow])))
    let reinserted = try #require(graph.root?.children.first)

    #expect(reinserted === original)
    #expect(reinserted.id == original.id)
    #expect(reinserted.state(for: stateKey) == 42)
    #expect(reinserted.isPresentationOnly == false)
    #expect(graph.presentationNode(withID: original.id) == nil)
  }

  @Test
  func `duplicate key produces typed diagnostic`() throws {
    let graph = ViewGraph()
    let descriptor = root(children: [row("same"), row("same")])

    #expect(throws: DuplicateIdentityDiagnostic.self) {
      try graph.prepare(descriptor)
    }
  }

  private func root(children: [NodeDescriptor]) -> NodeDescriptor {
    NodeDescriptor(type: Root.self, children: children)
  }

  private func row(_ key: String, branch: Int? = nil) -> NodeDescriptor {
    NodeDescriptor(type: Row.self, key: key, branch: branch)
  }
}

@MainActor
private final class SnapshotMetadataValue: FrameSnapshottingNodeMetadata {
  var value: Int

  init(value: Int) {
    self.value = value
  }

  func makeFrameSnapshotCopy() -> any FrameSnapshottingNodeMetadata {
    SnapshotMetadataValue(value: value)
  }
}
