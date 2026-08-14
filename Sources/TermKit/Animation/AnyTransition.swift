/// A deterministic sequence of symbols for transitions and timeline-driven effects.
public struct SymbolFrames: Sendable, Hashable {
  /// The animated symbols in display order.
  public let frames: [String]
  /// The symbol to display when motion is unavailable.
  public let fallback: String

  /// Creates a symbol sequence with a required static fallback.
  /// - Complexity: O(1).
  public init(_ frames: [String], fallback: String? = nil) {
    precondition(frames.isEmpty == false, "Symbol frames must not be empty.")
    self.frames = frames
    self.fallback = fallback ?? frames[0]
  }

  /// Returns the symbol at normalized progress.
  /// - Complexity: O(1).
  public func frame(at progress: Double, reduceMotion: Bool = false) -> String {
    guard reduceMotion == false else { return fallback }
    let progress = min(1, max(0, progress))
    let index = min(frames.count - 1, Int(progress * Double(frames.count)))
    return frames[index]
  }

  /// Returns the symbol for an externally supplied timeline instant.
  /// - Complexity: O(1).
  public func frame(
    at instant: TimeInstant,
    startingAt start: TimeInstant,
    interval: TimeSpan,
    motion: MotionEnvironmentValues = MotionEnvironmentValues()
  ) -> String {
    precondition(interval > .zero, "A symbol frame interval must be positive.")
    guard motion.areAnimationsEnabled, motion.isReducedMotionEnabled == false else { return fallback }
    guard instant >= start else { return frames[0] }
    let elapsed = start.duration(to: instant).nanoseconds
    return frames[Int((elapsed / interval.nanoseconds) % Int64(frames.count))]
  }

  fileprivate var reducedForMotion: SymbolFrames {
    SymbolFrames([fallback], fallback: fallback)
  }
}

/// An edge from which a transition moves or reveals content.
public enum TransitionEdge: Sendable, Hashable {
  /// The top edge.
  case top
  /// The leading edge.
  case leading
  /// The bottom edge.
  case bottom
  /// The trailing edge.
  case trailing
}

/// A visual effect applied during a transition.
public enum TransitionEffect: Sendable, Hashable {
  /// Changes opacity.
  case opacity
  /// Moves content from an edge by a cell distance.
  case move(edge: TransitionEdge, distance: Double)
  /// Reveals content from an edge.
  case reveal(edge: TransitionEdge)
  /// Wipes content from an edge.
  case wipe(edge: TransitionEdge)
  /// Changes a symbol through a sequence of frames.
  case symbolFrames(SymbolFrames)

  /// A value that indicates whether the effect changes spatial presentation.
  public var isSpatial: Bool {
    switch self {
    case .opacity, .symbolFrames: false
    case .move, .reveal, .wipe: true
    }
  }
}

/// The lifecycle phase sampled by a transition.
public enum TransitionPhase: Sendable, Hashable {
  /// The insertion phase.
  case insertion
  /// The removal phase.
  case removal
}

/// The resolved visual values for one transition sample.
public struct TransitionSample: Sendable, Hashable {
  /// The opacity multiplier.
  public var opacity: Double
  /// The horizontal and vertical cell offset.
  public var offset: AnimatablePair<Double, Double>
  /// The visible fraction for a reveal effect.
  public var revealFraction: Double
  /// The reveal edge, if a reveal effect applies.
  public var revealEdge: TransitionEdge?
  /// The visible fraction for a wipe effect.
  public var wipeFraction: Double
  /// The wipe edge, if a wipe effect applies.
  public var wipeEdge: TransitionEdge?
  /// The displayed symbol, if symbol frames apply.
  public var symbol: String?

  /// Creates a transition sample.
  public init(
    opacity: Double = 1,
    offset: AnimatablePair<Double, Double> = .zero,
    revealFraction: Double = 1,
    revealEdge: TransitionEdge? = nil,
    wipeFraction: Double = 1,
    wipeEdge: TransitionEdge? = nil,
    symbol: String? = nil
  ) {
    self.opacity = opacity
    self.offset = offset
    self.revealFraction = revealFraction
    self.revealEdge = revealEdge
    self.wipeFraction = wipeFraction
    self.wipeEdge = wipeEdge
    self.symbol = symbol
  }
}

/// Type-erased insertion and removal transition effects.
public struct AnyTransition: Sendable, Hashable {
  /// A transition with no effects.
  public static let identity = AnyTransition()
  /// A transition that changes opacity.
  public static let opacity = AnyTransition(effect: .opacity)

  /// The effects applied during insertion.
  public let insertionEffects: [TransitionEffect]
  /// The effects applied during removal.
  public let removalEffects: [TransitionEffect]

  /// Creates a movement transition.
  /// - Complexity: O(1).
  public static func move(edge: TransitionEdge, distance: Double = 1) -> AnyTransition {
    precondition(distance.isFinite && distance >= 0, "A transition distance must be finite and nonnegative.")
    return AnyTransition(effect: .move(edge: edge, distance: distance))
  }

  /// Creates a reveal transition.
  /// - Complexity: O(1).
  public static func reveal(edge: TransitionEdge = .top) -> AnyTransition {
    AnyTransition(effect: .reveal(edge: edge))
  }

  /// Creates a wipe transition.
  /// - Complexity: O(1).
  public static func wipe(edge: TransitionEdge = .leading) -> AnyTransition {
    AnyTransition(effect: .wipe(edge: edge))
  }

  /// Creates a symbol-frame transition.
  /// - Complexity: O(1).
  public static func symbolFrames(_ frames: SymbolFrames) -> AnyTransition {
    AnyTransition(effect: .symbolFrames(frames))
  }

  /// Creates a transition with different insertion and removal effects.
  /// - Complexity: O(n + m), where n and m are the effect counts.
  public static func asymmetric(
    insertion: AnyTransition,
    removal: AnyTransition
  ) -> AnyTransition {
    AnyTransition(
      insertionEffects: insertion.insertionEffects,
      removalEffects: removal.removalEffects
    )
  }

  /// Creates a transition from insertion and removal effects.
  /// - Complexity: O(n + m), where n and m are the effect counts.
  public init(
    insertionEffects: [TransitionEffect] = [],
    removalEffects: [TransitionEffect] = []
  ) {
    self.insertionEffects = Self.unique(insertionEffects)
    self.removalEffects = Self.unique(removalEffects)
  }

  /// Combines this transition with another transition.
  /// - Complexity: O(n + m), where n and m are the combined effect counts.
  public func combined(with other: AnyTransition) -> AnyTransition {
    AnyTransition(
      insertionEffects: insertionEffects + other.insertionEffects,
      removalEffects: removalEffects + other.removalEffects
    )
  }

  /// Returns a transition with spatial motion removed.
  /// - Complexity: O(n), where n is the effect count.
  public func reducedForMotion() -> AnyTransition {
    AnyTransition(
      insertionEffects: Self.reducedEffects(insertionEffects),
      removalEffects: Self.reducedEffects(removalEffects)
    )
  }

  /// Resolves this transition for transaction motion settings.
  /// - Complexity: O(n), where n is the effect count.
  public func resolved(for transaction: Transaction) -> AnyTransition {
    guard transaction.areAnimationsEnabled, transaction.animation != nil else { return .identity }
    return transaction.isReducedMotionEnabled ? reducedForMotion() : self
  }

  /// Samples the effects for a transition phase and progress.
  /// - Complexity: O(n), where n is the phase's effect count.
  public func sample(phase: TransitionPhase, progress: Double) -> TransitionSample {
    let clampedProgress = min(1, max(0, progress))
    let visibleProgress = phase == .insertion ? clampedProgress : 1 - clampedProgress
    let effects = phase == .insertion ? insertionEffects : removalEffects
    var sample = TransitionSample()

    for effect in effects {
      switch effect {
      case .opacity:
        sample.opacity *= visibleProgress
      case let .move(edge, distance):
        let displacement = distance * (1 - visibleProgress)
        let vector = offset(for: edge, distance: displacement)
        sample.offset += vector
      case let .reveal(edge):
        sample.revealFraction = min(sample.revealFraction, visibleProgress)
        sample.revealEdge = edge
      case let .wipe(edge):
        sample.wipeFraction = min(sample.wipeFraction, visibleProgress)
        sample.wipeEdge = edge
      case let .symbolFrames(frames):
        sample.symbol = frames.frame(at: visibleProgress)
      }
    }
    return sample
  }

  private init(effect: TransitionEffect) {
    self.init(insertionEffects: [effect], removalEffects: [effect])
  }

  private func offset(for edge: TransitionEdge, distance: Double) -> AnimatablePair<Double, Double> {
    switch edge {
    case .top: AnimatablePair(0, -distance)
    case .leading: AnimatablePair(-distance, 0)
    case .bottom: AnimatablePair(0, distance)
    case .trailing: AnimatablePair(distance, 0)
    }
  }

  private static func unique(_ effects: [TransitionEffect]) -> [TransitionEffect] {
    var seen: Set<TransitionEffect> = []
    return effects.filter { seen.insert($0).inserted }
  }

  private static func reducedEffects(_ effects: [TransitionEffect]) -> [TransitionEffect] {
    let nonSpatial = effects.compactMap { effect -> TransitionEffect? in
      switch effect {
      case let .symbolFrames(frames): .symbolFrames(frames.reducedForMotion)
      default: effect.isSpatial ? nil : effect
      }
    }
    if nonSpatial.isEmpty, effects.contains(where: \TransitionEffect.isSpatial) {
      return [.opacity]
    }
    return nonSpatial
  }
}
