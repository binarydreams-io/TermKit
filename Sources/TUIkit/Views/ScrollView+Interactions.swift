//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollView+Interactions.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Scroll Indicators

extension _ScrollViewCore {
  /// Overlays scroll indicators on the first and last viewport lines.
  ///
  /// The method replaces a line instead of inserting one, so the viewport
  /// keeps its fixed row count. The top indicator appears only when rows
  /// scrolled past the first row of the content, and the bottom indicator
  /// appears only when rows remain below the last visible row.
  ///
  /// A one-line viewport that qualifies for both indicators keeps the
  /// bottom one only, because the method applies the top overlay first and
  /// the bottom overlay second, into the same single line.
  ///
  /// The method also drops or shrinks any interaction region that sits
  /// under an overlaid row. Without this, a content region translated into
  /// the viewport by ``visibleRegions(of:offset:height:width:)`` — a
  /// `Button`, a selectable row, anything the caller nested — would stay
  /// clickable underneath the glyph that visually replaced it.
  ///
  /// - Parameters:
  ///   - buffer: The viewport buffer to overlay in place.
  ///   - clampedOffset: The first visible content row, already clamped.
  ///   - maximumOffset: The largest offset that still fills the viewport.
  ///   - context: The render context, used to read the palette.
  func applyIndicators(
    to buffer: inout FrameBuffer,
    clampedOffset: Int,
    maximumOffset: Int,
    context: RenderContext
  ) {
    guard showsIndicators, !buffer.lines.isEmpty else {
      return
    }

    let palette = context.environment.palette
    var lines = buffer.lines
    let lastLine = lines.count - 1
    var overlaidRows: [Int] = []
    // The indicator belongs to the viewport, not to the content: content
    // wider than the viewport is clipped by the caller, and an indicator
    // laid out against the content width would lose its trailing glyphs
    // with it.
    let indicatorWidth = max(1, min(buffer.width, context.availableWidth))

    if clampedOffset > 0 {
      lines[0] = renderScrollIndicator(direction: .up, width: indicatorWidth, palette: palette)
        .padToVisibleWidth(buffer.width)
      overlaidRows.append(0)
    }
    if clampedOffset < maximumOffset {
      lines[lastLine] = renderScrollIndicator(direction: .down, width: indicatorWidth, palette: palette)
        .padToVisibleWidth(buffer.width)
      overlaidRows.append(lastLine)
    }
    buffer.lines = lines

    guard !overlaidRows.isEmpty else {
      return
    }
    buffer.regions = buffer.regions.compactMap { region in
      var rect: TerminalCellRect? = region.rect
      for row in overlaidRows {
        guard let current = rect else {
          break
        }
        rect = current.excludingRow(row)
      }
      return rect.map { InteractionRegion(id: region.id, rect: $0) }
    }
  }
}

extension TerminalCellRect {
  /// Returns the rectangle with the given row removed from its span.
  ///
  /// An indicator overlay only ever touches the viewport's first or last
  /// row, so this only shrinks from the top or the bottom of the
  /// rectangle. Shrinking a one-row rectangle drops it entirely (`nil`)
  /// instead of returning an empty-height rectangle, so a caller does not
  /// need a second emptiness check. A row inside the rectangle that is
  /// neither its top nor its bottom row cannot be excluded without
  /// splitting the rectangle in two, which no caller here needs; the
  /// method drops the whole rectangle instead of leaving a click-through
  /// gap under the glyph.
  ///
  /// - Parameter row: The viewport row the indicator overlay replaced.
  /// - Returns: The rectangle without that row, or `nil` when nothing of
  ///   the rectangle remains.
  fileprivate func excludingRow(_ row: Int) -> TerminalCellRect? {
    guard y <= row, row < maxY else {
      return self
    }
    guard height > 1 else {
      return nil
    }
    if row == y {
      return TerminalCellRect(x: x, y: y + 1, width: width, height: height - 1)
    }
    if row == maxY - 1 {
      return TerminalCellRect(x: x, y: y, width: width, height: height - 1)
    }
    return nil
  }
}

// MARK: - Mouse Wheel

extension _ScrollViewCore {
  /// Registers the mouse wheel handler and its full-viewport scroll region.
  ///
  /// The handler moves the offset by three rows per notch, clamped to
  /// `0...maximumOffset`. The write goes through the caller's binding when
  /// present; otherwise it goes through the state box that stores the
  /// view's own offset. A `StateBox` write already signals the render
  /// invalidation sink through its own setter — the state-box equivalent of
  /// `_ListCore`'s `handler.onVisualStateChange` callback.
  ///
  /// The method registers nothing during a measurement pass or when no
  /// interaction dispatcher is available, mirroring `_ToggleCore`.
  ///
  /// - Parameters:
  ///   - buffer: The viewport buffer to append the scroll region to.
  ///   - context: The render context carrying identity and environment.
  ///   - stateBox: The offset's state box, or `nil` when a binding owns it.
  ///   - maximumOffset: The largest offset that still fills the viewport.
  func registerScrollInteraction(
    to buffer: inout FrameBuffer,
    context: RenderContext,
    stateBox: StateBox<Int>?,
    maximumOffset: Int
  ) {
    guard !context.isMeasuring,
          let interactionDispatcher = context.environment.interactionDispatcher
    else {
      return
    }

    let interactionID = "scrollview-scroll-\(context.identity.path)"
    let offsetBinding = offset
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

      if let offsetBinding {
        offsetBinding.wrappedValue = min(max(0, offsetBinding.wrappedValue + delta), maximumOffset)
      } else if let stateBox {
        stateBox.value = min(max(0, stateBox.value + delta), maximumOffset)
      }
    }

    buffer.regions.append(
      InteractionRegion(
        id: interactionID,
        rect: TerminalCellRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
      )
    )
  }
}
