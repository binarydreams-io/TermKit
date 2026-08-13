//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - List Core (Internal Rendering)

/// Internal core view that handles list rendering inside a ContainerView.
struct _ListCore<SelectionValue: Hashable & Sendable, Content: View, Footer: View>: View, Renderable {
  let title: String?
  let content: Content
  let footer: Footer?
  let singleSelection: Binding<SelectionValue?>?
  let multiSelection: Binding<Set<SelectionValue>>?
  let selectionMode: SelectionMode
  let focusID: String?
  let isDisabled: Bool
  let emptyPlaceholder: String
  let showFooterSeparator: Bool

  var body: Never {
    fatalError("_ListCore renders via Renderable")
  }

  // MARK: - Row Extraction

  func extractRows(from content: Content, context: RenderContext) -> [SelectableListRow<SelectionValue>] {
    // Check for SectionRowExtractor first (Section view)
    // This must come before ChildInfoProvider because Section conforms to both
    if let section = content as? SectionRowExtractor {
      return extractSectionRows(from: section, context: context)
    }

    // Check for ListRowExtractor (ForEach)
    if let extractor = content as? ListRowExtractor {
      let rows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
      return rows.map { SelectableListRow(type: .content(id: $0.id), buffer: $0.buffer, badge: $0.badge) }
    }

    // Check for ChildInfoProvider (handles TupleView with multiple children)
    if let provider = content as? ChildInfoProvider {
      return extractFromChildren(provider: provider, context: context)
    }

    // Fallback: render as single content row
    let buffer = TUIkit.renderToBuffer(content, context: context)
    if let zeroID = 0 as? SelectionValue {
      return [SelectableListRow(type: .content(id: zeroID), buffer: buffer)]
    }

    return []
  }

  /// Extracts rows from a ChildInfoProvider, handling Sections specially.
  private func extractFromChildren(
    provider: ChildInfoProvider,
    context: RenderContext
  ) -> [SelectableListRow<SelectionValue>] {
    var result: [SelectableListRow<SelectionValue>] = []
    let infos = provider.childInfos(context: context)

    for (index, info) in infos.enumerated() {
      guard let buffer = info.buffer else { continue }

      // Try to extract original view for Section detection
      // ChildInfo only has buffer, so we check the provider type
      if let indexID = index as? SelectionValue {
        result.append(SelectableListRow(type: .content(id: indexID), buffer: buffer))
      }
    }

    return result
  }

  /// Extracts typed rows from a Section (header + content + footer).
  private func extractSectionRows(
    from section: SectionRowExtractor,
    context: RenderContext
  ) -> [SelectableListRow<SelectionValue>] {
    var rows: [SelectableListRow<SelectionValue>] = []
    let info = section.extractSectionInfo(context: context)

    // Header (non-selectable)
    if let headerBuffer = info.headerBuffer {
      rows.append(SelectableListRow(type: .header, buffer: headerBuffer))
    }

    // Content rows (selectable)
    if let extractor = section as? ListRowExtractor {
      let contentRows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
      for row in contentRows {
        rows.append(SelectableListRow(type: .content(id: row.id), buffer: row.buffer, badge: row.badge))
      }
    } else {
      // Fallback: render content as single row (if Section content is not ForEach)
      // Use the content buffer from SectionInfo
      // Note: This row is still selectable but uses index-based ID
      if !info.contentBuffer.lines.isEmpty, let indexID = 0 as? SelectionValue {
        rows.append(SelectableListRow(type: .content(id: indexID), buffer: info.contentBuffer))
      }
    }

    // Footer (non-selectable)
    if let footerBuffer = info.footerBuffer {
      rows.append(SelectableListRow(type: .footer, buffer: footerBuffer))
    }

    return rows
  }

  // MARK: - Visible Row Calculation

  func calculateVisibleRows(
    rows: [SelectableListRow<SelectionValue>],
    handler: ItemListHandler<SelectionValue>
  ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
    handler.visibleRange.map { index in
      (index, rows[index])
    }
  }
}

// MARK: - List Content View

/// Simple view that renders pre-computed lines.
struct _ListContentView: View, Renderable {
  let lines: [String]
  let regions: [InteractionRegion]

  var body: Never {
    fatalError("_ListContentView renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    FrameBuffer(lines: lines, regions: regions)
  }
}
