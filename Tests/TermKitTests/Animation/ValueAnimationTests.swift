@testable import TermKit
import Testing

struct ValueAnimationTests {
  @Test
  func `Value animation preserves the transaction until its value changes`() {
    let baseAnimation = Animation.linear(duration: .seconds(1))
    let base = Transaction(animation: baseAnimation, reduceMotion: true)
    var scoped = ValueAnimation<Int>(.easeOut(duration: .milliseconds(180)), value: 1)

    let transaction = scoped.transaction(for: 1, from: base)

    #expect(transaction.animation == baseAnimation)
    #expect(transaction.isReducedMotionEnabled)
  }

  @Test
  func `Value animation injects its animation only after a value change`() {
    let animation = Animation.easeOut(duration: .milliseconds(180))
    var scoped = ValueAnimation(animation, value: "idle")

    let changed = scoped.transaction(for: "running", from: Transaction())
    let unchanged = scoped.transaction(for: "running", from: Transaction())

    #expect(changed.animation == animation)
    #expect(unchanged.animation == nil)
    #expect(scoped.value == "running")
  }

  @Test
  func `Disabled value animation never injects an animation`() {
    var scoped = ValueAnimation(.default, value: false)

    let transaction = scoped.transaction(
      for: true,
      from: Transaction(animationsEnabled: false)
    )

    #expect(transaction.animation == nil)
    #expect(scoped.value)
  }
}
