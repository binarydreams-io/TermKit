@testable import TermKit
import Testing

@MainActor
struct TransactionTests {
  @Test
  func `withAnimation scopes the current task transaction`() {
    let outer = Transaction.current
    let animation = Animation.linear(duration: .milliseconds(200))

    let inner = withAnimation(animation) {
      Transaction.current
    }

    #expect(inner.animation == animation)
    #expect(Transaction.current.animation == outer.animation)
  }
}
