//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Sparkline.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Sparkline

/// A single-line trend indicator drawn from block glyphs.
///
/// `Sparkline` maps each value to one of eight block glyphs (`▁▂▃▄▅▆▇█`),
/// normalized against the largest value in the series. It is a pure
/// composition over `Text` — it holds no layout state and renders through
/// `Text`'s own `Renderable` conformance.
///
/// ```swift
/// Sparkline(values: [12, 40, 8, 55, 30])
/// ```
///
/// > Important: `Sparkline` does not clip its glyph string to
/// > `availableWidth`. A series with more values than the caller's width
/// > will overflow; slice `values` before constructing the view if the
/// > series can exceed the display width.
public struct Sparkline: View {
  /// The block glyphs, from lowest to highest magnitude.
  private static let glyphs: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

  /// The series to plot, oldest first.
  private let values: [Double]

  /// Creates a sparkline for the given series.
  ///
  /// - Parameter values: The series to plot, oldest first.
  public init(values: [Double]) {
    self.values = values
  }

  public var body: some View {
    Text(Self.glyphString(for: values))
  }

  /// Maps every value to a glyph, normalized against the series maximum.
  ///
  /// A non-positive maximum (all values zero, negative, or the series is
  /// otherwise flat) renders every glyph as the lowest bar `▁` rather than
  /// dividing by zero. A non-finite value (`.nan`, `.infinity`, e.g. from
  /// an upstream 0/0) is sanitized to 0 before it reaches the maximum or
  /// the glyph index math — `Int(Double)` traps on non-finite input, and
  /// this is the one point that conversion happens.
  private static func glyphString(for values: [Double]) -> String {
    guard !values.isEmpty else { return "" }

    let sanitized = values.map { $0.isFinite ? $0 : 0 }
    let maximum = sanitized.max() ?? 0
    guard maximum > 0 else {
      return String(repeating: glyphs[0], count: sanitized.count)
    }

    return String(sanitized.map { value in
      let index = min(7, Int(value / maximum * 7 + 0.5))
      return glyphs[max(0, index)]
    })
  }
}
