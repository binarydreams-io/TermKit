//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore+BorderlessRendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension _ListCore {
  /// Wraps the rendered row content in the list's bordered container, or
  /// renders it borderless when the active style declares no border.
  ///
  /// - Parameters:
  ///   - contentLines: The rendered content lines (rows and scroll indicators).
  ///   - contentRegions: Interaction regions for rows and scrolling.
  ///   - context: The render context.
  ///   - palette: The active palette.
  ///   - style: The active list style.
  /// - Returns: The finished frame buffer.
  func assembleContainer(
    contentLines: [String],
    contentRegions: [InteractionRegion],
    context: RenderContext,
    palette: any Palette,
    style: any ListStyle
  ) -> FrameBuffer {
    // Pad content to fill available height (SwiftUI behavior: List is greedy)
    // Reserve space for: title line (1) + top border (1) + bottom border (1) + footer if present
    let footerHeight = footer != nil ? 2 : 0 // footer line + separator
    let borderOverhead = style.showsBorder ? 2 : 0 // top + bottom border
    let titleOverhead = title != nil ? 1 : 0
    let targetContentHeight = max(1, context.availableHeight - borderOverhead - titleOverhead - footerHeight)

    var paddedContentLines = contentLines
    if paddedContentLines.count < targetContentHeight {
      let emptyLinesToAdd = targetContentHeight - paddedContentLines.count
      paddedContentLines.append(contentsOf: Array(repeating: "", count: emptyLinesToAdd))
    }

    // Create the list content as a simple view
    let listContent = _ListContentView(lines: paddedContentLines, regions: contentRegions)

    // A style that declares no border must not get one. `renderContainer`
    // reads a nil border style as "use the appearance default", which is
    // right for Panel and Card — they ask for the default that way — but it
    // would frame a plain list and push every row one column off the column
    // header above it.
    guard style.showsBorder else {
      return renderBorderless(content: listContent, palette: palette, context: context)
    }

    // Render using the shared container helper with footer support
    // Apply list style: border from showsBorder, padding from style
    let config = ContainerConfig(
      borderStyle: style.showsBorder ? context.environment.appearance.borderStyle : nil,
      borderColor: style.showsBorder ? palette.border : nil,
      titleColor: nil,
      padding: style.rowPadding,
      showFooterSeparator: showFooterSeparator
    )

    return renderContainer(
      title: title,
      config: config,
      content: listContent,
      footer: footer,
      context: context
    )
  }

  /// Renders a list whose style declares no border.
  ///
  /// The rows keep the full width, and the optional title and footer stack
  /// above and below them as plain rows.
  ///
  /// - Parameters:
  ///   - content: The rendered rows.
  ///   - palette: The active palette, for the title colour.
  ///   - context: The render context.
  /// - Returns: The stacked buffer.
  private func renderBorderless(
    content: _ListContentView,
    palette: any Palette,
    context: RenderContext
  ) -> FrameBuffer {
    var buffer = FrameBuffer()
    if let title {
      buffer.appendVertically(
        TUIkit.renderToBuffer(
          Text(title).bold().foregroundStyle(.palette.foreground),
          context: context
        )
      )
    }
    buffer.appendVertically(TUIkit.renderToBuffer(content, context: context))
    if let footer {
      buffer.appendVertically(TUIkit.renderToBuffer(footer, context: context))
    }
    return buffer
  }
}
