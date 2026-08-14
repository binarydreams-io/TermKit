import Foundation

/// A timing curve used to sample animation progress.
public enum AnimationCurve: Sendable, Hashable {
    /// Progresses at a constant rate.
    case linear
    /// Progresses along a cubic Bezier curve.
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)
    /// Progresses according to a damped spring response.
    case spring(response: TimeSpan, dampingFraction: Double)
}

/// A sampled animation value and velocity.
public struct AnimationSample: Sendable, Hashable {
    /// The normalized animation value.
    public var value: Double
    /// The value velocity per second.
    public var velocity: Double
    /// A value that indicates whether the animation reached its duration.
    public var isComplete: Bool

    /// Creates an animation sample.
    public init(value: Double, velocity: Double, isComplete: Bool) {
        self.value = value
        self.velocity = velocity
        self.isComplete = isComplete
    }
}

/// A duration and timing curve used to animate values.
public struct Animation: Sendable, Hashable {
    /// The default animation.
    public static let `default` = easeInOut(duration: .milliseconds(350))
    /// The standard 180-millisecond animation for component transitions.
    public static let defaultComponentTransition = easeOut(duration: .milliseconds(180))

    /// The timing curve.
    public var curve: AnimationCurve
    /// The total animation duration.
    public var duration: TimeSpan

    /// Creates a linear animation.
    /// - Complexity: O(1).
    public static func linear(duration: TimeSpan = .milliseconds(350)) -> Animation {
        Animation(curve: .linear, duration: duration)
    }

    /// Creates an accelerating animation.
    /// - Complexity: O(1).
    public static func easeIn(duration: TimeSpan = .milliseconds(350)) -> Animation {
        cubicBezier(0.42, 0, 1, 1, duration: duration)
    }

    /// Creates a decelerating animation.
    /// - Complexity: O(1).
    public static func easeOut(duration: TimeSpan = .milliseconds(350)) -> Animation {
        cubicBezier(0, 0, 0.58, 1, duration: duration)
    }

    /// Creates an animation that accelerates and then decelerates.
    /// - Complexity: O(1).
    public static func easeInOut(duration: TimeSpan = .milliseconds(350)) -> Animation {
        cubicBezier(0.42, 0, 0.58, 1, duration: duration)
    }

    /// Creates a cubic Bezier animation from unlabeled control points.
    /// - Complexity: O(1).
    public static func cubicBezier(
        _ x1: Double,
        _ y1: Double,
        _ x2: Double,
        _ y2: Double,
        duration: TimeSpan = .milliseconds(350)
    ) -> Animation {
        precondition((0...1).contains(x1) && (0...1).contains(x2), "Bezier x control points must be between zero and one.")
        precondition(y1.isFinite && y2.isFinite, "Bezier y control points must be finite.")
        return Animation(curve: .cubicBezier(x1: x1, y1: y1, x2: x2, y2: y2), duration: duration)
    }

    /// Creates a cubic Bezier animation from labeled control points.
    /// - Complexity: O(1).
    public static func cubicBezier(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double,
        duration: TimeSpan = .milliseconds(350)
    ) -> Animation {
        cubicBezier(x1, y1, x2, y2, duration: duration)
    }

    /// Creates a damped spring animation.
    /// - Complexity: O(1).
    public static func spring(
        response: TimeSpan = .milliseconds(500),
        dampingFraction: Double = 0.825
    ) -> Animation {
        precondition(response > .zero, "A spring response must be positive.")
        precondition(dampingFraction.isFinite && dampingFraction > 0, "A spring damping fraction must be positive and finite.")
        let duration = springSettlingDuration(response: response, dampingFraction: dampingFraction)
        return Animation(curve: .spring(response: response, dampingFraction: dampingFraction), duration: duration)
    }

    /// Creates an animation from a curve and duration.
    public init(curve: AnimationCurve, duration: TimeSpan) {
        precondition(duration > .zero, "An animation duration must be positive.")
        switch curve {
        case .linear:
            break
        case .cubicBezier(let x1, let y1, let x2, let y2):
            precondition(
                (0...1).contains(x1) && (0...1).contains(x2) && y1.isFinite && y2.isFinite,
                "Bezier control points must be valid and finite."
            )
        case .spring(let response, let dampingFraction):
            precondition(response > .zero, "A spring response must be positive.")
            precondition(
                dampingFraction.isFinite && dampingFraction > 0,
                "A spring damping fraction must be positive and finite."
            )
        }
        self.curve = curve
        self.duration = duration
    }

    /// Samples the animation at elapsed time.
    /// - Complexity: O(1).
    public func sample(at elapsed: TimeSpan) -> AnimationSample {
        if elapsed >= duration {
            return AnimationSample(value: 1, velocity: 0, isComplete: true)
        }

        let elapsedSeconds = max(0, elapsed.seconds)
        switch curve {
        case .linear:
            return AnimationSample(
                value: elapsedSeconds / duration.seconds,
                velocity: 1 / duration.seconds,
                isComplete: false
            )
        case .cubicBezier(let x1, let y1, let x2, let y2):
            return cubicBezierSample(
                elapsedSeconds: elapsedSeconds,
                durationSeconds: duration.seconds,
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2
            )
        case .spring(let response, let dampingFraction):
            let response = springResponse(
                at: elapsedSeconds,
                responseSeconds: response.seconds,
                dampingFraction: dampingFraction
            )
            return AnimationSample(value: response.value, velocity: response.velocity, isComplete: false)
        }
    }

    /// Returns normalized progress at elapsed time.
    /// - Complexity: O(1).
    public func value(at elapsed: TimeSpan) -> Double {
        sample(at: elapsed).value
    }
}

extension Animation {
    struct SpringMotionSample {
        var displacementScale: Double
        var initialVelocityScale: Double
        var displacementVelocityScale: Double
        var initialVelocityVelocityScale: Double
    }

    func springMotionSample(at elapsed: TimeSpan) -> SpringMotionSample? {
        guard case .spring(let response, let dampingFraction) = curve else { return nil }
        return springMotionSample(
            at: max(0, elapsed.seconds),
            responseSeconds: response.seconds,
            dampingFraction: dampingFraction
        )
    }

    fileprivate static func springSettlingDuration(response: TimeSpan, dampingFraction: Double) -> TimeSpan {
        let angularFrequency = 2 * Double.pi / response.seconds
        let epsilon = 0.001
        let seconds: Double

        if dampingFraction < 1 {
            let envelopeScale = 1 / sqrt(1 - dampingFraction * dampingFraction)
            seconds = log(envelopeScale / epsilon) / (dampingFraction * angularFrequency)
        } else if dampingFraction == 1 {
            seconds = 2 * response.seconds
        } else {
            let root = sqrt(dampingFraction * dampingFraction - 1)
            let slowRate = angularFrequency * (dampingFraction - root)
            let slowCoefficient = (dampingFraction + root) / (2 * root)
            seconds = log(slowCoefficient / epsilon) / slowRate
        }

        return .seconds(max(response.seconds, seconds))
    }

    fileprivate func cubicBezierSample(
        elapsedSeconds: Double,
        durationSeconds: Double,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> AnimationSample {
        let x = elapsedSeconds / durationSeconds
        var parameter = x

        for _ in 0..<8 {
            let error = bezier(parameter, control1: x1, control2: x2) - x
            let derivative = bezierDerivative(parameter, control1: x1, control2: x2)
            guard abs(derivative) > 1e-7 else { break }
            let candidate = parameter - error / derivative
            guard (0...1).contains(candidate) else { break }
            parameter = candidate
        }

        var lower = 0.0
        var upper = 1.0
        for _ in 0..<24 {
            if bezier(parameter, control1: x1, control2: x2) < x {
                lower = parameter
            } else {
                upper = parameter
            }
            parameter = (lower + upper) / 2
        }

        let value = bezier(parameter, control1: y1, control2: y2)
        let dx = bezierDerivative(parameter, control1: x1, control2: x2)
        let dy = bezierDerivative(parameter, control1: y1, control2: y2)
        let velocity = abs(dx) > 1e-9 ? dy / dx / durationSeconds : 0
        return AnimationSample(value: value, velocity: velocity, isComplete: false)
    }

    fileprivate func bezier(_ parameter: Double, control1: Double, control2: Double) -> Double {
        let inverse = 1 - parameter
        return 3 * inverse * inverse * parameter * control1
            + 3 * inverse * parameter * parameter * control2
            + parameter * parameter * parameter
    }

    fileprivate func bezierDerivative(_ parameter: Double, control1: Double, control2: Double) -> Double {
        let inverse = 1 - parameter
        return 3 * inverse * inverse * control1
            + 6 * inverse * parameter * (control2 - control1)
            + 3 * parameter * parameter * (1 - control2)
    }

    fileprivate func springResponse(
        at time: Double,
        responseSeconds: Double,
        dampingFraction: Double
    ) -> (value: Double, velocity: Double) {
        let sample = springMotionSample(
            at: time,
            responseSeconds: responseSeconds,
            dampingFraction: dampingFraction
        )
        return (1 - sample.displacementScale, -sample.displacementVelocityScale)
    }

    fileprivate func springMotionSample(
        at time: Double,
        responseSeconds: Double,
        dampingFraction: Double
    ) -> SpringMotionSample {
        let frequency = 2 * Double.pi / responseSeconds

        if dampingFraction < 1 {
            let root = sqrt(1 - dampingFraction * dampingFraction)
            let dampedFrequency = frequency * root
            let decayRate = dampingFraction * frequency
            let coefficient = dampingFraction / root
            let decay = exp(-decayRate * time)
            let cosine = cos(dampedFrequency * time)
            let sine = sin(dampedFrequency * time)
            let error = decay * (cosine + coefficient * sine)
            let errorDerivative =
                decay
                * (-decayRate * (cosine + coefficient * sine)
                    - dampedFrequency * sine
                    + coefficient * dampedFrequency * cosine)
            return SpringMotionSample(
                displacementScale: error,
                initialVelocityScale: decay * sine / dampedFrequency,
                displacementVelocityScale: errorDerivative,
                initialVelocityVelocityScale: decay * (cosine - decayRate * sine / dampedFrequency)
            )
        }

        if dampingFraction == 1 {
            let decay = exp(-frequency * time)
            return SpringMotionSample(
                displacementScale: decay * (1 + frequency * time),
                initialVelocityScale: time * decay,
                displacementVelocityScale: -frequency * frequency * time * decay,
                initialVelocityVelocityScale: decay * (1 - frequency * time)
            )
        }

        let root = sqrt(dampingFraction * dampingFraction - 1)
        let firstRoot = -frequency * (dampingFraction - root)
        let secondRoot = -frequency * (dampingFraction + root)
        let denominator = firstRoot - secondRoot
        let firstCoefficient = -secondRoot / denominator
        let secondCoefficient = firstRoot / denominator
        let firstExponential = exp(firstRoot * time)
        let secondExponential = exp(secondRoot * time)
        let firstTerm = firstCoefficient * firstExponential
        let secondTerm = secondCoefficient * secondExponential
        return SpringMotionSample(
            displacementScale: firstTerm + secondTerm,
            initialVelocityScale: (firstExponential - secondExponential) / denominator,
            displacementVelocityScale: firstRoot * firstTerm + secondRoot * secondTerm,
            initialVelocityVelocityScale: (firstRoot * firstExponential - secondRoot * secondExponential) / denominator
        )
    }
}
