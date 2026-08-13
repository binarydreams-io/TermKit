import TUIFoundation

/// A deterministic sequence of symbols for transitions and timeline-driven effects.
public struct SymbolFrames: Sendable, Hashable {
    /// The animated symbols in display order.
    public let frames: [String]
    /// The symbol to display when motion is unavailable.
    public let fallback: String

    /// Creates a symbol sequence with a required static fallback.
    public init(_ frames: [String], fallback: String? = nil) {
        precondition(frames.isEmpty == false, "Symbol frames must not be empty.")
        self.frames = frames
        self.fallback = fallback ?? frames[0]
    }

    /// Returns the symbol at normalized progress.
    public func frame(at progress: Double, reduceMotion: Bool = false) -> String {
        guard reduceMotion == false else { return fallback }
        let progress = min(1, max(0, progress))
        let index = min(frames.count - 1, Int(progress * Double(frames.count)))
        return frames[index]
    }

    /// Returns the symbol for an externally supplied timeline instant.
    public func frame(
        at instant: TimeInstant,
        startingAt start: TimeInstant,
        interval: TUIDuration,
        motion: MotionEnvironmentValues = MotionEnvironmentValues()
    ) -> String {
        precondition(interval > .zero, "A symbol frame interval must be positive.")
        guard motion.animationsEnabled, motion.reduceMotion == false else { return fallback }
        guard instant >= start else { return frames[0] }
        let elapsed = start.duration(to: instant).nanoseconds
        return frames[Int((elapsed / interval.nanoseconds) % Int64(frames.count))]
    }

    fileprivate var reducedForMotion: SymbolFrames {
        SymbolFrames([fallback], fallback: fallback)
    }
}

public enum TransitionEdge: Sendable, Hashable {
    case top
    case leading
    case bottom
    case trailing
}

public enum TransitionEffect: Sendable, Hashable {
    case opacity
    case move(edge: TransitionEdge, distance: Double)
    case reveal(edge: TransitionEdge)
    case wipe(edge: TransitionEdge)
    case symbolFrames(SymbolFrames)

    public var isSpatial: Bool {
        switch self {
        case .opacity, .symbolFrames: false
        case .move, .reveal, .wipe: true
        }
    }
}

public enum TransitionPhase: Sendable, Hashable {
    case insertion
    case removal
}

public struct TransitionSample: Sendable, Hashable {
    public var opacity: Double
    public var offset: AnimatablePair<Double, Double>
    public var revealFraction: Double
    public var revealEdge: TransitionEdge?
    public var wipeFraction: Double
    public var wipeEdge: TransitionEdge?
    public var symbol: String?

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

public struct AnyTransition: Sendable, Hashable {
    public static let identity = AnyTransition()
    public static let opacity = AnyTransition(effect: .opacity)

    public let insertionEffects: [TransitionEffect]
    public let removalEffects: [TransitionEffect]

    public static func move(edge: TransitionEdge, distance: Double = 1) -> AnyTransition {
        precondition(distance.isFinite && distance >= 0, "A transition distance must be finite and nonnegative.")
        return AnyTransition(effect: .move(edge: edge, distance: distance))
    }

    public static func reveal(edge: TransitionEdge = .top) -> AnyTransition {
        AnyTransition(effect: .reveal(edge: edge))
    }

    public static func wipe(edge: TransitionEdge = .leading) -> AnyTransition {
        AnyTransition(effect: .wipe(edge: edge))
    }

    public static func symbolFrames(_ frames: SymbolFrames) -> AnyTransition {
        AnyTransition(effect: .symbolFrames(frames))
    }

    public static func asymmetric(
        insertion: AnyTransition,
        removal: AnyTransition
    ) -> AnyTransition {
        AnyTransition(
            insertionEffects: insertion.insertionEffects,
            removalEffects: removal.removalEffects
        )
    }

    public init(
        insertionEffects: [TransitionEffect] = [],
        removalEffects: [TransitionEffect] = []
    ) {
        self.insertionEffects = Self.unique(insertionEffects)
        self.removalEffects = Self.unique(removalEffects)
    }

    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(
            insertionEffects: insertionEffects + other.insertionEffects,
            removalEffects: removalEffects + other.removalEffects
        )
    }

    public func reducedForMotion() -> AnyTransition {
        return AnyTransition(
            insertionEffects: Self.reducedEffects(insertionEffects),
            removalEffects: Self.reducedEffects(removalEffects)
        )
    }

    public func resolved(for transaction: Transaction) -> AnyTransition {
        guard transaction.animationsEnabled, transaction.animation != nil else { return .identity }
        return transaction.reduceMotion ? reducedForMotion() : self
    }

    public func sample(phase: TransitionPhase, progress: Double) -> TransitionSample {
        let clampedProgress = min(1, max(0, progress))
        let visibleProgress = phase == .insertion ? clampedProgress : 1 - clampedProgress
        let effects = phase == .insertion ? insertionEffects : removalEffects
        var sample = TransitionSample()

        for effect in effects {
            switch effect {
            case .opacity:
                sample.opacity *= visibleProgress
            case .move(let edge, let distance):
                let displacement = distance * (1 - visibleProgress)
                let vector = offset(for: edge, distance: displacement)
                sample.offset += vector
            case .reveal(let edge):
                sample.revealFraction = min(sample.revealFraction, visibleProgress)
                sample.revealEdge = edge
            case .wipe(let edge):
                sample.wipeFraction = min(sample.wipeFraction, visibleProgress)
                sample.wipeEdge = edge
            case .symbolFrames(let frames):
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
            case .symbolFrames(let frames): .symbolFrames(frames.reducedForMotion)
            default: effect.isSpatial ? nil : effect
            }
        }
        if nonSpatial.isEmpty && effects.contains(where: \TransitionEffect.isSpatial) {
            return [.opacity]
        }
        return nonSpatial
    }
}
