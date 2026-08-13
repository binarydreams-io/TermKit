import TUIViewGraph

/// Motion preferences supplied by a view environment or runtime.
public struct MotionEnvironmentValues: Sendable, Hashable {
    /// A value that indicates whether animations can run.
    public var animationsEnabled: Bool

    /// A value that indicates whether spatial motion must be reduced.
    public var reduceMotion: Bool

    /// Creates motion preferences.
    public init(animationsEnabled: Bool = true, reduceMotion: Bool = false) {
        self.animationsEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
    }

    /// Returns a transaction that includes these motion preferences.
    public func transaction(from base: Transaction = .current) -> Transaction {
        var transaction = base
        transaction.animationsEnabled = animationsEnabled
        transaction.reduceMotion = reduceMotion
        if animationsEnabled == false {
            transaction.animation = nil
        }
        return transaction
    }
}

package struct AnimationsEnabledEnvironmentKey: EnvironmentKey {
    package static let defaultValue = true
}

package struct ReduceMotionEnvironmentKey: EnvironmentKey {
    package static let defaultValue = false
}

@MainActor
public extension EnvironmentValues {
    /// The motion preferences in the current view environment.
    var motion: MotionEnvironmentValues {
        get {
            MotionEnvironmentValues(
                animationsEnabled: self[AnimationsEnabledEnvironmentKey.self],
                reduceMotion: self[ReduceMotionEnvironmentKey.self]
            )
        }
        set {
            self[AnimationsEnabledEnvironmentKey.self] = newValue.animationsEnabled
            self[ReduceMotionEnvironmentKey.self] = newValue.reduceMotion
        }
    }

    /// A value that indicates whether animations can run in the current environment.
    var animationsEnabled: Bool {
        get { self[AnimationsEnabledEnvironmentKey.self] }
        set { self[AnimationsEnabledEnvironmentKey.self] = newValue }
    }

    /// A value that indicates whether the current environment must reduce spatial motion.
    var reduceMotion: Bool {
        get { self[ReduceMotionEnvironmentKey.self] }
        set { self[ReduceMotionEnvironmentKey.self] = newValue }
    }
}

public extension View {
    /// Sets the motion preferences for this view and its descendants.
    func motion(_ values: MotionEnvironmentValues) -> some View {
        environment(AnimationsEnabledEnvironmentKey.self, values.animationsEnabled)
            .environment(ReduceMotionEnvironmentKey.self, values.reduceMotion)
    }

    /// Enables or disables animations for this view and its descendants.
    func animationsEnabled(_ isEnabled: Bool) -> some View {
        environment(AnimationsEnabledEnvironmentKey.self, isEnabled)
    }

    /// Sets reduced-motion behavior for this view and its descendants.
    func reduceMotion(_ isEnabled: Bool) -> some View {
        environment(ReduceMotionEnvironmentKey.self, isEnabled)
    }
}
