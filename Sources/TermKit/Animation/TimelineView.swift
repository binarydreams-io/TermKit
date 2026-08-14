struct TimelineFrameEnvironment: Sendable, Hashable {
    var instant: TimeInstant

    init(instant: TimeInstant = .zero) {
        self.instant = instant
    }
}

struct TimelineFrameEnvironmentKey: EnvironmentKey {
    static let defaultValue = TimelineFrameEnvironment()
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
        public var cadence: TimeSpan?

        /// A value that indicates whether animations can run.
        public var areAnimationsEnabled: Bool

        /// A value that indicates whether the current environment reduces motion.
        public var isReducedMotionEnabled: Bool

        /// Creates a timeline context.
        /// - Complexity: O(1).
        public init(
            instant: TimeInstant,
            cadence: TimeSpan?,
            animationsEnabled: Bool = true,
            reduceMotion: Bool = false
        ) {
            self.instant = instant
            self.cadence = cadence
            areAnimationsEnabled = animationsEnabled
            isReducedMotionEnabled = reduceMotion
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
    private let content: @MainActor (_ context: Context) -> Content

    /// Creates a timeline view for an externally supplied instant.
    /// - Complexity: O(1).
    public init(
        _ schedule: TimelineSchedule,
        at instant: TimeInstant,
        content: @escaping @MainActor (_ context: Context) -> Content
    ) {
        self.schedule = schedule
        self.instant = instant
        usesRuntimeInstant = false
        self.content = content
    }

    /// Creates a timeline view that uses the mounted runtime instant.
    /// - Complexity: O(1).
    public init(
        _ schedule: TimelineSchedule,
        content: @escaping @MainActor (_ context: Context) -> Content
    ) {
        self.schedule = schedule
        instant = .zero
        usesRuntimeInstant = true
        self.content = content
    }

    /// Returns the first scheduled update after the specified instant.
    /// - Complexity: O(n) for explicit schedules and O(1) otherwise.
    public func nextUpdate(after instant: TimeInstant) -> TimeInstant? {
        schedule.next(after: instant)
    }

    /// Creates content for the specified externally supplied instant.
    /// - Complexity: O(1), excluding content creation.
    @MainActor
    public func content(at instant: TimeInstant) -> Content {
        content(Context(instant: instant, cadence: schedule.cadence))
    }

    /// The descriptors for the content at the current timeline instant.
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
        var descriptor = NodeDescriptor.makeDeclarative(content(context))
        if motionEnabled || schedule.kind == .explicit {
            descriptor = descriptor.attribute(TimelineFrameAttribute(schedule: schedule))
        }
        return [descriptor]
    }
}
