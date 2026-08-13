import TUIFoundation

public struct FrameDemandID: RawRepresentable, ExpressibleByStringLiteral, Sendable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A frame demand identifier must not be empty.")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct FrameTick: Sendable, Hashable {
    public var instant: TimeInstant
    public var deltaTime: TUIDuration

    public init(instant: TimeInstant, deltaTime: TUIDuration) {
        self.instant = instant
        self.deltaTime = deltaTime
    }
}

@MainActor
public final class FrameScheduler {
    private enum Demand {
        case cadence(TUIDuration)
        case deadline(TimeInstant)
    }

    nonisolated public static let maximumFramesPerSecond = 60
    nonisolated public static let minimumFrameInterval = TUIDuration.nanoseconds(16_666_667)

    public let maximumDeltaTime: TUIDuration

    private var demands: [FrameDemandID: Demand] = [:]
    private var hasPendingInvalidation = false
    private var lastFrameInstant: TimeInstant?

    public init(maximumDeltaTime: TUIDuration = .milliseconds(100)) {
        precondition(maximumDeltaTime > .zero, "The maximum frame delta must be positive.")
        self.maximumDeltaTime = maximumDeltaTime
    }

    public var isIdle: Bool {
        demands.isEmpty && hasPendingInvalidation == false
    }

    public var demandCount: Int { demands.count }

    public func requestFrame() {
        hasPendingInvalidation = true
    }

    public func register(_ id: FrameDemandID, cadence: TUIDuration = minimumFrameInterval) {
        precondition(cadence > .zero, "A frame cadence must be positive.")
        demands[id] = .cadence(max(cadence, Self.minimumFrameInterval))
    }

    package func register(_ id: FrameDemandID, deadline: TimeInstant) {
        demands[id] = .deadline(deadline)
    }

    public func remove(_ id: FrameDemandID) {
        demands.removeValue(forKey: id)
    }

    public func removeAllDemands() {
        demands.removeAll(keepingCapacity: true)
    }

    public func nextDeadline(at instant: TimeInstant) -> TimeInstant? {
        guard isIdle == false else { return nil }
        guard let deadline = scheduledDeadline(at: instant) else { return instant }
        return max(deadline, instant)
    }

    @discardableResult
    public func frame(at instant: TimeInstant) -> FrameTick? {
        guard isIdle == false else { return nil }
        if let scheduledDeadline = scheduledDeadline(at: instant), instant < scheduledDeadline { return nil }

        let deltaTime: TUIDuration
        if let lastFrameInstant {
            guard instant >= lastFrameInstant else { return nil }
            deltaTime = min(lastFrameInstant.duration(to: instant), maximumDeltaTime)
        } else {
            deltaTime = .zero
        }

        hasPendingInvalidation = false
        lastFrameInstant = instant
        return FrameTick(instant: instant, deltaTime: deltaTime)
    }

    private func scheduledDeadline(at instant: TimeInstant) -> TimeInstant? {
        var deadline = hasPendingInvalidation
            ? lastFrameInstant?.advanced(by: Self.minimumFrameInterval) ?? instant
            : nil
        for demand in demands.values {
            let candidate: TimeInstant
            switch demand {
            case .cadence(let cadence):
                candidate = lastFrameInstant?.advanced(by: cadence) ?? instant
            case .deadline(let demandDeadline):
                candidate = demandDeadline
            }
            deadline = deadline.map { min($0, candidate) } ?? candidate
        }
        return deadline
    }
}
