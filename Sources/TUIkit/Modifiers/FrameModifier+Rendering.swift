//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameModifier+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Renderable

extension FlexibleFrameView: Renderable {
  public func renderToBuffer(context: RenderContext) -> FrameBuffer {
    // Calculate the target width based on constraints
    let targetWidth: Int = if let maximumWidth = maxWidth {
      switch maximumWidth {
      case .infinity:
        context.availableWidth
      case let .fixed(value):
        min(value, context.availableWidth)
      }
    } else if let ideal = idealWidth {
      min(ideal, context.availableWidth)
    } else {
      // No max constraint - render with available width, then size to content
      context.availableWidth
    }

    // Calculate the target height based on constraints
    let targetHeight: Int? = if let maximumHeight = maxHeight {
      switch maximumHeight {
      case .infinity:
        context.availableHeight
      case let .fixed(value):
        min(value, context.availableHeight)
      }
    } else if let ideal = idealHeight {
      min(ideal, context.availableHeight)
    } else {
      nil // Use intrinsic height
    }

    // Create context for content with constrained width
    var contentContext = context
    contentContext.availableWidth = targetWidth
    if let height = targetHeight {
      contentContext.availableHeight = height
    }

    // Mark that an explicit width constraint was set
    if minWidth != nil || idealWidth != nil || maxWidth != nil {
      contentContext.hasExplicitWidth = true
    }

    // Render content
    let buffer = TUIkit.renderToBuffer(content, context: contentContext)

    // Apply minimum constraints
    var finalWidth = buffer.width
    var finalHeight = buffer.height

    if let minimumWidth = minWidth {
      finalWidth = max(finalWidth, minimumWidth)
    }
    if let minimumHeight = minHeight {
      finalHeight = max(finalHeight, minimumHeight)
    }

    // Apply maximum constraints (expand to fill if infinity)
    if let maximumWidth = maxWidth, case .infinity = maximumWidth {
      finalWidth = context.availableWidth
    }
    if let maximumHeight = maxHeight, case .infinity = maximumHeight {
      finalHeight = context.availableHeight
    }

    // If size matches buffer, return as-is
    if finalWidth == buffer.width, finalHeight == buffer.height {
      return buffer
    }

    // Otherwise, align content within the frame
    return alignBuffer(buffer, toWidth: finalWidth, height: finalHeight)
  }

  /// Aligns buffer content within the target frame size.
  private func alignBuffer(_ buffer: FrameBuffer, toWidth targetWidth: Int, height targetHeight: Int) -> FrameBuffer {
    var result: [String] = []

    // Calculate vertical offset for alignment
    let verticalOffset: Int = switch alignment.vertical {
    case .top:
      0
    case .center:
      max(0, (targetHeight - buffer.height) / 2)
    case .bottom:
      max(0, targetHeight - buffer.height)
    }

    for row in 0 ..< targetHeight {
      let contentRow = row - verticalOffset
      let line: String = if contentRow >= 0, contentRow < buffer.height {
        buffer.lines[contentRow]
      } else {
        ""
      }

      // Align horizontally within the frame
      let aligned = alignHorizontally(line, toWidth: targetWidth)
      result.append(aligned)
    }

    let regions = alignedRegions(
      in: buffer,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      verticalOffset: verticalOffset
    )
    return FrameBuffer(lines: result, regions: regions)
  }

  /// Translates and clips regions using the same per-line alignment as the text.
  private func alignedRegions(
    in buffer: FrameBuffer,
    targetWidth: Int,
    targetHeight: Int,
    verticalOffset: Int
  ) -> [InteractionRegion] {
    let outputBounds = TerminalCellRect(
      x: 0,
      y: 0,
      width: max(targetWidth, buffer.width),
      height: targetHeight
    )
    var result: [InteractionRegion] = []

    for region in buffer.regions {
      var pieces: [TerminalCellRect] = []

      for sourceRow in region.rect.y ..< region.rect.maxY {
        let destinationRow = sourceRow + verticalOffset
        guard sourceRow < buffer.height, destinationRow >= 0, destinationRow < targetHeight else {
          continue
        }

        let lineWidth = buffer.lines[sourceRow].strippedLength
        let offset = horizontalOffset(for: lineWidth, in: targetWidth)
        let translated = TerminalCellRect(
          x: region.rect.x + offset,
          y: destinationRow,
          width: region.rect.width,
          height: 1
        )
        guard let visible = translated.intersection(outputBounds) else {
          continue
        }

        if let previous = pieces.last,
           previous.x == visible.x,
           previous.width == visible.width,
           previous.maxY == visible.y
        {
          pieces[pieces.count - 1].height += 1
        } else {
          pieces.append(visible)
        }
      }

      result.append(contentsOf: pieces.map { InteractionRegion(id: region.id, rect: $0) })
    }

    return result
  }

  /// Aligns a single line within the given width.
  private func alignHorizontally(_ line: String, toWidth targetWidth: Int) -> String {
    let visibleWidth = line.strippedLength

    if visibleWidth >= targetWidth {
      return line
    }

    let padding = targetWidth - visibleWidth

    switch alignment.horizontal {
    case .leading:
      return line + String(repeating: " ", count: padding)
    case .center:
      let left = padding / 2
      let right = padding - left
      return String(repeating: " ", count: left) + line + String(repeating: " ", count: right)
    case .trailing:
      return String(repeating: " ", count: padding) + line
    }
  }

  /// Returns the leading offset for one aligned line.
  private func horizontalOffset(for visibleWidth: Int, in targetWidth: Int) -> Int {
    guard visibleWidth < targetWidth else { return 0 }

    switch alignment.horizontal {
    case .leading:
      return 0
    case .center:
      return (targetWidth - visibleWidth) / 2
    case .trailing:
      return targetWidth - visibleWidth
    }
  }
}
