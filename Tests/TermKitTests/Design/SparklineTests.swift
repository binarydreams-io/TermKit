@testable import TermKit
import Testing

struct SparklineTests {
  @Test
  func `width clamp keeps newest values and preserves full-series scale`() {
    let sparkline = Sparkline(values: [0, 2, 4, 6])

    #expect(sparkline.visibleValues(fittingWidth: 2) == [4, 6])
    #expect(sparkline.text(fittingWidth: 2) == "▆█")
    #expect(sparkline.sizeThatFits(ProposedCellSize(width: 3)) == CellSize(width: 3, height: 1))
  }

  @Test
  func `constant and nonfinite values have stable glyphs`() {
    let sparkline = Sparkline(values: [5, .nan, 5])

    #expect(sparkline.text(fittingWidth: 3) == "█▁█")
    #expect(sparkline.text(fittingWidth: 0).isEmpty)
  }

  @Test
  @MainActor
  func `paint uses the clamped text and configured style`() throws {
    let style = CellStyle(attributes: .bold)
    let sparkline = Sparkline(values: [0, 1, 2, 3], style: style)
    var resources = ControlRenderResources()
    var surface = Surface(size: CellSize(width: 2, height: 1))

    let node = try sparkline.paint(
      into: &surface,
      context: PaintContext(clip: surface.bounds),
      resources: &resources
    )

    #expect(node.label == "▆█")
    #expect(resources.styles.value(for: surface[.zero].styleID) == style)
  }
}
