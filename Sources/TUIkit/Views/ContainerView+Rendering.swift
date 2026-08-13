//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContainerView+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Container View Core

/// Internal rendering implementation for ContainerView.
///
/// This struct contains all the complex rendering logic, allowing
/// ContainerView to have a proper `body: some View` that enables modifiers
/// to work correctly.
struct _ContainerViewCore<Content: View, Footer: View>: View, Renderable {
  /// The container title (rendered in border or header section).
  let title: String?

  /// The title color.
  let titleColor: Color?

  /// The main content.
  let content: Content

  /// The footer content (typically buttons).
  let footer: Footer?

  /// The container style configuration.
  let style: ContainerStyle

  /// The inner padding for the body.
  let padding: EdgeInsets

  var body: Never {
    fatalError("_ContainerViewCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let appearance = context.environment.appearance
    let effectiveBorderStyle = style.borderStyle ?? appearance.borderStyle
    let palette = context.environment.palette
    let borderColor = style.borderColor?.resolve(with: palette) ?? palette.border

    // Create inner context for content inside borders using shared helper.
    // Padding width reduction is handled by PaddingModifier.adjustContext.
    var innerContext = context.forBorderedContent()

    // Consume focus indicator so nested containers don't also show it.
    let indicatorColor = context.environment.focusIndicatorColor
    innerContext.environment.focusIndicatorColor = nil

    // Render body content first to determine its natural width.
    let paddedContent = content.padding(padding)
    let bodyBuffer = TUIkit.renderToBuffer(paddedContent, context: innerContext)

    // If body is empty and there's no footer, return empty buffer.
    // This preserves the convention that bordering empty content
    // produces nothing (e.g. `EmptyView().border()`).
    if bodyBuffer.isEmpty, footer == nil {
      return bodyBuffer
    }

    // Render footer with full available width for initial measurement.
    // This ensures the footer's natural width is included in the
    // innerWidth calculation, preventing truncation when footer content
    // (e.g. HStack with Spacer + Button) is wider than the body.
    let footerPadding = EdgeInsets(horizontal: 1, vertical: 0)
    let initialFooterBuffer: FrameBuffer?
    if let footerView = footer {
      let paddedFooter = footerView.padding(footerPadding)
      initialFooterBuffer = TUIkit.renderToBuffer(paddedFooter, context: innerContext)
    } else {
      initialFooterBuffer = nil
    }

    // Calculate inner width using shared helper
    let titleWidth = title.map { $0.count + 4 } ?? 0 // " Title " + borders
    let footerNaturalWidth = initialFooterBuffer?.width ?? 0
    let contentBasedWidth = max(titleWidth, bodyBuffer.width, footerNaturalWidth)
    let innerWidth = context.resolveContainerWidth(
      contentWidth: contentBasedWidth,
      innerAvailableWidth: innerContext.availableWidth
    )

    // Re-render footer constrained to the final innerWidth so that
    // Spacer() fills exactly the container's inner width.
    let footerBuffer: FrameBuffer?
    if let footerView = footer {
      var footerContext = innerContext
      footerContext.availableWidth = innerWidth - footerPadding.leading - footerPadding.trailing
      let paddedFooter = footerView.padding(footerPadding)
      footerBuffer = TUIkit.renderToBuffer(paddedFooter, context: footerContext)
    } else {
      footerBuffer = nil
    }

    return renderStandardStyle(
      bodyBuffer: bodyBuffer,
      footerBuffer: footerBuffer,
      innerWidth: innerWidth,
      borderStyle: effectiveBorderStyle,
      borderColor: borderColor,
      context: context,
      focusIndicatorColor: indicatorColor
    )
  }

  // MARK: - Standard Style Rendering

  /// Renders with title in top border (line, rounded, doubleLine, heavy).
  private func renderStandardStyle(
    bodyBuffer: FrameBuffer,
    footerBuffer: FrameBuffer?,
    innerWidth: Int,
    borderStyle: BorderStyle,
    borderColor: Color,
    context: RenderContext,
    focusIndicatorColor: Color? = nil
  ) -> FrameBuffer {
    let palette = context.environment.palette
    var lines: [String] = []
    var regions = bodyBuffer.regions.map {
      InteractionRegion(id: $0.id, rect: $0.rect.translatedBy(x: 1, y: 1))
    }

    // Top border (with title if present)
    if let titleText = title {
      lines.append(
        BorderRenderer.standardTopBorder(
          style: borderStyle,
          innerWidth: innerWidth,
          color: borderColor,
          title: titleText,
          titleColor: titleColor?.resolve(with: palette) ?? palette.accent,
          focusIndicatorColor: focusIndicatorColor
        )
      )
    } else {
      lines.append(
        BorderRenderer.standardTopBorder(
          style: borderStyle,
          innerWidth: innerWidth,
          color: borderColor,
          focusIndicatorColor: focusIndicatorColor
        )
      )
    }

    // Body lines (no background color applied)
    for line in bodyBuffer.lines {
      lines.append(
        BorderRenderer.standardContentLine(
          content: line,
          innerWidth: innerWidth,
          style: borderStyle,
          color: borderColor
        )
      )
    }

    // Footer section (if present)
    if let footerBuf = footerBuffer, !footerBuf.isEmpty {
      var footerOffset = 1 + bodyBuffer.height
      if style.showFooterSeparator {
        lines.append(
          BorderRenderer.standardDivider(
            style: borderStyle,
            innerWidth: innerWidth,
            color: borderColor
          )
        )
        footerOffset += 1
      }

      regions.append(contentsOf: footerBuf.regions.map {
        InteractionRegion(id: $0.id, rect: $0.rect.translatedBy(x: 1, y: footerOffset))
      })

      // Footer lines (no background - footer has its own styling)
      for line in footerBuf.lines {
        lines.append(
          BorderRenderer.standardContentLine(
            content: line,
            innerWidth: innerWidth,
            style: borderStyle,
            color: borderColor
          )
        )
      }
    }

    // Bottom border
    lines.append(
      BorderRenderer.standardBottomBorder(
        style: borderStyle,
        innerWidth: innerWidth,
        color: borderColor
      )
    )

    return FrameBuffer(lines: lines, regions: regions)
  }
}

// MARK: - Equatable Conformance

extension _ContainerViewCore: @preconcurrency Equatable where Content: Equatable, Footer: Equatable {
  static func == (lhs: _ContainerViewCore<Content, Footer>, rhs: _ContainerViewCore<Content, Footer>) -> Bool {
    lhs.title == rhs.title &&
      lhs.titleColor == rhs.titleColor &&
      lhs.content == rhs.content &&
      lhs.footer == rhs.footer &&
      lhs.style == rhs.style &&
      lhs.padding == rhs.padding
  }
}
