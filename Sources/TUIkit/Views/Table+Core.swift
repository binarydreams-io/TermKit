//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Table+Core.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Table Core (Internal Rendering)

/// Internal core view that handles table rendering inside a ContainerView.
struct _TableCore<Value: Identifiable & Sendable>: View, Renderable where Value.ID: Hashable {
  let data: [Value]
  let columns: [TableColumn<Value>]
  let singleSelection: Binding<Value.ID?>?
  let multiSelection: Binding<Set<Value.ID>>?
  let selectionMode: SelectionMode
  let focusID: String?
  let isDisabled: Bool
  let emptyPlaceholder: String
  let columnSpacing: Int

  var body: Never {
    fatalError("_TableCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let palette = context.environment.palette
    let stateStorage = context.environment.stateStorage!

    // Calculate available width inside container (subtract border + padding)
    let innerWidth = max(0, context.availableWidth - 4)

    // Calculate column widths
    let columnWidths = calculateColumnWidths(
      availableWidth: innerWidth,
      spacing: columnSpacing
    )

    // Build header line from column titles
    let headerLine = renderHeader(columnWidths: columnWidths, palette: palette)

    // Handle empty state
    let contentLines: [String]

    if data.isEmpty {
      contentLines = [emptyPlaceholder]
    } else {
      // Calculate viewport height
      let availableHeight = context.availableHeight
      let viewportHeight = max(1, availableHeight - 6) // Reserve for border + header + indicators

      // Focus registration via shared helper
      let persistedFocusID = FocusRegistration.persistFocusID(
        context: context,
        explicitFocusID: focusID,
        defaultPrefix: "table",
        propertyIndex: 1 // focusID
      )

      // Get or create persistent handler
      let handlerKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0) // handler
      let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
        for: handlerKey,
        default: ItemListHandler(
          focusID: persistedFocusID,
          itemCount: data.count,
          viewportHeight: viewportHeight,
          selectionMode: selectionMode,
          canBeFocused: !isDisabled
        )
      )
      let handler = handlerBox.value

      // Update handler with current values
      handler.itemCount = data.count
      handler.viewportHeight = viewportHeight
      handler.canBeFocused = !isDisabled
      handler.itemIDs = data.map(\.id)
      if !context.isMeasuring {
        let invalidationSink = context.environment.renderInvalidationSink
        let identity = context.identity
        handler.onVisualStateChange = {
          invalidationSink?.invalidate(.subtree(identity))
        }
      }

      // Assign selection bindings directly (type-safe, no AnyHashable conversion)
      handler.singleSelection = singleSelection
      handler.multiSelection = multiSelection

      // Ensure focused item is visible
      handler.ensureFocusedItemVisible()

      FocusRegistration.register(context: context, handler: handler)
      let tableHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

      // Build content lines
      var lines: [String] = []

      // Top scroll indicator
      if handler.hasContentAbove {
        lines.append(renderScrollIndicator(direction: .up, width: innerWidth, palette: palette))
      }

      // Data rows
      let visibleRange = handler.visibleRange
      for rowIndex in visibleRange {
        let item = data[rowIndex]
        let isFocused = handler.isFocused(at: rowIndex) && tableHasFocus
        let isSelected = handler.isSelected(at: rowIndex)

        lines.append(
          renderRow(
            item: item,
            columnWidths: columnWidths,
            isFocused: isFocused,
            isSelected: isSelected,
            rowWidth: innerWidth,
            context: context,
            palette: palette
          )
        )
      }

      // Bottom scroll indicator
      if handler.hasContentBelow {
        lines.append(renderScrollIndicator(direction: .down, width: innerWidth, palette: palette))
      }

      contentLines = lines
    }

    // Create the table content as a simple view
    let tableContent = _TableContentView(lines: contentLines)

    // Create header view
    let headerView = _TableHeaderView(line: headerLine)

    // Wrap in ContainerView with header separator (column titles are in header)
    let container = ContainerView(
      title: nil,
      style: ContainerStyle(showHeaderSeparator: true, showFooterSeparator: false),
      padding: EdgeInsets(horizontal: 1, vertical: 0)
    ) {
      VStack(spacing: 0) {
        headerView
        tableContent
      }
    }

    return TUIkit.renderToBuffer(container, context: context)
  }
}

// MARK: - Table Content View

/// Simple view that renders pre-computed lines.
private struct _TableContentView: View, Renderable {
  let lines: [String]

  var body: Never {
    fatalError("_TableContentView renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    FrameBuffer(lines: lines)
  }
}

// MARK: - Table Header View

/// Simple view that renders the header line.
private struct _TableHeaderView: View, Renderable {
  let line: String

  var body: Never {
    fatalError("_TableHeaderView renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    FrameBuffer(lines: [line])
  }
}
