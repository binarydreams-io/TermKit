import TUIFoundation
import TUIViewGraph

package struct TimelineFrameEnvironment: Sendable, Hashable {
    package var instant: TimeInstant

    package init(instant: TimeInstant = .zero) {
        self.instant = instant
    }
}

package struct TimelineFrameEnvironmentKey: EnvironmentKey {
    package static let defaultValue = TimelineFrameEnvironment()
}

private enum TimelineFrameAttributeID {}

private struct TimelineFrameAttribute: MountedFrameDemandAttribute {
    let schedule: TimelineSchedule

    var id: AnyHashable { ObjectIdentifier(TimelineFrameAttributeID.self) }

    func apply(
        to node: MountedNode,
        replacing previous: (any MountedNodeAttribute)?
    ) -> [MountedNodeAttributeAction] { [] }

    func remove(from node: MountedNode) -> [MountedNodeAttributeAction] { [] }

    func frameDemand(after instant: TimeInstant) -> MountedFrameDemand? {
        switch schedule.kind {
        case .animation:
            return schedule.cadence.map { MountedFrameDemand(cadence: $0) }
        case .periodic, .explicit:
            return schedule.next(after: instant).map { MountedFrameDemand(deadline: $0) }
        }
    }
}

/// A view whose content is evaluated for timeline instants.
public struct TimelineView<Content: View>: View {
    /// Information about one timeline update.
    public struct Context: Sendable, Hashable {
        /// The instant represented by this update.
        public var instant: TimeInstant

        /// The preferred interval between updates, if the schedule has one.
        public var cadence: TUIDuration?

        /// A value that indicates whether animations can run.
        public var animationsEnabled: Bool

        /// A value that indicates whether the current environment reduces motion.
        public var reduceMotion: Bool

        /// Creates a timeline context.
        public init(
            instant: TimeInstant,
            cadence: TUIDuration?,
            animationsEnabled: Bool = true,
            reduceMotion: Bool = false
        ) {
            self.instant = instant
            self.cadence = cadence
            self.animationsEnabled = animationsEnabled
            self.reduceMotion = reduceMotion
        }
    }

    /// The schedule that determines update instants.
    public let schedule: TimelineSchedule

    /// The current externally supplied instant.
    public let instant: TimeInstant

    @Environment(TimelineFrameEnvironmentKey.self) private var frameEnvironment
    @Environment(AnimationsEnabledEnvironmentKey.self) private var animationsEnabled
    @Environment(ReduceMotionEnvironmentKey.self) private var reduceMotion

    private let usesRuntimeInstant: Bool
    private let content: @MainActor (Context) -> Content

    /// Creates a timeline view for an externally supplied instant.
    public init(
        _ schedule: TimelineSchedule,
        at instant: TimeInstant,
        content: @escaping @MainActor (Context) -> Content
    ) {
        self.schedule = schedule
        self.instant = instant
        usesRuntimeInstant = false
        self.content = content
    }

    /// Creates a timeline view that uses the mounted runtime instant.
    public init(
        _ schedule: TimelineSchedule,
        content: @escaping @MainActor (Context) -> Content
    ) {
        self.schedule = schedule
        instant = .zero
        usesRuntimeInstant = true
        self.content = content
    }

    /// Returns the first scheduled update after the specified instant.
    public func nextUpdate(after instant: TimeInstant) -> TimeInstant? {
        schedule.next(after: instant)
    }

    /// Creates content for the specified externally supplied instant.
    @MainActor
    public func content(at instant: TimeInstant) -> Content {
        content(Context(instant: instant, cadence: schedule.cadence))
    }

    @MainActor
    public var graphBody: [NodeDescriptor] {
        let currentInstant = usesRuntimeInstant ? frameEnvironment.instant : instant
        let motionEnabled = animationsEnabled && reduceMotion == false
        let context = Context(
            instant: currentInstant,
            cadence: motionEnabled ? schedule.cadence : nil,
            animationsEnabled: animationsEnabled,
            reduceMotion: reduceMotion
        )
        guard usesRuntimeInstant else { return content(context).graphBody }
        var descriptor = NodeDescriptor.declarative(content(context))
        if motionEnabled || schedule.kind == .explicit {
            descriptor = descriptor.attribute(TimelineFrameAttribute(schedule: schedule))
        }
        return [descriptor]
    }
}
