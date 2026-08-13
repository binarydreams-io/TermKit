//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Section+Extraction.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Section Row Extractor

/// Protocol for views that can provide section information for List rendering.
///
/// When a `List` contains `Section` views, it uses this protocol to extract
/// section structure for proper rendering with headers, footers, and grouping.
@MainActor
protocol SectionRowExtractor {
  /// Extracts section information for list rendering.
  ///
  /// - Parameter context: The rendering context.
  /// - Returns: Section metadata including header, content rows, and footer.
  func extractSectionInfo(context: RenderContext) -> SectionInfo
}

/// Metadata about a section for List rendering.
struct SectionInfo {
  /// The rendered header buffer (nil if no header).
  let headerBuffer: FrameBuffer?

  /// The rendered footer buffer (nil if no footer).
  let footerBuffer: FrameBuffer?

  /// The content rows within this section.
  let contentBuffer: FrameBuffer
}

extension Section: SectionRowExtractor {
  func extractSectionInfo(context: RenderContext) -> SectionInfo {
    // Render header with styling
    let headerBuffer: FrameBuffer?
    if !(header is EmptyView) {
      let raw = TUIkit.renderToBuffer(header, context: context)
      let styledLines = raw.lines.map { line in
        applyHeaderFooterStyle(line, bold: true)
      }
      headerBuffer = FrameBuffer(lines: styledLines)
    } else {
      headerBuffer = nil
    }

    // Render footer with styling
    let footerBuffer: FrameBuffer?
    if !(footer is EmptyView) {
      let raw = TUIkit.renderToBuffer(footer, context: context)
      let styledLines = raw.lines.map { line in
        applyHeaderFooterStyle(line, bold: false)
      }
      footerBuffer = FrameBuffer(lines: styledLines)
    } else {
      footerBuffer = nil
    }

    // Render content
    let contentBuffer = TUIkit.renderToBuffer(content, context: context)

    return SectionInfo(
      headerBuffer: headerBuffer,
      footerBuffer: footerBuffer,
      contentBuffer: contentBuffer
    )
  }

  /// Applies dim styling (and optionally bold) to a line.
  private func applyHeaderFooterStyle(_ line: String, bold: Bool) -> String {
    var style = TextStyle()
    style.isDim = true
    style.isBold = bold
    return ANSIRenderer.render(line, with: style)
  }
}

// MARK: - Section as ChildInfoProvider

extension Section: ChildInfoProvider {
  public func childInfos(context: RenderContext) -> [ChildInfo] {
    // For stack layouts, render Section as a single unit
    let buffer = TUIkit.renderToBuffer(self, context: context)
    return [ChildInfo(buffer: buffer, isSpacer: false, spacerMinLength: nil, size: nil)]
  }
}

// MARK: - Section as ListRowExtractor

extension Section: ListRowExtractor {
  /// Extracts list rows from the section's content.
  ///
  /// Delegates to the content's `ListRowExtractor` implementation if available
  /// (e.g., `ForEach`). This allows List to extract individual content rows
  /// while separately handling section headers and footers.
  ///
  /// - Parameter context: The rendering context.
  /// - Returns: Array of list rows from the section's content.
  func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
    // Delegate to content if it's a ListRowExtractor (e.g., ForEach)
    if let extractor = content as? ListRowExtractor {
      return extractor.extractListRows(context: context)
    }

    // Fallback: render content as a single row (rare case)
    let buffer = TUIkit.renderToBuffer(content, context: context)
    if let indexID = 0 as? RowID {
      return [ListRow(id: indexID, buffer: buffer, badge: nil)]
    }
    return []
  }
}
