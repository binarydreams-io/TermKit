/// A one-row chart that represents numeric values with block glyphs.
public struct Sparkline: SemanticRenderable, View, Hashable {
  /// The semantic identifier.
  public var id: SemanticID
  /// The values in chronological order.
  public var values: [Double]
  /// The chart style.
  public var style: CellStyle

  /// Creates a static sparkline.
  public nonisolated init(values: [Double], style: CellStyle = .default, id: SemanticID = "sparkline") {
    self.id = id
    self.values = values
    self.style = style
  }

  /// Returns the newest values that fit in the specified width.
  /// - Complexity: O(*n*), where *n* is the returned value count.
  public nonisolated func visibleValues(fittingWidth width: Int) -> [Double] {
    Array(values.suffix(max(0, width)))
  }

  /// Returns sparkline text for the specified width.
  /// - Complexity: O(*n*), where *n* is the value count.
  public nonisolated func text(fittingWidth width: Int) -> String {
    let visibleValues = visibleValues(fittingWidth: width)
    guard visibleValues.isEmpty == false else { return "" }
    let sanitized = values.map { $0.isFinite ? max(0, $0) : 0 }
    let maximum = sanitized.max() ?? 0
    let glyphs = Array("▁▂▃▄▅▆▇█")
    guard maximum > 0 else {
      return String(repeating: glyphs[0], count: visibleValues.count)
    }
    return String(visibleValues.map { value in
      let sanitizedValue = value.isFinite ? max(0, value) : 0
      let index = min(glyphs.count - 1, Int((sanitizedValue / maximum * 7).rounded()))
      return glyphs[index]
    })
  }

  /// The primitive node descriptor for the chart.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
  }

  /// Returns the chart size constrained by a proposal.
  /// - Complexity: O(1).
  public nonisolated func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    let width = min(values.count, proposal.width ?? values.count)
    return CellSize(width: width, height: min(1, proposal.height ?? 1))
  }

  /// Paints the chart and returns its semantic text node.
  /// - Complexity: O(*n*), where *n* is the value count.
  public nonisolated func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let visibleText = text(fittingWidth: context.frameSize.width)
    let frame = try SurfaceTextPainter.paint(
      [StyledRun(visibleText, style: style)],
      into: &surface,
      context: context,
      resources: &resources
    )
    return SemanticNode(id: id, role: .text, label: visibleText, frame: frame)
  }
}
