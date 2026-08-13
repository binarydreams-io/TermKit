//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Table+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension _TableCore {
  // MARK: - Column Width Calculation

  func calculateColumnWidths(availableWidth: Int, spacing: Int) -> [Int] {
    guard !columns.isEmpty else { return [] }

    let totalSpacing = spacing * (columns.count - 1)
    let indicatorWidth = 2
    let contentWidth = max(0, availableWidth - totalSpacing - indicatorWidth)

    var widths = [Int](repeating: 0, count: columns.count)
    var usedWidth = 0
    var flexibleIndices: [Int] = []

    for (index, column) in columns.enumerated() {
      switch column.width {
      case let .fixed(fixedWidth):
        widths[index] = fixedWidth
        usedWidth += fixedWidth
      case let .ratio(ratio):
        let ratioWidth = Int(Double(contentWidth) * ratio)
        widths[index] = ratioWidth
        usedWidth += ratioWidth
      case .flexible:
        flexibleIndices.append(index)
      }
    }

    if !flexibleIndices.isEmpty {
      let remainingWidth = max(0, contentWidth - usedWidth)
      let perColumn = remainingWidth / flexibleIndices.count
      let remainder = remainingWidth % flexibleIndices.count

      for (offset, index) in flexibleIndices.enumerated() {
        widths[index] = perColumn + (offset < remainder ? 1 : 0)
      }
    }

    return widths.map { max(1, $0) }
  }

  // MARK: - Header Rendering

  func renderHeader(columnWidths: [Int], palette: any Palette) -> String {
    let spacing = String(repeating: " ", count: columnSpacing)

    let cells = zip(columns, columnWidths).map { column, width -> String in
      let aligned = alignText(column.title, width: width, alignment: column.alignment)
      return ANSIRenderer.colorize(aligned, foreground: palette.foregroundSecondary, bold: true)
    }

    return "  " + cells.joined(separator: spacing)
  }

  // MARK: - Row Rendering

  func renderRow(
    item: Value,
    columnWidths: [Int],
    isFocused: Bool,
    isSelected: Bool,
    rowWidth: Int,
    context: RenderContext,
    palette: any Palette
  ) -> String {
    let spacing = String(repeating: " ", count: columnSpacing)
    let visualState = rowVisualState(
      isFocused: isFocused,
      isSelected: isSelected,
      context: context,
      palette: palette
    )

    let styledIndicator = ANSIRenderer.colorize(
      visualState.indicator,
      foreground: visualState.indicatorColor
    )

    // Build cells using environment foreground color
    let foregroundColor = context.environment.foregroundStyle ?? palette.foreground
    let cells = zip(columns, columnWidths).map { column, width -> String in
      let value = column.value(for: item)
      let aligned = alignText(value, width: width, alignment: column.alignment)
      return ANSIRenderer.colorize(aligned, foreground: foregroundColor)
    }

    let content = styledIndicator + " " + cells.joined(separator: spacing)

    if let bgColor = visualState.backgroundColor {
      let visibleLength = content.strippedLength
      let padding = max(0, rowWidth - visibleLength)
      let paddedContent = content + String(repeating: " ", count: padding)
      return paddedContent.withPersistentBackground(bgColor)
    } else {
      return content
    }
  }

  /// Determines indicator symbol, indicator color, and background color for a table row.
  private func rowVisualState(
    isFocused: Bool,
    isSelected: Bool,
    context: RenderContext,
    palette: any Palette
  ) -> (indicator: String, indicatorColor: Color, backgroundColor: Color?) {
    if isFocused, isSelected {
      let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
      let bg = Color.lerp(dimAccent, palette.accent.opacity(ViewConstants.focusPulseMax), phase: context.environment.pulsePhase)
      return ("●", palette.accent, bg)
    } else if isFocused {
      return (" ", palette.foregroundTertiary, palette.focusBackground)
    } else if isSelected {
      return ("●", palette.accent.opacity(ViewConstants.selectionIndicator), nil)
    } else {
      return (" ", palette.foregroundTertiary, nil)
    }
  }

  // MARK: - Text Alignment

  private func alignText(_ text: String, width: Int, alignment: HorizontalAlignment) -> String {
    let visibleLength = text.strippedLength
    let padding = max(0, width - visibleLength)

    switch alignment {
    case .leading:
      return text + String(repeating: " ", count: padding)
    case .center:
      let leftPad = padding / 2
      let rightPad = padding - leftPad
      return String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
    case .trailing:
      return String(repeating: " ", count: padding) + text
    }
  }
}
