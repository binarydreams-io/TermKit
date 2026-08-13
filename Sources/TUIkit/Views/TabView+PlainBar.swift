//  TUIKit - Terminal UI Kit for Swift
//  TabView+PlainBar.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Plain Bar

extension _TabBarCore {
  /// The mark of the selected tab: `▎`, one quarter block.
  ///
  /// The mark is thin on purpose. A heavy bar reads as the edge of a frame, and
  /// the plain style draws no frames.
  static var plainSelectionMark: String {
    "\u{258E}"
  }

  /// The columns between two plain cells.
  ///
  /// Four columns separate two labels without a divider glyph, and they keep two
  /// one-word labels from reading as one.
  static var plainCellGap: Int {
    4
  }

  /// The cells of the plain bar.
  ///
  /// Each cell spends its natural width, because the style paints no fill: an
  /// equal share of the offered width would scatter three labels across the
  /// terminal instead of grouping them into a bar.
  ///
  /// - Parameters:
  ///   - availableWidth: The columns the bar may spend.
  ///   - palette: The palette the bar reads its tones from.
  /// - Returns: The cells to render, in display order.
  func plainCells(availableWidth: Int, palette: any Palette) -> [_TabBarCell] {
    let widths = tabs.map { plainText(of: $0).strippedLength }
    let window = plainWindow(widths: widths, availableWidth: availableWidth)
    var cells: [_TabBarCell] = []
    var spent = 0

    for index in window {
      let budget = availableWidth - spent
      guard budget > 0 else { break }
      let visibleWidth = widths[index]
      let gap = index == window.upperBound - 1 ? 0 : Self.plainCellGap
      let colored = plainColoredText(of: tabs[index], palette: palette)
      let text = visibleWidth >= budget
        ? colored.ansiAwarePrefix(visibleCount: budget)
        : colored + String(repeating: " ", count: min(gap, budget - visibleWidth))
      let width = min(visibleWidth + gap, budget)
      cells.append(_TabBarCell(index: index, text: text, width: width))
      spent += width
    }

    return cells
  }

  /// The tabs the plain bar shows, as indices into ``tabs``.
  ///
  /// The window always holds the selected tab. It grows from the left while the
  /// cells and their gaps fit the offered width, and it starts one tab further
  /// right for every window that would leave the open tab out. A bar too narrow
  /// for the selected tab alone shows that tab truncated, never another one.
  ///
  /// - Parameters:
  ///   - widths: The visible width of every tab's cell, in display order.
  ///   - availableWidth: The columns the bar may spend.
  /// - Returns: The indices of the tabs to render, in display order.
  private func plainWindow(widths: [Int], availableWidth: Int) -> Range<Int> {
    let selected = selectedIndex

    for start in 0 ... selected {
      var end = start
      var spent = 0
      while end < tabs.count {
        let gap = end == start ? 0 : Self.plainCellGap
        guard spent + gap + widths[end] <= availableWidth else { break }
        spent += gap + widths[end]
        end += 1
      }
      if selected < end {
        return start ..< end
      }
    }

    return selected ..< selected + 1
  }

  /// One plain cell's text without its colors: the lead, one space, and the
  /// label. A tab with no lead prints its label alone.
  ///
  /// - Parameter tab: The tab the cell shows.
  /// - Returns: The cell's visible characters.
  private func plainText(of tab: TabItem<Value>) -> String {
    let lead = plainLead(of: tab)
    return lead.isEmpty ? label(of: tab) : "\(lead) \(label(of: tab))"
  }

  /// The cell's leading column: the mark for the selected tab, the key hint for
  /// an unselected one, and nothing for a tab that carries no hint.
  private func plainLead(of tab: TabItem<Value>) -> String {
    isSelected(tab) ? Self.plainSelectionMark : (tab.hint ?? "")
  }

  /// One plain cell's colored text.
  ///
  /// The selected cell carries the accent, bold, across its mark and its label.
  /// An unselected cell splits its tones: the hint takes the dimmest
  /// foreground, and the label takes the tertiary one.
  ///
  /// - Parameters:
  ///   - tab: The tab the cell shows.
  ///   - palette: The palette the cell reads its tones from.
  /// - Returns: The cell's text with its ANSI codes.
  private func plainColoredText(of tab: TabItem<Value>, palette: any Palette) -> String {
    if isSelected(tab) {
      return ANSIRenderer.colorize(plainText(of: tab), foreground: palette.accent, bold: true)
    }

    let coloredLabel = ANSIRenderer.colorize(label(of: tab), foreground: palette.foregroundTertiary)
    let lead = plainLead(of: tab)
    guard !lead.isEmpty else { return coloredLabel }
    let coloredLead = ANSIRenderer.colorize(lead, foreground: palette.foregroundQuaternary)
    return "\(coloredLead) \(coloredLabel)"
  }
}
