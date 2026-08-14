/// Selects the clipboard action after a text-selection drag ends.
public enum TextSelectionCopyAction: Sendable, Hashable {
  /// Uses the runtime copy-on-release setting. A completed copy clears
  /// the selection.
  case automatic
  /// Keeps the selection without writing to the clipboard.
  case suppress
}

/// Configures text selection over the rendered terminal surface.
public struct TextSelectionConfiguration: Sendable, Hashable {
  /// A configuration that preserves the runtime's 2.1 mouse behavior.
  public static let disabled = TextSelectionConfiguration(isEnabled: false)

  /// A value that enables mouse-drag text selection.
  public var isEnabled: Bool
  /// A value that enables an OSC 52 clipboard write on release.
  public var copiesOnRelease: Bool
  /// The style that the runtime merges into selected cells.
  public var style: CellStyle

  /// Creates a text-selection configuration.
  public init(
    isEnabled: Bool = true,
    copiesOnRelease: Bool = true,
    style: CellStyle = CellStyle(attributes: .inverse)
  ) {
    self.isEnabled = isEnabled
    self.copiesOnRelease = copiesOnRelease
    self.style = style
  }

  /// Creates a text-selection configuration from a resolved semantic theme.
  public init(
    theme: ResolvedSemanticTheme,
    isEnabled: Bool = true,
    copiesOnRelease: Bool = true
  ) {
    self.init(
      isEnabled: isEnabled,
      copiesOnRelease: copiesOnRelease,
      style: CellStyle(
        foreground: .rgba(theme[.selectedText]),
        background: .rgba(theme[.selectedBackground])
      )
    )
  }
}

struct SurfaceTextSelection: Sendable, Hashable {
  private(set) var anchor: CellPoint?
  private(set) var head: CellPoint?
  private(set) var didDrag = false
  private(set) var isDragging = false

  var isEmpty: Bool {
    anchor == nil || head == nil
  }

  mutating func begin(at point: CellPoint, in bounds: CellRect) {
    guard let point = bounded(point, in: bounds) else {
      clear()
      return
    }
    anchor = point
    head = point
    didDrag = false
    isDragging = true
  }

  mutating func update(to point: CellPoint, in bounds: CellRect) {
    guard isDragging, let anchor, let point = bounded(point, in: bounds) else { return }
    head = point
    didDrag = didDrag || point != anchor
  }

  mutating func finish(at point: CellPoint, in bounds: CellRect) -> Bool {
    guard isDragging else { return false }
    update(to: point, in: bounds)
    isDragging = false
    // A pointer that wandered off the anchor cell and returned selects
    // nothing beyond that cell, so the release reads as a click.
    didDrag = didDrag && head != anchor
    return didDrag
  }

  mutating func clear() {
    anchor = nil
    head = nil
    didDrag = false
    isDragging = false
  }

  func text(in surface: Surface, graphemes: GraphemeInterner) -> String {
    selectedRows(in: surface).map { row in
      var text = ""
      var x = row.range.lowerBound
      while x < row.range.upperBound {
        let point = CellPoint(x: x, y: row.y)
        let cell = surface[point]
        if cell.isContinuation {
          x += 1
          continue
        }
        text += graphemes.value(for: cell.graphemeID) ?? " "
        x += max(1, Int(cell.displayWidth))
      }
      while text.last == " " {
        text.removeLast()
      }
      return text
    }.joined(separator: "\n")
  }

  func applyStyle(
    _ selectionStyle: CellStyle,
    to surface: inout Surface,
    styles: inout StyleInterner
  ) throws {
    for row in selectedRows(in: surface) {
      try surface.transformStyles(
        in: CellRect(x: row.range.lowerBound, y: row.y, width: row.range.count, height: 1),
        styles: &styles
      ) { style in
        CellStyle(
          foreground: selectionStyle.foreground ?? style.foreground,
          background: selectionStyle.background ?? style.background,
          attributes: style.attributes.union(selectionStyle.attributes)
        )
      }
    }
  }

  private func selectedRows(in surface: Surface) -> [(y: Int, range: Range<Int>)] {
    guard var start = anchor, var end = head else { return [] }
    if (end.y, end.x) < (start.y, start.x) {
      swap(&start, &end)
    }
    start = expandedLeader(for: start, in: surface)
    end = expandedEnd(for: end, in: surface)

    return (start.y ... end.y).compactMap { y in
      let lower = y == start.y ? start.x : surface.bounds.minX
      let upper = y == end.y ? end.x + 1 : surface.bounds.maxX
      guard lower < upper else { return nil }
      return (y, lower ..< upper)
    }
  }

  private func expandedLeader(for point: CellPoint, in surface: Surface) -> CellPoint {
    let cell = surface[point]
    guard cell.isContinuation, point.x > surface.bounds.minX else { return point }
    return point.offsetBy(dx: -1)
  }

  private func expandedEnd(for point: CellPoint, in surface: Surface) -> CellPoint {
    let cell = surface[point]
    if cell.isContinuation {
      return point
    }
    if cell.displayWidth == 2, point.x + 1 < surface.bounds.maxX {
      return point.offsetBy(dx: 1)
    }
    return point
  }

  private func bounded(_ point: CellPoint, in bounds: CellRect) -> CellPoint? {
    guard bounds.isEmpty == false else { return nil }
    return CellPoint(
      x: min(max(point.x, bounds.minX), bounds.maxX - 1),
      y: min(max(point.y, bounds.minY), bounds.maxY - 1)
    )
  }
}
