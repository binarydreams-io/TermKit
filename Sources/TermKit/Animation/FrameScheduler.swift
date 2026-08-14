/// A stable identifier for a frame demand.
public struct FrameDemandID: RawRepresentable, ExpressibleByStringLiteral, Sendable, Hashable {
  /// The identifier's string value.
  public var rawValue: String

  /// Creates a frame demand identifier from a nonempty string.
  public init(rawValue: String) {
    precondition(rawValue.isEmpty == false, "A frame demand identifier must not be empty.")
    self.rawValue = rawValue
  }

  /// Creates a frame demand identifier from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

/// Timing information for one rendered frame.
public struct FrameTick: Sendable, Hashable {
  /// The frame instant.
  public var instant: TimeInstant
  /// The elapsed time since the preceding frame.
  public var deltaTime: TimeSpan

  /// Creates a frame tick.
  public init(instant: TimeInstant, deltaTime: TimeSpan) {
    self.instant = instant
    self.deltaTime = deltaTime
  }
}

/// Coordinates frame requests and recurring frame demands.
@MainActor
public final class FrameScheduler {
  private enum Demand {
    case cadence(TimeSpan)
    case deadline(TimeInstant)
  }

  /// The maximum supported frame rate.
  public nonisolated static let maximumFramesPerSecond = 60
  /// The minimum interval between frames.
  public nonisolated static let minimumFrameInterval = TimeSpan.nanoseconds(16_666_667)

  /// The maximum delta reported by a frame tick.
  public let maximumDeltaTime: TimeSpan

  private var demands: [FrameDemandID: Demand] = [:]
  private var hasPendingInvalidation = false
  private var lastFrameInstant: TimeInstant?

  /// Creates a frame scheduler.
  public init(maximumDeltaTime: TimeSpan = .milliseconds(100)) {
    precondition(maximumDeltaTime > .zero, "The maximum frame delta must be positive.")
    self.maximumDeltaTime = maximumDeltaTime
  }

  /// A value that indicates whether no frame work remains.
  public var isIdle: Bool {
    demands.isEmpty && hasPendingInvalidation == false
  }

  /// The number of registered recurring demands.
  public var demandCount: Int {
    demands.count
  }

  /// Requests one frame.
  /// - Complexity: O(1).
  public func requestFrame() {
    hasPendingInvalidation = true
  }

  /// Registers or replaces a recurring frame demand.
  /// - Complexity: O(1) on average.
  public func register(_ id: FrameDemandID, cadence: TimeSpan = minimumFrameInterval) {
    precondition(cadence > .zero, "A frame cadence must be positive.")
    demands[id] = .cadence(max(cadence, Self.minimumFrameInterval))
  }

  func register(_ id: FrameDemandID, deadline: TimeInstant) {
    demands[id] = .deadline(deadline)
  }

  /// Removes a frame demand.
  /// - Complexity: O(1) on average.
  public func remove(_ id: FrameDemandID) {
    demands.removeValue(forKey: id)
  }

  /// Removes all recurring frame demands.
  /// - Complexity: O(n), where n is the demand count.
  public func removeAllDemands() {
    demands.removeAll(keepingCapacity: true)
  }

  /// Returns the earliest instant at which a frame can run.
  /// - Complexity: O(n), where n is the demand count.
  public func nextDeadline(at instant: TimeInstant) -> TimeInstant? {
    guard isIdle == false else { return nil }
    guard let deadline = scheduledDeadline(at: instant) else { return instant }
    return max(deadline, instant)
  }

  /// Produces a frame tick when a frame is due.
  /// - Complexity: O(n), where n is the demand count.
  @discardableResult
  public func frame(at instant: TimeInstant) -> FrameTick? {
    guard isIdle == false else { return nil }
    if let scheduledDeadline = scheduledDeadline(at: instant), instant < scheduledDeadline {
      return nil
    }

    let deltaTime: TimeSpan
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
    var deadline =
      hasPendingInvalidation
        ? lastFrameInstant?.advanced(by: Self.minimumFrameInterval) ?? instant
        : nil
    for demand in demands.values {
      let candidate: TimeInstant = switch demand {
      case let .cadence(cadence):
        lastFrameInstant?.advanced(by: cadence) ?? instant
      case let .deadline(demandDeadline):
        demandDeadline
      }
      deadline = deadline.map { min($0, candidate) } ?? candidate
    }
    return deadline
  }
}
