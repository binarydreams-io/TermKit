import Testing
@testable import TUIFoundation

struct ConcurrencyDiagnosticsTests {
    @Test func lockedStateProtectsConcurrentMutation() async {
        let state = LockedState(0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    state.withLock { $0 += 1 }
                }
            }
        }

        #expect(state.withLock { $0 } == 100)
    }

    @Test func diagnosticsCounterIncrementsAndResets() async {
        let counter = DiagnosticsCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    counter.increment(by: 2)
                }
            }
        }

        #expect(counter.value == 200)
        #expect(counter.reset() == 200)
        #expect(counter.value == 0)
    }
}
