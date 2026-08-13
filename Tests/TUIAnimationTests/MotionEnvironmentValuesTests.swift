import TUIViewGraph
import Testing

@testable import TUIAnimation

struct MotionEnvironmentValuesTests {
    @Test("Motion values override transaction policy")
    func transactionPolicy() {
        let motion = MotionEnvironmentValues(animationsEnabled: false, reduceMotion: true)

        let transaction = motion.transaction(from: Transaction(animation: .default))

        #expect(transaction.animationsEnabled == false)
        #expect(transaction.reduceMotion)
        #expect(transaction.animation == nil)
    }

    @MainActor
    @Test("Motion values round-trip through the view environment")
    func viewEnvironment() {
        var environment = EnvironmentValues()
        environment.motion = MotionEnvironmentValues(animationsEnabled: false, reduceMotion: true)

        #expect(environment.animationsEnabled == false)
        #expect(environment.reduceMotion)
    }
}
