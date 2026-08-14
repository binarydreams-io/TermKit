import TermKit

struct SpectrumView: View, SemanticRenderable {
  let instant: TimeInstant
  let isActive: Bool

  var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .paint)]
  }

  func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    CellSize(width: proposal.width ?? 32, height: min(5, proposal.height ?? 5))
  }

  func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let phase = isActive ? Int(instant.nanoseconds / 80_000_000) : 0
    let bars = "▁▂▃▄▅▆▇█"
    let glyphs = Array(bars)
    for column in 0 ..< context.frameSize.width {
      let level = (column * 5 + phase * 3 + column * column) % glyphs.count
      let point = context.origin.offsetBy(dx: column, dy: 0)
      guard context.clip.contains(point), surface.bounds.contains(point) else { continue }
      let graphemeID = try resources.graphemes.intern(glyphs[level])
      let styleID = try resources.internPaintStyle(level >= 6 ? PlayerStyles.peakData : PlayerStyles.data)
      _ = try surface.write(graphemeID: graphemeID, at: point, styleID: styleID, clip: context.clip)
    }
    return SemanticNode(
      id: "player-spectrum",
      role: .progressIndicator,
      label: "Signal spectrum",
      value: isActive ? "Active" : "Paused",
      frame: CellRect(origin: context.origin, size: context.frameSize)
    )
  }
}
