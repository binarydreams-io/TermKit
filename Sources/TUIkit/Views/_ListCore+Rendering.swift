//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension _ListCore {
  // swiftlint:disable:next function_body_length
  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let palette = context.environment.palette
    let style = context.environment.listStyle
    let stateStorage = context.environment.stateStorage!

    // Extract rows from content
    let rows = extractRows(from: content, context: context)

    // Handle empty state
    let contentLines: [String]
    let contentRegions: [InteractionRegion]
    let listHasFocus: Bool

    if rows.isEmpty {
      contentLines = [emptyPlaceholder]
      contentRegions = []
      listHasFocus = false
    } else {
      // Calculate viewport height (reserve space for scroll indicators if needed)
      let availableHeight = context.availableHeight
      let viewportHeight = max(1, availableHeight - 4) // Reserve for border + indicators

      let persistedFocusID = FocusRegistration.persistFocusID(
        context: context,
        explicitFocusID: focusID,
        defaultPrefix: "list",
        propertyIndex: 1 // focusID
      )

      // Get or create persistent handler
      let handlerKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0) // handler
      let handlerBox: StateBox<ItemListHandler<SelectionValue>> = stateStorage.storage(
        for: handlerKey,
        default: ItemListHandler(
          focusID: persistedFocusID,
          itemCount: rows.count,
          viewportHeight: viewportHeight,
          selectionMode: selectionMode,
          canBeFocused: !isDisabled
        )
      )
      let handler = handlerBox.value

      // Update handler with current values
      handler.itemCount = rows.count
      handler.viewportHeight = viewportHeight
      handler.canBeFocused = !isDisabled
      if !context.isMeasuring {
        let invalidationSink = context.environment.renderInvalidationSink
        let identity = context.identity
        handler.onVisualStateChange = {
          invalidationSink?.invalidate(.subtree(identity))
        }
      }

      // Build selectableIndices set and itemIDs from typed rows
      var selectableIndices = Set<Int>()
      var itemIDs: [SelectionValue?] = []
      var rowHeights: [Int]?
      for (index, row) in rows.enumerated() {
        let rowHeight = max(1, row.buffer.height)
        if rowHeights == nil, rowHeight != 1 {
          rowHeights = Array(repeating: 1, count: index)
        }
        rowHeights?.append(rowHeight)

        if let id = row.id {
          // Content row: use actual ID
          itemIDs.append(id)
          selectableIndices.insert(index)
        } else {
          // Header/footer: nil (non-selectable)
          itemIDs.append(nil)
        }
      }
      handler.itemIDs = itemIDs
      handler.selectableIndices = selectableIndices
      handler.rowHeights = rowHeights ?? []

      // Assign selection bindings directly (type-safe, no AnyHashable conversion)
      handler.singleSelection = singleSelection
      handler.multiSelection = multiSelection

      // Ensure focused item is visible
      handler.ensureFocusedItemVisible()

      FocusRegistration.register(context: context, handler: handler)
      listHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

      // Calculate visible rows
      let visibleRows = calculateVisibleRows(
        rows: rows,
        handler: handler
      )

      // Calculate row width based on the widest row content
      // If an explicit frame width is set, use the available width minus border padding
      let maxRowWidth = visibleRows.map(\.row.buffer.width).max() ?? 0
      let rowWidth: Int = if context.hasExplicitWidth {
        // Use available width minus 2 for borders only (content padding is 0)
        max(maxRowWidth, context.availableWidth - 2)
      } else {
        maxRowWidth
      }

      // Build content lines
      var lines: [String] = []
      var rowRegions: [(id: String, y: Int, height: Int)] = []

      // Top scroll indicator
      if handler.hasContentAbove {
        lines.append(renderScrollIndicator(direction: .up, width: rowWidth, palette: palette))
      }

      // Render each visible row with alternating colors based on list style
      // Track section-relative content index for alternating colors
      var sectionContentIndex = 0
      for (rowIndex, row) in visibleRows {
        // Reset section content index on header
        if case .header = row.type {
          sectionContentIndex = 0
        }

        let isFocused = handler.isFocused(at: rowIndex) && listHasFocus
        let isSelected = handler.isSelected(at: rowIndex)

        let styledLines = renderRow(
          row: row,
          isFocused: isFocused,
          isSelected: isSelected,
          rowWidth: rowWidth,
          sectionContentIndex: sectionContentIndex,
          style: style,
          context: context,
          palette: palette
        )
        let rowY = lines.count
        lines.append(contentsOf: styledLines)

        if row.isSelectable,
           !isDisabled,
           !context.isMeasuring,
           let interactionDispatcher = context.environment.interactionDispatcher
        {
          let interactionID = "list-row-interaction-\(persistedFocusID)-\(rowIndex)"
          let focusManager = context.environment.focusManager
          interactionDispatcher.registerClick(id: interactionID) {
            focusManager.focus(id: persistedFocusID)
            handler.updateFocus(to: rowIndex)
            handler.toggleSelectionAtFocusedIndex()
          }
          rowRegions.append((interactionID, rowY, styledLines.count))
        }

        // Increment section content index only for content rows
        if case .content = row.type {
          sectionContentIndex += 1
        }
      }

      // Bottom scroll indicator
      if handler.hasContentBelow {
        lines.append(renderScrollIndicator(direction: .down, width: rowWidth, palette: palette))
      }

      contentLines = lines
      let contentWidth = lines.map(\.strippedLength).max() ?? 0
      var regions = rowRegions.map {
        InteractionRegion(
          id: $0.id,
          rect: TerminalCellRect(x: 0, y: $0.y, width: contentWidth, height: $0.height)
        )
      }

      if !isDisabled,
         !context.isMeasuring,
         contentWidth > 0,
         !lines.isEmpty,
         let interactionDispatcher = context.environment.interactionDispatcher
      {
        let interactionID = "list-scroll-interaction-\(persistedFocusID)"
        interactionDispatcher.registerScroll(id: interactionID) { direction in
          let delta: Int
          switch direction {
          case .up:
            delta = -3
          case .down:
            delta = 3
          case .left, .right:
            return
          }

          handler.moveFocusBySelectableRows(by: delta)
        }
        regions.append(
          InteractionRegion(
            id: interactionID,
            rect: TerminalCellRect(x: 0, y: 0, width: contentWidth, height: context.availableHeight)
          )
        )
      }
      contentRegions = regions
    }

    return assembleContainer(
      contentLines: contentLines,
      contentRegions: contentRegions,
      context: context,
      palette: palette,
      style: style
    )
  }
}
