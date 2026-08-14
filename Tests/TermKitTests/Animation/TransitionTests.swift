@testable import TermKit
import Testing

struct TransitionTests {
  @Test
  func `Combined transition samples all effects`() {
    let transition = AnyTransition.opacity.combined(with: .move(edge: .leading, distance: 4))
    let sample = transition.sample(phase: .insertion, progress: 0.25)

    #expect(sample.opacity == 0.25)
    #expect(sample.offset.first == -3)
    #expect(sample.offset.second == 0)
  }

  @Test
  func `Asymmetric transition uses separate phase effects`() {
    let transition = AnyTransition.asymmetric(
      insertion: .reveal(edge: .top),
      removal: .wipe(edge: .trailing)
    )

    #expect(transition.insertionEffects == [.reveal(edge: .top)])
    #expect(transition.removalEffects == [.wipe(edge: .trailing)])
    #expect(transition.sample(phase: .insertion, progress: 0.5).revealFraction == 0.5)
    #expect(transition.sample(phase: .removal, progress: 0.5).wipeFraction == 0.5)
  }

  @Test
  func `Reduced motion replaces spatial transitions with opacity`() {
    let transition = AnyTransition.move(edge: .bottom).combined(with: .reveal(edge: .top))
    let transaction = Transaction(
      animation: .linear(duration: .milliseconds(200)),
      reduceMotion: true
    )
    let reduced = transition.resolved(for: transaction)

    #expect(reduced.insertionEffects == [.opacity])
    #expect(reduced.removalEffects == [.opacity])
  }

  @Test
  func `Reduced motion preserves identity on an asymmetric phase`() {
    let transition = AnyTransition.asymmetric(
      insertion: .move(edge: .leading),
      removal: .identity
    )

    let reduced = transition.reducedForMotion()

    #expect(reduced.insertionEffects == [.opacity])
    #expect(reduced.removalEffects.isEmpty)
  }

  @Test
  func `Disabled animations resolve transitions to identity`() {
    let transaction = Transaction(
      animation: .linear(duration: .milliseconds(200)),
      animationsEnabled: false
    )

    #expect(AnyTransition.opacity.resolved(for: transaction) == .identity)
  }

  @Test
  func `Symbol frame transitions sample insertion and removal progress`() {
    let transition = AnyTransition.symbolFrames(SymbolFrames([".", "o", "O"], fallback: "-"))

    #expect(transition.sample(phase: .insertion, progress: 0).symbol == ".")
    #expect(transition.sample(phase: .insertion, progress: 0.5).symbol == "o")
    #expect(transition.sample(phase: .removal, progress: 1).symbol == ".")
  }

  @Test
  func `Symbol frame effects use supplied time and a static motion fallback`() {
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

  @Test
  func `Reduced motion keeps symbol frames static`() {
    let transition = AnyTransition.symbolFrames(SymbolFrames(["a", "b"], fallback: "x"))
    let reduced = transition.reducedForMotion()

    #expect(reduced.sample(phase: .insertion, progress: 1).symbol == "x")
  }
}
