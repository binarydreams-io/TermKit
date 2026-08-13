//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore+RowRendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension _ListCore {
  // MARK: - Row Rendering

  func renderRow(
    row: SelectableListRow<SelectionValue>,
    isFocused: Bool,
    isSelected: Bool,
    rowWidth: Int,
    sectionContentIndex: Int,
    style: any ListStyle,
    context: RenderContext,
    palette: any Palette
  ) -> [String] {
    let backgroundColor = rowBackgroundColor(
      rowType: row.type,
      isFocused: isFocused,
      isSelected: isSelected,
      sectionContentIndex: sectionContentIndex,
      style: style,
      context: context,
      palette: palette
    )

    // Check for badge on the row (only for content rows, on first line only)
    let badge = row.badge
    let shouldRenderBadge = badge != nil && !badge!.isHidden && row.isSelectable

    // Render each line with padding and optional badge
    return row.buffer.lines.enumerated().map { lineIndex, line in
      if shouldRenderBadge, lineIndex == 0 {
        renderLineWithBadge(
          line: line,
          badge: badge!,
          rowWidth: rowWidth,
          backgroundColor: backgroundColor,
          palette: palette
        )
      } else {
        renderPlainLine(
          line: line,
          rowWidth: rowWidth,
          backgroundColor: backgroundColor
        )
      }
    }
  }

  /// Determines the background color for a row based on its type and visual state.
  private func rowBackgroundColor(
    rowType: ListRowType<SelectionValue>,
    isFocused: Bool,
    isSelected: Bool,
    sectionContentIndex: Int,
    style: any ListStyle,
    context: RenderContext,
    palette: any Palette
  ) -> Color? {
    switch rowType {
    case .header, .footer:
      return nil

    case .content:
      if isFocused, isSelected {
        let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
        return Color.lerp(dimAccent, palette.accent.opacity(ViewConstants.focusPulseMax), phase: context.environment.pulsePhase)
      } else if isFocused {
        return palette.focusBackground
      } else if isSelected {
        return palette.accent.opacity(ViewConstants.selectedBackground)
      } else if style.alternatingRowColors, sectionContentIndex.isMultiple(of: 2) {
        return palette.accent.opacity(ViewConstants.alternatingRowBackground)
      } else {
        return nil
      }
    }
  }

  /// Renders a line with a right-aligned badge.
  /// Layout: [1 pad][content][fill padding][badge][1 pad]
  private func renderLineWithBadge(
    line: String,
    badge: BadgeValue,
    rowWidth: Int,
    backgroundColor: Color?,
    palette: any Palette
  ) -> String {
    let lineLength = line.strippedLength
    let badgeText = badge.displayText
    let styledBadge = ANSIRenderer.colorize(badgeText, foreground: palette.foregroundTertiary)

    let badgeWidth = badgeText.count
    let usedWidth = 1 + lineLength + badgeWidth + 1
    let fillPadding = max(1, rowWidth - usedWidth)
    let paddedLine = " " + line + String(repeating: " ", count: fillPadding) + styledBadge + " "

    return paddedLine.withPersistentBackground(backgroundColor)
  }

  /// Renders a plain line without badge.
  /// Layout: [1 pad][content][right padding]
  private func renderPlainLine(
    line: String,
    rowWidth: Int,
    backgroundColor: Color?
  ) -> String {
    let lineLength = line.strippedLength
    let usedWidth = 1 + lineLength
    let rightPadding = max(1, rowWidth - usedWidth)
    let paddedLine = " " + line + String(repeating: " ", count: rightPadding)

    return paddedLine.withPersistentBackground(backgroundColor)
  }
}
