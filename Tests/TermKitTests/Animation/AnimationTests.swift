import Testing

@testable import TermKit

struct AnimationTests {
    @Test("Linear animation samples deterministically")
    func linearCurve() {
        let animation = Animation.linear(duration: .seconds(1))

        #expect(animation.value(at: .zero) == 0)
        #expect(animation.value(at: .milliseconds(250)) == 0.25)
        #expect(animation.value(at: .milliseconds(500)) == 0.5)
        #expect(animation.sample(at: .seconds(1)).isComplete)
    }

    @Test("Standard easing curves have their expected midpoint relationship")
    func easingCurves() {
        let instant = TimeSpan.milliseconds(500)
        let easeIn = Animation.easeIn(duration: .seconds(1)).value(at: instant)
        let easeOut = Animation.easeOut(duration: .seconds(1)).value(at: instant)
        let easeInOut = Animation.easeInOut(duration: .seconds(1)).value(at: instant)

        #expect(easeIn < 0.5)
        #expect(easeOut > 0.5)
        #expect(abs(easeInOut - 0.5) < 0.000_001)
    }

    @Test("Cubic Bezier uses time on the x axis")
    func cubicBezierCurve() {
        let animation = Animation.cubicBezier(0.25, 0.1, 0.25, 1, duration: .seconds(1))
        let sample = animation.sample(at: .milliseconds(500))

        #expect(abs(sample.value - 0.802_403_4) < 0.000_001)
        #expect(sample.velocity > 0)
    }

    @Test("Spring settles at its final value")
    func springSettles() {
        let animation = Animation.spring(response: .milliseconds(500), dampingFraction: 0.7)
        let middle = animation.sample(at: .milliseconds(500))
        let settled = animation.sample(at: animation.duration)

        #expect(middle.value > 0.9)
        #expect(settled.value == 1)
        #expect(settled.velocity == 0)
        #expect(settled.isComplete)
    }

    @Test("Default component transition uses the specified duration range")
    func defaultComponentTransitionDuration() {
        let duration = Animation.defaultComponentTransition.duration

        #expect(duration >= .milliseconds(120))
        #expect(duration <= .milliseconds(220))
    }
}
