import TUIFoundation
import TUIViewGraph
import Testing

@testable import TUIAnimation

@MainActor
private final class CompletionRecorder {
    var count = 0

    func record() {
        count += 1
    }
}

@MainActor
struct AnimationTrackTests {
    @Test("Retargeting starts at the current presentation value")
    func retargetHasNoJump() {
        let animation = Animation.linear(duration: .seconds(1))
        var track = AnimationTrack(from: 0.0, to: 10.0, at: .zero, animation: animation)
        let interruption = TimeInstant.zero.advanced(by: .milliseconds(400))

        let before = track.sample(at: interruption)
        let retargeted = track.retarget(to: 20, at: interruption, animation: animation)
        let after = track.sample(at: interruption)

        #expect(before == 4)
        #expect(retargeted == before)
        #expect(after == before)
        #expect(track.startValue == before)
    }

    @Test("Retargeting drops the interrupted completion")
    func retargetCancelsPriorCompletion() {
        let interrupted = CompletionRecorder()
        let completed = CompletionRecorder()
        let animation = Animation.linear(duration: .seconds(1))
        var track = AnimationTrack(
            from: 0.0,
            to: 10.0,
            at: .zero,
            animation: animation,
            completion: { interrupted.record() }
        )
        let interruption = TimeInstant.zero.advanced(by: .milliseconds(400))

        _ = track.retarget(
            to: 20,
            at: interruption,
            animation: animation,
            completion: { completed.record() }
        )
        _ = track.sample(at: interruption.advanced(by: .seconds(1)))

        #expect(interrupted.count == 0)
        #expect(completed.count == 1)
    }

    @Test("Completion runs once after a track finishes")
    func completion() {
        let recorder = CompletionRecorder()
        var track = AnimationTrack(
            from: 0.0,
            to: 1.0,
            at: .zero,
            animation: .linear(duration: .milliseconds(100)),
            completion: { recorder.record() }
        )

        _ = track.sample(at: .zero.advanced(by: .milliseconds(100)))
        _ = track.sample(at: .zero.advanced(by: .milliseconds(200)))

        #expect(track.status == .completed)
        #expect(recorder.count == 1)
    }

    @Test("Cancellation preserves the current value and drops completion")
    func cancellation() {
        let recorder = CompletionRecorder()
        var track = AnimationTrack(
            from: 0.0,
            to: 10.0,
            at: .zero,
            animation: .linear(duration: .seconds(1)),
            completion: { recorder.record() }
        )
        let instant = TimeInstant.zero.advanced(by: .milliseconds(250))
        let sampled = track.sample(at: instant)

        track.cancel()
        let afterCancellation = track.sample(at: .zero.advanced(by: .seconds(1)))

        #expect(track.status == .cancelled)
        #expect(afterCancellation == sampled)
        #expect(recorder.count == 0)
    }

    @Test("Disabled animation reaches its target immediately")
    func disabledAnimation() {
        let recorder = CompletionRecorder()
        let transaction = Transaction(
            animation: .linear(duration: .seconds(1)),
            animationsEnabled: false,
            completion: { recorder.record() }
        )
        let track = AnimationTrack(from: 0.0, to: 5.0, at: .zero, transaction: transaction)

        #expect(track.currentValue == 5)
        #expect(track.status == .completed)
        #expect(recorder.count == 1)
    }

    @Test("Store completion observes completed state and can retarget the same key")
    func storeDefersAnimatedCompletionUntilAfterMutation() {
        let store = AnimationTrackStore()
        let key = AnimationTrackKey(nodeID: NodeID(rawValue: 1), property: "opacity")
        var observedStatus: AnimationTrackStatus?
        let transaction = Transaction(
            animation: .linear(duration: .seconds(1)),
            completion: {
                observedStatus = store.status(for: key)
                _ = store.retarget(key, to: 20.0, at: .zero, transaction: Transaction(animation: nil))
            }
        )
        _ = store.setTarget(10.0, from: 0.0, for: key, at: .zero, transaction: transaction)

        let completedValue = store.sample(key, as: Double.self, at: .zero.advanced(by: .seconds(1)))
        let retargetedValue = store.sample(key, as: Double.self, at: .zero.advanced(by: .seconds(1)))

        #expect(completedValue == 10)
        #expect(observedStatus == .completed)
        #expect(retargetedValue == 20)
    }

    @Test("Store inserts an immediate track before completion and preserves callback removal")
    func storeDefersImmediateCompletionUntilAfterInsertion() {
        let store = AnimationTrackStore()
        let key = AnimationTrackKey(nodeID: NodeID(rawValue: 2), property: "offset")
        var observedStatus: AnimationTrackStatus?
        let transaction = Transaction(animation: nil) {
            observedStatus = store.status(for: key)
            store.remove(key)
        }

        let value = store.setTarget(5.0, from: 0.0, for: key, at: .zero, transaction: transaction)

        #expect(value == 5)
        #expect(observedStatus == .completed)
        #expect(store.status(for: key) == nil)
        #expect(store.count == 0)
    }

    @Test("A scoped completion waits for every animated track")
    func transactionCompletionWaitsForAllTracks() {
        let recorder = CompletionRecorder()
        let store = AnimationTrackStore()
        let firstKey = AnimationTrackKey(nodeID: NodeID(rawValue: 3), property: "first")
        let secondKey = AnimationTrackKey(nodeID: NodeID(rawValue: 3), property: "second")

        let transaction = Transaction(
            animation: .linear(duration: .seconds(1)),
            completion: { recorder.record() }
        )
        withTransaction(transaction) {
            store.setTarget(1.0, from: 0.0, for: firstKey, at: .zero)
            store.setTarget(2.0, from: 0.0, for: secondKey, at: .zero)
        }

        #expect(recorder.count == 0)
        _ = store.sample(firstKey, as: Double.self, at: .zero.advanced(by: .seconds(1)))
        #expect(recorder.count == 0)
        _ = store.sample(secondKey, as: Double.self, at: .zero.advanced(by: .seconds(1)))
        #expect(recorder.count == 1)
    }

    @Test("A cancelled track suppresses its scoped completion")
    func transactionCancellationSuppressesCompletion() {
        let recorder = CompletionRecorder()
        let store = AnimationTrackStore()
        let firstKey = AnimationTrackKey(nodeID: NodeID(rawValue: 4), property: "first")
        let secondKey = AnimationTrackKey(nodeID: NodeID(rawValue: 4), property: "second")

        withAnimation(.linear(duration: .seconds(1)), completion: { recorder.record() }) {
            store.setTarget(1.0, from: 0.0, for: firstKey, at: .zero)
            store.setTarget(2.0, from: 0.0, for: secondKey, at: .zero)
        }

        store.cancel(firstKey)
        _ = store.sample(secondKey, as: Double.self, at: .zero.advanced(by: .seconds(1)))

        #expect(recorder.count == 0)
    }

    @Test("Spring retargeting preserves scalar velocity")
    func springRetargetPreservesVelocity() {
        let spring = Animation.spring(response: .seconds(1), dampingFraction: 0.7)
        var track = AnimationTrack(from: 0.0, to: 10.0, at: .zero, animation: spring)
        let interruption = TimeInstant.zero.advanced(by: .milliseconds(200))

        _ = track.sample(at: interruption)
        let velocityBeforeRetarget = track.velocity
        var zeroVelocityTrack = AnimationTrack(
            from: track.currentValue,
            to: 20,
            at: interruption,
            animation: spring
        )
        _ = track.retarget(to: 20, at: interruption, animation: spring)
        let velocityAfterRetarget = track.velocity
        let nextInstant = interruption.advanced(by: .milliseconds(10))
        let velocityPreservingValue = track.sample(at: nextInstant)
        let zeroVelocityValue = zeroVelocityTrack.sample(at: nextInstant)

        #expect(abs(velocityAfterRetarget - velocityBeforeRetarget) < 1e-12)
        #expect(abs(velocityBeforeRetarget) > 1)
        #expect(velocityPreservingValue > zeroVelocityValue)
    }
}
