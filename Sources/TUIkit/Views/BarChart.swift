//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BarChart.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - BarChart

/// A horizontal bar chart, one row per item.
///
/// Each row lays out as a label, a proportional bar, and a right-aligned
/// value:
///
/// ```
/// swiftui-pro ████████████████████████ 100
/// pdf         ████████████             50
/// ```
///
/// The label column takes the width of the longest label, capped at a
/// third of the available width. The value column takes the width of the
/// widest formatted value. Whatever space remains becomes the bar. Bar
/// length is proportional to `value / maximumValue`, where `maximumValue`
/// is the largest value across all items; zero or negative values render
/// an empty bar. `BarChart` draws no axes or gridlines.
///
/// ```swift
/// BarChart(items: [
///     .init(label: "swiftui-pro", value: 100),
///     .init(label: "pdf", value: 50),
/// ])
/// ```
public struct BarChart: View {
  /// One labeled value in the chart.
  public struct Item: Equatable, Sendable {
    /// The row's label, shown left of the bar.
    public let label: String

    /// The row's value, shown right of the bar and used for the bar's
    /// proportion relative to the chart's largest value.
    public let value: Double

    /// Creates a bar chart item.
    ///
    /// - Parameters:
    ///   - label: The row's label.
    ///   - value: The row's value.
    public init(label: String, value: Double) {
      self.label = label
      self.value = value
    }
  }

  /// The rows to render, in the given order.
  private let items: [Item]

  /// Creates a bar chart for the given items.
  ///
  /// - Parameter items: The rows to render, in the given order.
  public init(items: [Item]) {
    self.items = items
  }

  public var body: some View {
    _BarChartCore(items: items)
  }
}
