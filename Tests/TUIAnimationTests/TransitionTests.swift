import TUIFoundation
import Testing

@testable import TUIAnimation

struct TransitionTests {
    @Test("Combined transition samples all effects")
    func combined() {
        let transition = AnyTransition.opacity.combined(with: .move(edge: .leading, distance: 4))
        let sample = transition.sample(phase: .insertion, progress: 0.25)

        #expect(sample.opacity == 0.25)
        #expect(sample.offset.first == -3)
        #expect(sample.offset.second == 0)
    }

    @Test("Asymmetric transition uses separate phase effects")
    func asymmetric() {
        let transition = AnyTransition.asymmetric(
            insertion: .reveal(edge: .top),
            removal: .wipe(edge: .trailing)
        )

        #expect(transition.insertionEffects == [.reveal(edge: .top)])
        #expect(transition.removalEffects == [.wipe(edge: .trailing)])
        #expect(transition.sample(phase: .insertion, progress: 0.5).revealFraction == 0.5)
        #expect(transition.sample(phase: .removal, progress: 0.5).wipeFraction == 0.5)
    }

    @Test("Reduced motion replaces spatial transitions with opacity")
    func reducedMotion() {
        let transition = AnyTransition.move(edge: .bottom).combined(with: .reveal(edge: .top))
        let transaction = Transaction(
            animation: .linear(duration: .milliseconds(200)),
            reduceMotion: true
        )
        let reduced = transition.resolved(for: transaction)

        #expect(reduced.insertionEffects == [.opacity])
        #expect(reduced.removalEffects == [.opacity])
    }

    @Test("Reduced motion preserves identity on an asymmetric phase")
    func asymmetricReducedMotion() {
        let transition = AnyTransition.asymmetric(
            insertion: .move(edge: .leading),
            removal: .identity
        )

        let reduced = transition.reducedForMotion()

        #expect(reduced.insertionEffects == [.opacity])
        #expect(reduced.removalEffects.isEmpty)
    }

    @Test("Disabled animations resolve transitions to identity")
    func disabledAnimations() {
        let transaction = Transaction(
            animation: .linear(duration: .milliseconds(200)),
            animationsEnabled: false
        )

        #expect(AnyTransition.opacity.resolved(for: transaction) == .identity)
    }

    @Test("Symbol frame transitions sample insertion and removal progress")
    func symbolFrameTransition() {
        let transition = AnyTransition.symbolFrames(SymbolFrames([".", "o", "O"], fallback: "-"))

        #expect(transition.sample(phase: .insertion, progress: 0).symbol == ".")
        #expect(transition.sample(phase: .insertion, progress: 0.5).symbol == "o")
        #expect(transition.sample(phase: .removal, progress: 1).symbol == ".")
    }

    @Test("Symbol frame effects use supplied time and a static motion fallback")
    func symbolFrameEffect() {
        let frames = SymbolFrames(["a", "b", "c"], fallback: "x")
        let start = TimeInstant(nanoseconds: 100)

        #expect(frames.frame(at: TimeInstant(nanoseconds: 120), startingAt: start, interval: .nanoseconds(10)) == "c")
        #expect(
            frames.frame(
                at: TimeInstant(nanoseconds: 120),
                startingAt: start,
                interval: .nanoseconds(10),
                motion: MotionEnvironmentValues(reduceMotion: true)
            ) == "x"
        )
    }

    @Test("Reduced motion keeps symbol frames static")
    func reducedSymbolFrames() {
        let transition = AnyTransition.symbolFrames(SymbolFrames(["a", "b"], fallback: "x"))
        let reduced = transition.reducedForMotion()

        #expect(reduced.sample(phase: .insertion, progress: 1).symbol == "x")
    }
}
