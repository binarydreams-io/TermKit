@testable import TermKit
import Testing

struct AnimationTests {
  @Test
  func `Linear animation samples deterministically`() {
    let animation = Animation.linear(duration: .seconds(1))

    #expect(animation.value(at: .zero) == 0)
    #expect(animation.value(at: .milliseconds(250)) == 0.25)
    #expect(animation.value(at: .milliseconds(500)) == 0.5)
    #expect(animation.sample(at: .seconds(1)).isComplete)
  }

  @Test
  func `Standard easing curves have their expected midpoint relationship`() {
    let instant = TimeSpan.milliseconds(500)
    let easeIn = Animation.easeIn(duration: .seconds(1)).value(at: instant)
    let easeOut = Animation.easeOut(duration: .seconds(1)).value(at: instant)
    let easeInOut = Animation.easeInOut(duration: .seconds(1)).value(at: instant)

    #expect(easeIn < 0.5)
    #expect(easeOut > 0.5)
    #expect(abs(easeInOut - 0.5) < 0.000_001)
  }

  @Test
  func `Cubic Bezier uses time on the x axis`() {
    let animation = Animation.cubicBezier(0.25, 0.1, 0.25, 1, duration: .seconds(1))
    let sample = animation.sample(at: .milliseconds(500))

    #expect(abs(sample.value - 0.802_403_4) < 0.000_001)
    #expect(sample.velocity > 0)
  }

  @Test
  func `Spring settles at its final value`() {
    let animation = Animation.spring(response: .milliseconds(500), dampingFraction: 0.7)
    let middle = animation.sample(at: .milliseconds(500))
    let settled = animation.sample(at: animation.duration)

    #expect(middle.value > 0.9)
    #expect(settled.value == 1)
    #expect(settled.velocity == 0)
    #expect(settled.isComplete)
  }

  @Test
  func `Default component transition uses the specified duration range`() {
    let duration = Animation.defaultComponentTransition.duration

    #expect(duration >= .milliseconds(120))
    #expect(duration <= .milliseconds(220))
  }
}
