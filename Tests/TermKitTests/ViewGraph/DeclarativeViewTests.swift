import Observation
@testable import TermKit
import Testing

@MainActor
struct DeclarativeViewTests {
  private enum Leaf {}
  private enum AnimationSlot: NodeMetadataKey {
    typealias Value = String
  }

  @Test
  func `view builder builds values branches optionals and arrays`() {
    let descriptors = buildViewGraph {
      NodeDescriptor(type: Leaf.self, value: 0)
      if true {
        NodeDescriptor(type: Leaf.self, value: 1)
      } else {
        NodeDescriptor(type: Leaf.self, value: 2)
      }
      for value in 3 ... 4 {
        NodeDescriptor(type: Leaf.self, value: value)
      }
    }

    #expect(descriptors.compactMap { $0.value(as: Int.self) } == [0, 1, 3, 4])
    #expect(descriptors[1].identity.branchPath == [0])
  }

  @Test
  func `state retains identity and coalesces rapid updates`() throws {
    let probe = StateProbe()
    let graph = ViewGraph()
    try graph.commit(graph.prepare(CounterView(probe: probe)))
    let original = try #require(graph.root)
    graph.clearDirtyFlags()

    probe.binding?.wrappedValue = 1
    probe.binding?.wrappedValue = 2
    probe.binding?.wrappedValue = 3

    #expect(original.dirtyFlags == .structure)
    try graph.commit(graph.prepare(CounterView(probe: probe)))
    #expect(graph.root === original)
    #expect(graph.root?.children.first?.value(as: Int.self) == 3)
  }

  @Test
  func `state does not survive structural identity replacement`() throws {
    let firstProbe = StateProbe()
    let secondProbe = StateProbe()
    let graph = ViewGraph()
    let first = NodeDescriptor.makeDeclarative(CounterView(probe: firstProbe)).withKey("first")
    try graph.commit(graph.prepare(first))
    firstProbe.binding?.wrappedValue = 9

    let second = NodeDescriptor.makeDeclarative(CounterView(probe: secondProbe)).withKey("second")
    try graph.commit(graph.prepare(second))

    #expect(graph.root?.children.first?.value(as: Int.self) == 0)
  }

  @Test
  func `mutation during body evaluation throws typed diagnostic`() throws {
    let graph = ViewGraph()

    #expect(throws: BodyMutationDiagnostic.self) {
      try graph.prepare(MutatingBodyView())
    }
    #expect(graph.root == nil)
  }

  @Test
  func `environment tracks reads and invalidates only dependents`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(EnvironmentReader()))
    let root = try #require(graph.root)
    graph.clearDirtyFlags()

    graph.setEnvironment("dark", for: ThemeKey.self)

    #expect(root.dirtyFlags == .structure)
    try graph.commit(graph.prepare(EnvironmentReader()))
    #expect(graph.root?.children.first?.value(as: String.self) == "dark")
    graph.clearDirtyFlags()
    graph.setEnvironment("dark", for: ThemeKey.self)
    #expect(root.dirtyFlags.isEmpty)
  }

  @Test
  func `preferences reduce bottom up in child order`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(PreferenceTree()))

    #expect(graph.root?.preference(SumPreference.self) == 6)
  }

  @Test
  func `changed preference invalidates A reader`() throws {
    let graph = ViewGraph()
    try graph.commit(graph.prepare(PreferenceReader(value: 1)))
    let root = try #require(graph.root)
    graph.clearDirtyFlags()

    try graph.commit(graph.prepare(PreferenceReader(value: 2)))

    #expect(root.dirtyFlags == .structure)
    #expect(root.preference(SumPreference.self) == 2)
  }

  @Test
  func `observation invalidates current mounted node`() async throws {
    let model = Model()
    let graph = ViewGraph()
    try graph.commit(graph.prepare(ObservedView(model: model)))
    let root = try #require(graph.root)
    graph.clearDirtyFlags()

    model.value = 1
    await Task.yield()

    #expect(root.dirtyFlags == .structure)
  }

  @Test
  func `rollback restores dynamic state preferences and metadata`() throws {
    let probe = StateProbe()
    let graph = ViewGraph()
    try graph.commit(graph.prepare(CounterView(probe: probe)))
    let root = try #require(graph.root)
    root.setMetadata("running", for: AnimationSlot.self)
    probe.binding?.wrappedValue = 4
    try graph.commit(graph.prepare(CounterView(probe: probe)))

    probe.binding?.wrappedValue = 7
    let commit = try graph.beginCommit(graph.prepare(CounterView(probe: probe)))
    root.setMetadata("staged", for: AnimationSlot.self)
    try graph.rollbackCommit(commit)

    #expect(root.metadata(for: AnimationSlot.self) == "running")
    #expect(root.children.first?.value(as: Int.self) == 4)
  }
}

@MainActor
private final class StateProbe {
  var binding: Binding<Int>?
}

@MainActor
private struct CounterView: View {
  @State private var count = 0
  let probe: StateProbe

  var graphBody: [NodeDescriptor] {
    probe.binding = $count
    NodeDescriptor(type: DeclarativeLeaf.self, value: count)
  }
}

@MainActor
private struct MutatingBodyView: View {
  @State private var count = 0

  var graphBody: [NodeDescriptor] {
    count += 1
    NodeDescriptor(type: DeclarativeLeaf.self, value: count)
  }
}

private enum ThemeKey: EnvironmentKey {
  static let defaultValue = "light"
}

@MainActor
private struct EnvironmentReader: View {
  @Environment(ThemeKey.self) private var theme

  var graphBody: [NodeDescriptor] {
    NodeDescriptor(type: DeclarativeLeaf.self, value: theme)
  }
}

private enum SumPreference: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value += nextValue()
  }
}

@MainActor
private struct PreferenceTree: View {
  var graphBody: [NodeDescriptor] {
    NodeDescriptor(type: DeclarativeLeaf.self).preference(SumPreference.self, 1)
    NodeDescriptor(type: DeclarativeLeaf.self).preference(SumPreference.self, 2)
    NodeDescriptor(type: DeclarativeLeaf.self).preference(SumPreference.self, 3)
  }
}

@MainActor
private struct PreferenceReader: View {
  @Preference(SumPreference.self) private var sum
  let value: Int

  var graphBody: [NodeDescriptor] {
    NodeDescriptor(type: DeclarativeLeaf.self, value: sum)
      .preference(SumPreference.self, value)
  }
}

@Observable
@MainActor
private final class Model {
  var value = 0
}

@MainActor
private struct ObservedView: View {
  let model: Model

  var graphBody: [NodeDescriptor] {
    NodeDescriptor(type: DeclarativeLeaf.self, value: model.value)
  }
}

private enum DeclarativeLeaf {}

extension NodeDescriptor {
  @MainActor
  fileprivate func preference<Key: PreferenceKey>(_ key: Key.Type, _ value: Key.Value) -> Self {
    settingPreference(key, to: value)
  }

  fileprivate func withKey(_ key: String) -> Self {
    var copy = self
    copy.identity = StructuralIdentity(type: identity.type, key: key)
    return copy
  }
}
