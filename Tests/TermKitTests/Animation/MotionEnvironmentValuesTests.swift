@testable import TermKit
import Testing

struct MotionEnvironmentValuesTests {
  @Test
  func `Motion values override transaction policy`() {
    let motion = MotionEnvironmentValues(animationsEnabled: false, reduceMotion: true)

    let transaction = motion.transaction(from: Transaction(animation: .default))

    #expect(transaction.areAnimationsEnabled == false)
    #expect(transaction.isReducedMotionEnabled)
    #expect(transaction.animation == nil)
  }

  @MainActor
  @Test
  func `Motion values round-trip through the view environment`() {
    var environment = EnvironmentValues()
    environment.motion = MotionEnvironmentValues(animationsEnabled: false, reduceMotion: true)

    #expect(environment.areAnimationsEnabled == false)
    #expect(environment.isReducedMotionEnabled)
  }
}
