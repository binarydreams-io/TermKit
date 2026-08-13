//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BarChart+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of `BarChart`.
struct _BarChartCore: View, Renderable {
  let items: [BarChart.Item]

  var body: Never {
    fatalError("_BarChartCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    guard !items.isEmpty else { return FrameBuffer(lines: []) }

    // Sanitize before any arithmetic touches these values: a NaN or
    // infinite value (e.g. from an upstream 0/0) would otherwise reach
    // `Int(Double)` in `format(value:)` or the glyph math below and trap.
    // Treating it as 0 renders the row with an empty bar and value "0"
    // instead of crashing.
    let items = items.map { item in
      BarChart.Item(label: item.label, value: item.value.isFinite ? item.value : 0)
    }

    let palette = context.environment.palette
    let availableWidth = context.availableWidth
    let formattedValues = items.map { Self.format(value: $0.value) }

    let longestLabelWidth = items.map(\.label.strippedLength).max() ?? 0
    let labelWidth = min(longestLabelWidth, max(0, availableWidth / 3))
    let valueWidth = formattedValues.map(\.strippedLength).max() ?? 0
    let barWidth = max(0, availableWidth - labelWidth - 2 - valueWidth)

    let maximumValue = items.map(\.value).max() ?? 0

    let lines = zip(items, formattedValues).map { item, formattedValue in
      renderRow(
        item: item,
        formattedValue: formattedValue,
        labelWidth: labelWidth,
        barWidth: barWidth,
        valueWidth: valueWidth,
        maximumValue: maximumValue,
        palette: palette
      )
    }

    return FrameBuffer(lines: lines)
  }

  // MARK: - Row Rendering

  /// Renders one `label bar value` row.
  ///
  /// The label is padded on its plain (uncolored) form, colorized, then
  /// truncated with `ansiAwarePrefix` — the same order `TabView` uses —
  /// so a label longer than `labelWidth` keeps its trailing ANSI reset
  /// instead of bleeding color into the bar that follows.
  private func renderRow(
    item: BarChart.Item,
    formattedValue: String,
    labelWidth: Int,
    barWidth: Int,
    valueWidth: Int,
    maximumValue: Double,
    palette: any Palette
  ) -> String {
    let paddedLabel = item.label.padToVisibleWidth(labelWidth)
    let coloredLabel = ANSIRenderer.colorize(paddedLabel, foreground: palette.foreground)
    let label = coloredLabel.ansiAwarePrefix(visibleCount: labelWidth)

    let bar = TrackRenderer.render(
      fraction: Self.fraction(value: item.value, maximumValue: maximumValue),
      width: barWidth,
      style: .block,
      filledColor: palette.accent,
      emptyColor: palette.foregroundTertiary,
      accentColor: palette.accent
    )

    let valuePadding = String(repeating: " ", count: max(0, valueWidth - formattedValue.strippedLength))
    let value = ANSIRenderer.colorize(valuePadding + formattedValue, foreground: palette.foregroundSecondary)

    return label + " " + bar + " " + value
  }

  // MARK: - Value Formatting

  /// Formats a value as a plain integer string (rounded, no thousands separators).
  ///
  /// Guards the `Int(Double)` conversion directly: `renderToBuffer` already
  /// sanitizes non-finite item values to 0 before this is called, but the
  /// guard stays here too so this conversion can never trap even if a
  /// future caller reaches it with a raw value.
  ///
  /// A finite value can still sit outside the integer range, where `Int(Double)`
  /// traps as well, and where no integer form reads as a number anyway. Such a
  /// value keeps the scientific form the `Double` prints, so the row reports its
  /// magnitude instead of crashing the frame.
  private static func format(value: Double) -> String {
    guard value.isFinite else { return "0" }
    let rounded = value.rounded()
    guard let integer = Int(exactly: rounded) else { return String(rounded) }
    return String(integer)
  }

  /// The bar's filled proportion of `value` relative to `maximumValue`.
  ///
  /// Zero or negative values, and a non-positive `maximumValue`, render an
  /// empty bar instead of dividing by zero or a negative number.
  private static func fraction(value: Double, maximumValue: Double) -> Double {
    guard maximumValue > 0, value > 0 else { return 0 }
    return min(1.0, value / maximumValue)
  }
}
