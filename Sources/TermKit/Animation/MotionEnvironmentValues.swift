/// Motion preferences supplied by a view environment or runtime.
public struct MotionEnvironmentValues: Sendable, Hashable {
    /// A value that indicates whether animations can run.
    public var areAnimationsEnabled: Bool

    /// A value that indicates whether spatial motion must be reduced.
    public var isReducedMotionEnabled: Bool

    /// Creates motion preferences.
    public init(animationsEnabled: Bool = true, reduceMotion: Bool = false) {
        areAnimationsEnabled = animationsEnabled
        isReducedMotionEnabled = reduceMotion
    }

    /// Returns a transaction that includes these motion preferences.
    /// - Complexity: O(1).
    public func transaction(from base: Transaction = .current) -> Transaction {
        var transaction = base
        transaction.areAnimationsEnabled = areAnimationsEnabled
        transaction.isReducedMotionEnabled = isReducedMotionEnabled
        if areAnimationsEnabled == false {
            transaction.animation = nil
        }
        return transaction
    }
}

struct AnimationsEnabledEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

struct ReduceMotionEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

@MainActor
extension EnvironmentValues {
    /// The motion preferences in the current view environment.
    public var motion: MotionEnvironmentValues {
        get {
            MotionEnvironmentValues(
                animationsEnabled: self[AnimationsEnabledEnvironmentKey.self],
                reduceMotion: self[ReduceMotionEnvironmentKey.self]
            )
        }
        set {
            self[AnimationsEnabledEnvironmentKey.self] = newValue.areAnimationsEnabled
            self[ReduceMotionEnvironmentKey.self] = newValue.isReducedMotionEnabled
        }
    }

    /// A value that indicates whether animations can run in the current environment.
    public var areAnimationsEnabled: Bool {
        get { self[AnimationsEnabledEnvironmentKey.self] }
        set { self[AnimationsEnabledEnvironmentKey.self] = newValue }
    }

    /// A value that indicates whether the current environment must reduce spatial motion.
    public var isReducedMotionEnabled: Bool {
        get { self[ReduceMotionEnvironmentKey.self] }
        set { self[ReduceMotionEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Sets the motion preferences for this view and its descendants.
    /// - Complexity: O(1).
    public func motion(_ values: MotionEnvironmentValues) -> some View {
        environment(AnimationsEnabledEnvironmentKey.self, value: values.areAnimationsEnabled)
            .environment(ReduceMotionEnvironmentKey.self, value: values.isReducedMotionEnabled)
    }

    /// Enables or disables animations for this view and its descendants.
    /// - Complexity: O(1).
    public func animationsEnabled(_ isEnabled: Bool) -> some View {
        environment(AnimationsEnabledEnvironmentKey.self, value: isEnabled)
    }

    /// Sets reduced-motion behavior for this view and its descendants.
    /// - Complexity: O(1).
    public func reduceMotion(_ isEnabled: Bool) -> some View {
        environment(ReduceMotionEnvironmentKey.self, value: isEnabled)
    }
}
