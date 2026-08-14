@testable import TermKit
import Testing

struct ColorTests {
  @Test func `interpolation uses linear SRGB`() {
    let midpoint = RGBA.black.interpolated(to: .white, progress: 0.5)

    #expect(abs(midpoint.red - 0.735_356_983) < 0.000_001)
    #expect(midpoint.red == midpoint.green)
    #expect(midpoint.green == midpoint.blue)
  }

  @Test func `palette resolves reference chains`() throws {
    let palette = SemanticPalette([
      "primary": .makeSemantic("accent"),
      "accent": .rgba(RGBA(redByte: 12, greenByte: 34, blueByte: 56))
    ])

    #expect(try palette.resolve(.makeSemantic("primary")) == RGBA(redByte: 12, greenByte: 34, blueByte: 56))
  }

  @Test func `palette reports reference cycles`() {
    let palette = SemanticPalette([
      "a": .makeSemantic("b"),
      "b": .makeSemantic("a")
    ])

    #expect(throws: ColorResolutionError.cycle(["a", "b", "a"])) {
      try palette.resolve(.makeSemantic("a"))
    }
  }

  @Test func `compositing preserves alpha math`() {
    let foreground = RGBA(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)

    #expect(foreground.composited(over: .black) == RGBA(red: 0.5, green: 0.0, blue: 0.0))
  }
}
