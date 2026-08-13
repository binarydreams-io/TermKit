//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitView+Layout.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Layout Helpers

extension _NavigationSplitViewCore {
  /// Resolves the effective visibility from the binding or defaults to `.all`.
  func resolveVisibility() -> NavigationSplitViewVisibility {
    if let binding = columnVisibility {
      let value = binding.wrappedValue
      // Resolve .automatic to .all
      if value == .automatic {
        return .all
      }
      return value
    }
    return .all
  }

  /// Calculates which columns should be visible based on visibility setting.
  func calculateVisibleColumns(visibility: NavigationSplitViewVisibility) -> [NavigationSplitViewColumn] {
    if isThreeColumn {
      switch visibility {
      case .all, .automatic:
        [.sidebar, .content, .detail]
      case .doubleColumn:
        [.content, .detail]
      case .detailOnly:
        [.detail]
      default:
        [.sidebar, .content, .detail]
      }
    } else {
      // Two-column layout
      switch visibility {
      case .all, .automatic, .doubleColumn:
        [.sidebar, .detail]
      case .detailOnly:
        [.detail]
      default:
        [.sidebar, .detail]
      }
    }
  }

  /// Fixed column widths for sidebar and content (TUI-specific).
  /// Only the rightmost column adapts to terminal width changes.
  private var fixedSidebarWidth: Int {
    25
  }

  private var fixedContentWidth: Int {
    30
  }

  /// Calculates the width for each visible column.
  /// TUI-specific: Left columns have fixed widths, only the rightmost column is flexible.
  func calculateColumnWidths(
    visibleColumns: [NavigationSplitViewColumn],
    style: any NavigationSplitViewStyle,
    availableWidth: Int
  ) -> [Int] {
    let separatorCount = max(0, visibleColumns.count - 1)
    let usableWidth = availableWidth - separatorCount

    guard usableWidth > 0 else {
      return Array(repeating: 0, count: visibleColumns.count)
    }

    // TUI-specific: Fixed widths for left columns, flexible rightmost column
    var widths: [Int] = []
    var remainingWidth = usableWidth

    for (index, column) in visibleColumns.enumerated() {
      let isLastColumn = index == visibleColumns.count - 1

      if isLastColumn {
        // Last column gets all remaining width
        widths.append(max(minimumColumnWidth, remainingWidth))
      } else {
        // Fixed width for left columns
        let fixedWidth: Int = switch column {
        case .sidebar:
          fixedSidebarWidth
        case .content:
          fixedContentWidth
        default:
          minimumColumnWidth
        }
        let width = min(fixedWidth, remainingWidth - minimumColumnWidth)
        widths.append(max(minimumColumnWidth, width))
        remainingWidth -= width
      }
    }

    return widths
  }

  /// Returns the focus section ID for a column.
  func focusSectionID(for column: NavigationSplitViewColumn) -> String {
    switch column {
    case .sidebar:
      "nav-split-sidebar"
    case .content:
      "nav-split-content"
    case .detail:
      "nav-split-detail"
    default:
      "nav-split-unknown"
    }
  }

  /// Renders a single column.
  func renderColumn(_ column: NavigationSplitViewColumn, context: RenderContext) -> FrameBuffer {
    switch column {
    case .sidebar:
      TUIkit.renderToBuffer(sidebar, context: context.withChildIdentity(type: type(of: sidebar)))
    case .content:
      TUIkit.renderToBuffer(content, context: context.withChildIdentity(type: type(of: content)))
    case .detail:
      TUIkit.renderToBuffer(detail, context: context.withChildIdentity(type: type(of: detail)))
    default:
      FrameBuffer()
    }
  }

  /// Combines column buffers horizontally with separators.
  func combineColumns(
    buffers: [FrameBuffer],
    columnWidths: [Int],
    separator: String,
    availableHeight: Int
  ) -> FrameBuffer {
    guard !buffers.isEmpty else { return FrameBuffer() }

    // Normalize all buffers to the same height
    let maxHeight = max(availableHeight, buffers.map(\.height).max() ?? 1)

    var result = FrameBuffer()

    for (index, buffer) in buffers.enumerated() {
      // Pad buffer to full height and width
      let targetWidth = index < columnWidths.count ? columnWidths[index] : buffer.width
      let paddedBuffer = padToSize(buffer, width: targetWidth, height: maxHeight)

      if index == 0 {
        result = paddedBuffer
      } else {
        // Add separator column (just a space, no styling needed)
        let separatorBuffer = FrameBuffer(
          lines: Array(repeating: separator, count: maxHeight)
        )
        result.appendHorizontally(separatorBuffer, spacing: 0)
        result.appendHorizontally(paddedBuffer, spacing: 0)
      }
    }

    return result
  }

  /// Pads a buffer to the specified width and height.
  private func padToSize(_ buffer: FrameBuffer, width: Int, height: Int) -> FrameBuffer {
    var lines = buffer.lines

    // Pad each line to the target width
    let paddedLines = lines.map { line -> String in
      let lineWidth = line.strippedLength
      if lineWidth < width {
        return line + String(repeating: " ", count: width - lineWidth)
      }
      return line
    }
    lines = paddedLines

    // Pad to target height
    let emptyLine = String(repeating: " ", count: width)
    while lines.count < height {
      lines.append(emptyLine)
    }

    return FrameBuffer(lines: lines, width: width, regions: buffer.regions)
  }
}
