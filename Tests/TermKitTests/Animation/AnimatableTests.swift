@testable import TermKit
import Testing

private struct Percentage: Animatable {
  var animatableData: Double
}

private struct LabelModifier: AnimatableModifier {
  var animatableData: Double

  func body(content: String) -> String {
    "\(content):\(animatableData)"
  }
}

private struct StaticModifier: AnimatableModifier {
  typealias AnimatableData = EmptyAnimatableData

  func body(content: String) -> String {
    content
  }
}

@MainActor
struct AnimatableTests {
  @Test
  func `Animatable data can be interpolated and applied`() {
    var value = Percentage(animatableData: 0)

    value.animatableData = .interpolated(from: 0, to: 1, progress: 0.25)

    #expect(value.animatableData == 0.25)
  }

  @Test
  func `Animatable modifiers execute with their current data`() {
    var modifier = LabelModifier(animatableData: 0)
    modifier.animatableData = 0.5

    #expect(modifier.body(content: "loading") == "loading:0.5")
  }

  @Test
  func `Static animatable modifiers receive empty data by default`() {
    var modifier = StaticModifier()
    modifier.animatableData = .zero

    #expect(modifier.animatableData == .zero)
    #expect(modifier.body(content: "ready") == "ready")
  }
}
