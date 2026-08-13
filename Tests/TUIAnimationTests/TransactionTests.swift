import TUIFoundation
import Testing

@testable import TUIAnimation

@MainActor
struct TransactionTests {
    @Test("withAnimation scopes the current task transaction")
    func taskLocalTransaction() {
        let outer = Transaction.current
        let animation = Animation.linear(duration: .milliseconds(200))

        let inner = withAnimation(animation) {
            Transaction.current
        }

        #expect(inner.animation == animation)
        #expect(Transaction.current.animation == outer.animation)
    }
}
