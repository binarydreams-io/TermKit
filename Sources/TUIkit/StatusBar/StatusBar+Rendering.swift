//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBar+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension StatusBar {
  public var body: some View {
    _StatusBarCore(
      userItems: userItems,
      systemItems: systemItems,
      style: style,
      alignment: alignment,
      highlightColor: highlightColor,
      labelColor: labelColor
    )
  }
}

// MARK: - StatusBar Core (Private Renderable)

/// Private rendering core for ``StatusBar``.
///
/// Handles all procedural ANSI rendering and buffer assembly.
/// Public ``StatusBar`` delegates to this via its `body`.
private struct _StatusBarCore: View, Renderable {
  let userItems: [any StatusBarItemProtocol]
  let systemItems: [any StatusBarItemProtocol]
  let style: StatusBarStyle
  let alignment: StatusBarAlignment
  let highlightColor: Color
  let labelColor: Color?

  var body: Never {
    fatalError("_StatusBarCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    // Get shortcuts used by user items (for deduplication)
    let userShortcuts = Set(userItems.map(\.shortcut))

    // Filter out system items that are overridden by user items
    let filteredSystemItems = systemItems.filter { !userShortcuts.contains($0.shortcut) }

    // Combine: sorted user items + filtered system items (fixed order)
    let sortedUserItems = userItems.sorted { $0.order < $1.order }
    let combinedItems = sortedUserItems + filteredSystemItems

    guard !combinedItems.isEmpty else {
      return FrameBuffer()
    }

    // Build item strings
    let itemStrings = combinedItems.map { item -> String in
      let shortcutStyled = ANSIRenderer.render(
        item.shortcut,
        with: {
          var style = TextStyle()
          style.foregroundColor = highlightColor
          style.isBold = true
          return style
        }()
      )

      let labelStyled: String = if let color = labelColor {
        ANSIRenderer.render(
          " " + item.label,
          with: {
            var style = TextStyle()
            style.foregroundColor = color
            return style
          }()
        )
      } else {
        " " + item.label
      }

      return shortcutStyled + labelStyled
    }

    switch style {
    case .compact:
      return renderCompact(itemStrings: itemStrings, width: context.availableWidth)

    case .bordered:
      return renderBordered(itemStrings: itemStrings, width: context.availableWidth, context: context)
    }
  }

  /// Aligns content within the given width based on alignment setting.
  private func alignContent(itemStrings: [String], width: Int) -> String {
    let separator = "  " // Two spaces between items for non-justified

    switch alignment {
    case .leading:
      let content = " " + itemStrings.joined(separator: separator)
      return content.padToVisibleWidth(width)

    case .trailing:
      let content = itemStrings.joined(separator: separator) + " "
      let contentWidth = content.strippedLength
      let padding = max(0, width - contentWidth)
      return String(repeating: " ", count: padding) + content

    case .center:
      let content = itemStrings.joined(separator: separator)
      let contentWidth = content.strippedLength
      let totalPadding = max(0, width - contentWidth)
      let leftPadding = totalPadding / 2
      let rightPadding = totalPadding - leftPadding
      return String(repeating: " ", count: leftPadding) + content + String(repeating: " ", count: rightPadding)

    case .justified:
      return justifyContent(itemStrings: itemStrings, width: width)
    }
  }

  /// Distributes items evenly across the width (justified alignment).
  private func justifyContent(itemStrings: [String], width: Int) -> String {
    guard !itemStrings.isEmpty else {
      return String(repeating: " ", count: width)
    }

    guard itemStrings.count > 1 else {
      // Single item: center it
      let content = itemStrings.first ?? ""
      let contentWidth = content.strippedLength
      let totalPadding = max(0, width - contentWidth)
      let leftPadding = totalPadding / 2
      let rightPadding = totalPadding - leftPadding
      return String(repeating: " ", count: leftPadding) + content + String(repeating: " ", count: rightPadding)
    }

    // Calculate total content width (without gaps)
    let totalContentWidth = itemStrings.reduce(0) { sum, item in
      sum + item.strippedLength
    }

    // For n items, we have n+1 gaps (left edge, between each item, right edge)
    let gapCount = itemStrings.count + 1
    let availableForGaps = max(0, width - totalContentWidth)
    let gapWidth = availableForGaps / gapCount
    let extraSpace = availableForGaps % gapCount

    // Build justified string with equal gaps
    var result = ""

    // Left edge gap (gets extra space if available)
    let leftGapExtra = extraSpace > 0 ? 1 : 0
    result += String(repeating: " ", count: gapWidth + leftGapExtra)

    for (index, item) in itemStrings.enumerated() {
      result += item

      if index < itemStrings.count - 1 {
        // Gap between items
        // Distribute extra space to middle gaps (after left edge took one if available)
        let gapIndex = index + 1 // 0 = left edge, 1..n-1 = between items, n = right edge
        let extra = gapIndex < extraSpace ? 1 : 0
        result += String(repeating: " ", count: gapWidth + extra)
      }
    }

    // Right edge gap
    let rightGapIndex = itemStrings.count
    let rightGapExtra = rightGapIndex < extraSpace ? 1 : 0
    result += String(repeating: " ", count: gapWidth + rightGapExtra)

    // Ensure the result fills the width exactly
    return result.padToVisibleWidth(width)
  }

  /// Renders the compact style (single line with alignment).
  private func renderCompact(itemStrings: [String], width: Int) -> FrameBuffer {
    let line = alignContent(itemStrings: itemStrings, width: width)
    return FrameBuffer(lines: [line])
  }

  /// Renders the bordered style using the current appearance's border style.
  private func renderBordered(itemStrings: [String], width: Int, context: RenderContext) -> FrameBuffer {
    let contentPadding = 2 // 1 char padding left + right
    let innerWidth = width - BorderRenderer.borderWidthOverhead
    let contentWidth = innerWidth - contentPadding
    let content = " " + alignContent(itemStrings: itemStrings, width: contentWidth) + " "

    let border = context.environment.appearance.borderStyle
    let borderColor = context.environment.palette.border

    return FrameBuffer(lines: [
      BorderRenderer.standardTopBorder(style: border, innerWidth: innerWidth, color: borderColor),
      BorderRenderer.standardContentLine(content: content, innerWidth: innerWidth, style: border, color: borderColor),
      BorderRenderer.standardBottomBorder(style: border, innerWidth: innerWidth, color: borderColor)
    ])
  }
}
