//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollView+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension ScrollView {
  public var body: some View {
    _ScrollViewCore(
      content: content,
      offset: offset,
      metrics: metrics,
      showsIndicators: showsIndicators
    )
  }
}

// MARK: - Core Constants

/// The `StateStorage` property indices of ``_ScrollViewCore``.
///
/// A generic type cannot hold static stored properties, so the indices live at
/// file scope instead of inside the core view.
private enum StateIndex {
  static let offset = 0
}

/// The number of context rows that one page step keeps.
private let pageOverlap = 2

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of ScrollView.
struct _ScrollViewCore<Content: View>: View, Renderable {
  let content: Content
  let offset: Binding<Int>?
  let metrics: Binding<ScrollMetrics>?
  let showsIndicators: Bool

  var body: Never {
    fatalError("_ScrollViewCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let contentBuffer = TUIkit.renderToBuffer(
      content,
      context: context.withChildIdentity(type: Content.self)
    )

    let viewportHeight = max(1, context.availableHeight)
    let maximumOffset = max(0, contentBuffer.height - viewportHeight)
    let (rawOffset, stateBox) = resolvedOffset(context: context)
    let clampedOffset = min(max(0, rawOffset), maximumOffset)

    report(
      ScrollMetrics(
        contentHeight: contentBuffer.height,
        viewportHeight: viewportHeight,
        maximumOffset: maximumOffset,
        pageSize: max(1, viewportHeight - pageOverlap),
        contentRegions: contentBuffer.regions
      ),
      context: context
    )

    var buffer = viewport(
      of: contentBuffer,
      offset: clampedOffset,
      height: viewportHeight,
      width: max(contentBuffer.width, context.availableWidth)
    )

    applyIndicators(to: &buffer, clampedOffset: clampedOffset, maximumOffset: maximumOffset, context: context)
    registerScrollInteraction(
      to: &buffer,
      context: context,
      stateBox: stateBox,
      maximumOffset: maximumOffset
    )

    return buffer
  }
}

// MARK: - Offset and Metrics

extension _ScrollViewCore {
  /// Returns the offset before the view clamps it, and the state box that
  /// owns it when the view keeps its own offset.
  ///
  /// The binding of the caller wins, and the state box is `nil` in that
  /// case because the binding is the persistence layer. Without a binding
  /// the view reads the offset that it keeps in state storage and returns
  /// the box so the wheel handler below can write a new value through the
  /// same persistent storage.
  private func resolvedOffset(context: RenderContext) -> (value: Int, box: StateBox<Int>?) {
    if let offset {
      return (offset.wrappedValue, nil)
    }
    guard let stateStorage = context.environment.stateStorage else {
      return (0, nil)
    }
    let key = StateStorage.StateKey(
      identity: context.identity,
      propertyIndex: StateIndex.offset
    )
    let box: StateBox<Int> = stateStorage.storage(for: key, default: 0)
    if !context.isMeasuring {
      stateStorage.markActive(context.identity)
    }
    return (box.value, box)
  }

  /// Writes the measured geometry through the metrics binding.
  ///
  /// The method returns early during a measurement pass and when the geometry
  /// did not change. An unconditional write would invalidate the render on
  /// every frame.
  private func report(_ measured: ScrollMetrics, context: RenderContext) {
    guard !context.isMeasuring,
          let metrics,
          metrics.wrappedValue != measured
    else {
      return
    }
    metrics.wrappedValue = measured
  }
}

// MARK: - Viewport Geometry

extension _ScrollViewCore {
  /// Returns the visible window of the content in viewport coordinates.
  ///
  /// The result always has `height` lines, and every line has the visible width
  /// `width`. The method slices whole rows instead of a rectangle, because a
  /// column clip drops the trailing ANSI reset of the widest line.
  ///
  /// - Parameters:
  ///   - buffer: The rendered content buffer.
  ///   - offset: The first visible content row, already clamped.
  ///   - height: The height of the viewport in terminal rows.
  ///   - width: The visible width of every viewport line.
  /// - Returns: The viewport buffer.
  private func viewport(
    of buffer: FrameBuffer,
    offset: Int,
    height: Int,
    width: Int
  ) -> FrameBuffer {
    let firstRow = min(offset, buffer.height)
    let lastRow = min(firstRow + height, buffer.height)

    var lines = buffer.lines[firstRow ..< lastRow].map { $0.padToVisibleWidth(width) }
    if lines.count < height {
      let blank = String(repeating: " ", count: width)
      lines.append(contentsOf: Array(repeating: blank, count: height - lines.count))
    }

    return FrameBuffer(
      lines: lines,
      width: width,
      regions: visibleRegions(of: buffer, offset: offset, height: height, width: width)
    )
  }

  /// Returns the content regions that overlap the viewport.
  ///
  /// The method drops a region that sits fully outside the viewport. The method
  /// reduces a partly visible region to its visible bounds. Every returned
  /// region uses viewport coordinates.
  ///
  /// - Parameters:
  ///   - buffer: The rendered content buffer.
  ///   - offset: The first visible content row, already clamped.
  ///   - height: The height of the viewport in terminal rows.
  ///   - width: The visible width of every viewport line.
  /// - Returns: The visible regions in viewport coordinates.
  private func visibleRegions(
    of buffer: FrameBuffer,
    offset: Int,
    height: Int,
    width: Int
  ) -> [InteractionRegion] {
    let viewportRect = TerminalCellRect(x: 0, y: offset, width: width, height: height)
    return buffer.regions.compactMap { region in
      guard let visible = region.rect.intersection(viewportRect) else {
        return nil
      }
      return InteractionRegion(id: region.id, rect: visible.translatedBy(x: 0, y: -offset))
    }
  }
}
