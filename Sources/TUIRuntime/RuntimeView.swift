import TUIAnimation
import TUIControls
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public enum MotionPolicy: Sendable, Hashable {
    case standard
    case reduced

    public var allowsAnimation: Bool {
        self == .standard
    }
}

public struct RuntimeFrameContext: Sendable {
    public var terminalSize: CellSize
    public var instant: TimeInstant
    public var deltaTime: TUIDuration
    public var motionPolicy: MotionPolicy
    public var transaction: Transaction

    public init(
        terminalSize: CellSize,
        instant: TimeInstant,
        deltaTime: TUIDuration = .zero,
        motionPolicy: MotionPolicy = .standard,
        transaction: Transaction = Transaction()
    ) {
        self.terminalSize = terminalSize
        self.instant = instant
        self.deltaTime = deltaTime
        self.motionPolicy = motionPolicy
        self.transaction = transaction
    }

    public func sample(_ animation: Animation, startedAt start: TimeInstant) -> AnimationSample {
        guard motionPolicy.allowsAnimation else {
            return animation.sample(at: animation.duration)
        }
        return animation.sample(at: start.duration(to: instant))
    }
}

public struct RuntimeFrame: Sendable {
    public var surface: TUIRenderer.Surface
    public var semantics: SemanticTree
    public var damage: DamageTracker?
    public var nextFrameCadence: TUIDuration?

    public init(
        surface: TUIRenderer.Surface,
        semantics: SemanticTree = SemanticTree(),
        damage: DamageTracker? = nil,
        nextFrameCadence: TUIDuration? = nil
    ) {
        if let nextFrameCadence {
            precondition(nextFrameCadence > .zero, "A frame cadence must be positive.")
        }
        self.surface = surface
        self.semantics = semantics
        self.damage = damage
        self.nextFrameCadence = nextFrameCadence
    }
}

@MainActor
public protocol RuntimeView {
    func nodeDescriptor(in context: RuntimeFrameContext) -> NodeDescriptor
    func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws
    func paint(in context: RuntimeFrameContext, resources: inout ControlRenderResources) throws -> RuntimeFrame
}

@MainActor
package protocol IncrementalRuntimeView: AnyObject, RuntimeView {
    var incrementalCounters: IncrementalRuntimeCounters { get }
    var activePresentationNodes: [MountedNode] { get }
    func beginIncrementalFrame(
        in context: RuntimeFrameContext,
        graph: ViewGraph,
        dirtyNodes: [ViewGraphFrame.DirtyNode],
        externalDamage: DamageTracker
    )
    func updatePresentation(in context: RuntimeFrameContext, graph: ViewGraph, layout: Bool) throws
    func finishIncrementalFrame()
    func rollbackIncrementalFrame()
}

package struct IncrementalRuntimeCounters: Equatable {
    package var layoutPassCount: Int
    package var measurementCount: Int
    package var paintVisitCount: Int
    package var offscreenLayerCount: Int
    package var offscreenCellCount: Int
}

extension RuntimeView {
    public func layout(in context: RuntimeFrameContext, graph: ViewGraph) throws {
        graph.root?.cache(
            size: context.terminalSize,
            frame: CellRect(origin: .zero, size: context.terminalSize)
        )
    }
}
