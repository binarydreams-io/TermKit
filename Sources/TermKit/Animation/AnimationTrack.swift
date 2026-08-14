/// A stable identifier for an animatable property.
public struct AnimationPropertyKey: RawRepresentable, ExpressibleByStringLiteral, Sendable, Hashable {
    /// The property's string value.
    public var rawValue: String

    /// Creates a property key from a nonempty string.
    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "An animation property key must not be empty.")
        self.rawValue = rawValue
    }

    /// Creates a property key from a string literal.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// A node and property pair that identifies an animation track.
public struct AnimationTrackKey: Sendable, Hashable {
    /// The animated node identifier.
    public var nodeID: NodeID
    /// The animated property identifier.
    public var property: AnimationPropertyKey

    /// Creates an animation track key.
    public init(nodeID: NodeID, property: AnimationPropertyKey) {
        self.nodeID = nodeID
        self.property = property
    }
}

/// The lifecycle state of an animation track.
public enum AnimationTrackStatus: Sendable, Hashable {
    /// The track is producing samples.
    case running
    /// The track reached its target.
    case completed
    /// The track stopped before completion.
    case cancelled
}

/// The state and sampling logic for one animated value.
@MainActor
public struct AnimationTrack<Value: VectorArithmetic> {
    /// The value at the track's start instant.
    public private(set) var startValue: Value
    /// The value toward which the track moves.
    public private(set) var targetValue: Value
    /// The most recently sampled value.
    public private(set) var currentValue: Value
    /// The current value velocity, in value units per second.
    public private(set) var velocity: Value
    /// The track's start instant.
    public private(set) var startTime: TimeInstant
    /// The active animation, or `nil` for an immediate change.
    public private(set) var animation: Animation?
    /// The track's lifecycle state.
    public private(set) var status: AnimationTrackStatus

    private var completion: AnimationCompletion?
    private var completionParticipant: TransactionCompletionParticipant?
    private var initialVelocity: Value

    /// Creates a track from a transaction.
    public init(
        from startValue: Value,
        to targetValue: Value,
        at startTime: TimeInstant,
        transaction: Transaction
    ) {
        self.init(
            from: startValue,
            to: targetValue,
            at: startTime,
            transaction: transaction,
            defersCompletion: false
        )
    }

    private init(
        from startValue: Value,
        to targetValue: Value,
        at startTime: TimeInstant,
        transaction: Transaction,
        defersCompletion: Bool
    ) {
        self.startValue = startValue
        self.targetValue = targetValue
        self.startTime = startTime
        animation = transaction.areAnimationsEnabled ? transaction.animation : nil
        completion = transaction.completion
        completionParticipant = transaction.completionGroup?.register()
        initialVelocity = .zero

        if animation == nil || startValue == targetValue {
            currentValue = targetValue
            velocity = .zero
            status = .completed
        } else {
            currentValue = startValue
            velocity = Self.velocity(from: startValue, to: targetValue, animation: animation)
            status = .running
        }

        if status == .completed, defersCompletion == false {
            takeCompletionAction()?()
        }
    }

    /// Creates a track from an animation and completion action.
    public init(
        from startValue: Value,
        to targetValue: Value,
        at startTime: TimeInstant,
        animation: Animation?,
        completion: AnimationCompletion? = nil
    ) {
        self.init(
            from: startValue,
            to: targetValue,
            at: startTime,
            transaction: Transaction(animation: animation, completion: completion)
        )
    }

    /// A value that indicates whether the track no longer runs.
    public var isComplete: Bool {
        status != .running
    }

    /// Samples and updates the track at an instant.
    /// - Complexity: O(1).
    @discardableResult
    public mutating func sample(at instant: TimeInstant) -> Value {
        let result = sampleDeferringCompletion(at: instant)
        result.completion?()
        return result.value
    }

    fileprivate mutating func sampleDeferringCompletion(
        at instant: TimeInstant
    ) -> (value: Value, completion: AnimationCompletion?) {
        guard status == .running, let animation else { return (currentValue, nil) }
        let animationSample = animation.sample(at: startTime.duration(to: instant))

        if animationSample.isComplete {
            return (targetValue, finishDeferringCompletion())
        }

        if let springSample = animation.springMotionSample(at: startTime.duration(to: instant)) {
            let displacement = startValue - targetValue
            currentValue =
                targetValue
                + displacement.scaled(by: springSample.displacementScale)
                + initialVelocity.scaled(by: springSample.initialVelocityScale)
            velocity =
                displacement.scaled(by: springSample.displacementVelocityScale)
                + initialVelocity.scaled(by: springSample.initialVelocityVelocityScale)
        } else {
            let displacement = targetValue - startValue
            currentValue = startValue + displacement.scaled(by: animationSample.value)
            velocity = displacement.scaled(by: animationSample.velocity)
        }
        return (currentValue, nil)
    }

    /// Changes the target while preserving sampled continuity.
    /// - Complexity: O(1).
    @discardableResult
    public mutating func retarget(
        to newTarget: Value,
        at instant: TimeInstant,
        transaction: Transaction
    ) -> Value {
        let result = retargetDeferringCompletion(to: newTarget, at: instant, transaction: transaction)
        for completion in result.completions {
            completion()
        }
        return result.value
    }

    fileprivate mutating func retargetDeferringCompletion(
        to newTarget: Value,
        at instant: TimeInstant,
        transaction: Transaction
    ) -> (value: Value, completions: [AnimationCompletion]) {
        let sample = sampleDeferringCompletion(at: instant)
        let sampledValue = sample.value
        let sampledVelocity = velocity
        var completions = sample.completion.map { [$0] } ?? []
        if let cancellation = takeCancellationAction() {
            completions.append(cancellation)
        }
        startValue = sampledValue
        targetValue = newTarget
        currentValue = sampledValue
        startTime = instant
        animation = transaction.areAnimationsEnabled ? transaction.animation : nil
        completion = transaction.completionGroup == nil ? transaction.completion : nil
        completionParticipant = transaction.completionGroup?.register()

        if animation == nil || sampledValue == newTarget {
            currentValue = newTarget
            velocity = .zero
            initialVelocity = .zero
            status = .completed
            if let completion = takeCompletionAction() {
                completions.append(completion)
            }
        } else {
            if case .spring = animation?.curve {
                initialVelocity = sampledVelocity
                velocity = sampledVelocity
            } else {
                initialVelocity = .zero
                velocity = Self.velocity(from: sampledValue, to: newTarget, animation: animation)
            }
            status = .running
        }
        return (currentValue, completions)
    }

    /// Changes the target with an animation and completion action.
    /// - Complexity: O(1).
    @discardableResult
    public mutating func retarget(
        to newTarget: Value,
        at instant: TimeInstant,
        animation: Animation?,
        completion: AnimationCompletion? = nil
    ) -> Value {
        retarget(
            to: newTarget,
            at: instant,
            transaction: Transaction(animation: animation, completion: completion)
        )
    }

    /// Cancels the running track without invoking its completion action.
    /// - Complexity: O(1).
    public mutating func cancel() {
        cancelDeferringCompletion()?()
    }

    fileprivate mutating func cancelDeferringCompletion() -> AnimationCompletion? {
        guard status == .running else { return nil }
        let cancellation = takeCancellationAction()
        velocity = .zero
        initialVelocity = .zero
        status = .cancelled
        return cancellation
    }

    /// Moves the running track to its target and invokes completion.
    /// - Complexity: O(1).
    public mutating func finish() {
        let completion = finishDeferringCompletion()
        completion?()
    }

    private mutating func finishDeferringCompletion() -> AnimationCompletion? {
        guard status == .running else { return nil }
        currentValue = targetValue
        velocity = .zero
        initialVelocity = .zero
        status = .completed
        return takeCompletionAction()
    }

    private mutating func takeCompletionAction() -> AnimationCompletion? {
        let completion = completion
        self.completion = nil
        if let completionParticipant {
            self.completionParticipant = nil
            return {
                completion?()
                completionParticipant.complete()
            }
        }
        return completion
    }

    private mutating func takeCancellationAction() -> AnimationCompletion? {
        completion = nil
        guard let completionParticipant else { return nil }
        self.completionParticipant = nil
        return { completionParticipant.cancel() }
    }

    private static func velocity(from startValue: Value, to targetValue: Value, animation: Animation?) -> Value {
        guard let animation else { return .zero }
        if case .spring = animation.curve {
            return .zero
        }
        return (targetValue - startValue).scaled(by: animation.sample(at: .zero).velocity)
    }

    fileprivate static func makeDeferringCompletion(
        from startValue: Value,
        to targetValue: Value,
        at startTime: TimeInstant,
        transaction: Transaction
    ) -> (track: AnimationTrack, completion: AnimationCompletion?) {
        var track = AnimationTrack(
            from: startValue,
            to: targetValue,
            at: startTime,
            transaction: transaction,
            defersCompletion: true
        )
        let completion = track.status == .completed ? track.takeCompletionAction() : nil
        return (track, completion)
    }
}

@MainActor
private protocol AnyAnimationTrackBox: AnyObject {
    var status: AnimationTrackStatus { get }
    func cancel()
    func cancelDeferringCompletion() -> AnimationCompletion?
    func copy() -> any AnyAnimationTrackBox
}

@MainActor
private final class ConcreteAnimationTrackBox<Value: VectorArithmetic>: AnyAnimationTrackBox {
    var track: AnimationTrack<Value>

    init(_ track: AnimationTrack<Value>) {
        self.track = track
    }

    var status: AnimationTrackStatus { track.status }

    func cancel() {
        track.cancel()
    }

    func cancelDeferringCompletion() -> AnimationCompletion? {
        track.cancelDeferringCompletion()
    }

    func copy() -> any AnyAnimationTrackBox {
        ConcreteAnimationTrackBox(track)
    }
}

/// Stores type-erased animation tracks by node and property.
@MainActor
public final class AnimationTrackStore: FrameSnapshottingNodeMetadata {
    private var tracks: [AnimationTrackKey: any AnyAnimationTrackBox] = [:]

    /// Creates an empty track store.
    public init() {}

    private init(tracks: [AnimationTrackKey: any AnyAnimationTrackBox]) {
        self.tracks = tracks
    }

    /// Creates an independent snapshot of all tracks.
    /// - Complexity: O(n), where n is the track count.
    public func makeFrameSnapshotCopy() -> any FrameSnapshottingNodeMetadata {
        AnimationTrackStore(tracks: tracks.mapValues { $0.copy() })
    }

    /// The number of stored tracks.
    public var count: Int { tracks.count }

    /// The number of running tracks.
    /// - Complexity: O(n), where n is the track count.
    public var activeCount: Int {
        tracks.values.lazy.filter { $0.status == .running }.count
    }

    /// Sets or retargets a typed property value.
    /// - Complexity: O(1) on average.
    @discardableResult
    public func setTarget<Value: VectorArithmetic>(
        _ target: Value,
        from initialValue: Value,
        for key: AnimationTrackKey,
        at instant: TimeInstant,
        transaction: Transaction = .current
    ) -> Value {
        let result = setTargetDeferringActions(
            target,
            from: initialValue,
            for: key,
            at: instant,
            transaction: transaction
        )
        for action in result.actions { action() }
        return result.value
    }

    func setTargetDeferringActions<Value: VectorArithmetic>(
        _ target: Value,
        from initialValue: Value,
        for key: AnimationTrackKey,
        at instant: TimeInstant,
        transaction: Transaction = .current
    ) -> (value: Value, actions: [AnimationCompletion]) {
        if let box = tracks[key] as? ConcreteAnimationTrackBox<Value> {
            let result = box.track.retargetDeferringCompletion(
                to: target,
                at: instant,
                transaction: transaction
            )
            return (result.value, result.completions)
        }

        let cancellation = tracks[key]?.cancelDeferringCompletion()
        let result = AnimationTrack.makeDeferringCompletion(
            from: initialValue,
            to: target,
            at: instant,
            transaction: transaction
        )
        tracks[key] = ConcreteAnimationTrackBox(result.track)
        let actions = [cancellation, result.completion].compactMap { $0 }
        return (result.track.currentValue, actions)
    }

    /// Retargets an existing typed track.
    /// - Complexity: O(1) on average.
    @discardableResult
    public func retarget<Value: VectorArithmetic>(
        _ key: AnimationTrackKey,
        to target: Value,
        at instant: TimeInstant,
        transaction: Transaction = .current
    ) -> Value? {
        guard let box = tracks[key] as? ConcreteAnimationTrackBox<Value> else { return nil }
        let result = box.track.retargetDeferringCompletion(
            to: target,
            at: instant,
            transaction: transaction
        )
        for completion in result.completions {
            completion()
        }
        return result.value
    }

    /// Samples an existing typed track.
    /// - Complexity: O(1) on average.
    public func sample<Value: VectorArithmetic>(
        _ key: AnimationTrackKey,
        as type: Value.Type = Value.self,
        at instant: TimeInstant
    ) -> Value? {
        let result = sampleDeferringCompletion(key, as: type, at: instant)
        result.completion?()
        return result.value
    }

    func preview<Value: VectorArithmetic>(
        _ key: AnimationTrackKey,
        as type: Value.Type = Value.self,
        at instant: TimeInstant
    ) -> Value? {
        guard let box = tracks[key] as? ConcreteAnimationTrackBox<Value>,
            let copy = box.copy() as? ConcreteAnimationTrackBox<Value>
        else { return nil }
        return copy.track.sampleDeferringCompletion(at: instant).value
    }

    func sampleDeferringCompletion<Value: VectorArithmetic>(
        _ key: AnimationTrackKey,
        as type: Value.Type = Value.self,
        at instant: TimeInstant
    ) -> (value: Value?, completion: AnimationCompletion?) {
        guard let box = tracks[key] as? ConcreteAnimationTrackBox<Value> else { return (nil, nil) }
        let result = box.track.sampleDeferringCompletion(at: instant)
        return (result.value, result.completion)
    }

    /// Returns an existing track's target value.
    /// - Complexity: O(1) on average.
    public func target<Value: VectorArithmetic>(
        _ key: AnimationTrackKey,
        as type: Value.Type = Value.self
    ) -> Value? {
        (tracks[key] as? ConcreteAnimationTrackBox<Value>)?.track.targetValue
    }

    /// Returns the status of a stored track.
    /// - Complexity: O(1) on average.
    public func status(for key: AnimationTrackKey) -> AnimationTrackStatus? {
        tracks[key]?.status
    }

    /// Cancels a stored track.
    /// - Complexity: O(1) on average.
    public func cancel(_ key: AnimationTrackKey) {
        tracks[key]?.cancel()
    }

    /// Removes and cancels a stored track.
    /// - Complexity: O(1) on average.
    public func remove(_ key: AnimationTrackKey) {
        removeDeferringCompletion(key)?()
    }

    func removeDeferringCompletion(_ key: AnimationTrackKey) -> AnimationCompletion? {
        tracks.removeValue(forKey: key)?.cancelDeferringCompletion()
    }

    /// Removes tracks that are not running.
    /// - Complexity: O(n), where n is the track count.
    public func removeCompleted() {
        tracks = tracks.filter { $0.value.status == .running }
    }

    /// Cancels and removes all tracks.
    /// - Complexity: O(n), where n is the track count.
    public func removeAll() {
        for track in tracks.values {
            track.cancel()
        }
        tracks.removeAll(keepingCapacity: true)
    }
}
