import Testing

@testable import TermKit

struct MotionEnvironmentValuesTests {
    @Test("Motion values override transaction policy")
    func transactionPolicy() {
        let motion = MotionEnvironmentValues(animationsEnabled: false, reduceMotion: true)

        let transaction = motion.transaction(from: Transaction(animation: .default))

        #expect(transaction.areAnimationsEnabled == false)
        #expect(transaction.isReducedMotionEnabled)
        #expect(transaction.animation == nil)
    }

    @MainActor
    @Test("Motion values round-trip through the view environment")
    func viewEnvironment() {
        var environment = EnvironmentValues()
        environment.motion = MotionEnvironmentValues(animationsEnabled: false, reduceMotion: true)

        #expect(environment.areAnimationsEnabled == false)
        #expect(environment.isReducedMotionEnabled)
    }
}
