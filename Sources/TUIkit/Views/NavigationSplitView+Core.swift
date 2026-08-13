//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitView+Core.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal Core

/// Internal view that handles the actual rendering of NavigationSplitView.
struct _NavigationSplitViewCore<Sidebar: View, Content: View, Detail: View>: View, Renderable, Layoutable {
  let sidebar: Sidebar
  let content: Content
  let detail: Detail
  let isThreeColumn: Bool
  let columnVisibility: Binding<NavigationSplitViewVisibility>?

  /// The minimum width for any column in characters.
  let minimumColumnWidth = 10

  /// The separator between columns (single space for TUI).
  /// TUI-specific: We use a space instead of a line to avoid double borders
  /// when columns contain bordered components like List.
  private let separator = " "

  var body: Never {
    fatalError("_NavigationSplitViewCore renders via Renderable")
  }

  func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
    let minWidth = minimumColumnWidth * (isThreeColumn ? 3 : 2)
    return ViewSize(width: minWidth, height: 1, isWidthFlexible: true, isHeightFlexible: true)
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let style = context.environment.navigationSplitViewStyle
    let visibility = resolveVisibility()

    // Calculate visible columns based on visibility
    let visibleColumns = calculateVisibleColumns(visibility: visibility)
    guard !visibleColumns.isEmpty else {
      return FrameBuffer()
    }

    // Calculate column widths
    let columnWidths = calculateColumnWidths(
      visibleColumns: visibleColumns,
      style: style,
      availableWidth: context.availableWidth
    )

    // Render each visible column
    var buffers: [FrameBuffer] = []
    let focusManager = context.environment.focusManager

    for (index, column) in visibleColumns.enumerated() {
      let columnWidth = columnWidths[index]
      let columnContext = context.withAvailableSize(width: columnWidth, height: context.availableHeight)

      // Register focus section for this column (skip during measurement)
      let sectionID = focusSectionID(for: column)
      if !columnContext.isMeasuring {
        focusManager.registerSection(id: sectionID)
      }

      // Create a context with the active focus section
      var sectionContext = columnContext
      sectionContext.environment.activeFocusSectionID = sectionID

      // If this section is active, set the focus indicator color for borders (never active during measurement)
      if !columnContext.isMeasuring, focusManager.isActiveSection(sectionID) {
        let accentColor = context.environment.palette.accent
        let dimColor = accentColor.opacity(ViewConstants.focusBorderDim)
        sectionContext.environment.focusIndicatorColor = Color.lerp(dimColor, accentColor, phase: context.environment.pulsePhase)
      } else {
        sectionContext.environment.focusIndicatorColor = nil
      }

      let buffer = renderColumn(column, context: sectionContext)
      buffers.append(buffer)
    }

    // Combine buffers horizontally with separators
    return combineColumns(
      buffers: buffers,
      columnWidths: columnWidths,
      separator: separator,
      availableHeight: context.availableHeight
    )
  }
}
