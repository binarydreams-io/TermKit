//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NotificationHostModifier+Surfaces.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Notification Surface

/// How a notification host paints each notification.
///
/// Both surfaces fade with the notification's opacity.
public enum NotificationSurface: Sendable {
    /// A box in the palette's border color. The default.
    case bordered

    /// A quiet surface: a leading accent rail on a filled background, and no
    /// border. Use it when a notification should read as part of the
    /// application's own chrome instead of a floating dialog.
    ///
    /// - Parameters:
    ///   - accent: The color of the leading rail.
    ///   - background: The fill behind the message.
    case rail(accent: Color, background: Color)
}

// MARK: - Surface Rendering

extension NotificationHostModifier {
    /// The columns kept between the surface edge and the message.
    private var horizontalPadding: Int { 1 }

    /// Renders one notification as a bordered box.
    ///
    /// Internal (not `private`) so `renderToBuffer(context:)`, defined in
    /// `NotificationHostModifier.swift`, can call it across the file split.
    func borderedEntry(
        _ entry: NotificationEntry,
        foreground: Color,
        border: Color,
        context: RenderContext
    ) -> FrameBuffer {
        let innerWidth = max(1, width - BorderRenderer.borderWidthOverhead)
        let textWidth = max(1, innerWidth - horizontalPadding * 2)
        let pad = String(repeating: " ", count: horizontalPadding)

        // Build content lines with horizontal padding, padded to full inner
        // width so the Box spans the intended width.
        var contentLines: [String] = []
        for line in NotificationTiming.wordWrap(entry.message, maxWidth: textWidth) {
            let styledLine = pad + ANSIRenderer.colorize(line, foreground: foreground)
            contentLines.append(styledLine.padToVisibleWidth(innerWidth))
        }

        var boxContext = context
        boxContext.availableWidth = width
        return TUIkit.renderToBuffer(
            Box(lines: contentLines, color: border),
            context: boxContext
        )
    }

    /// Renders one notification as a filled surface with a leading rail.
    ///
    /// Internal (not `private`) so `renderToBuffer(context:)`, defined in
    /// `NotificationHostModifier.swift`, can call it across the file split.
    func railEntry(
        _ entry: NotificationEntry,
        foreground: Color,
        accent: Color,
        background: Color,
        context: RenderContext
    ) -> FrameBuffer {
        let railWidth = 1
        let bodyWidth = max(1, width - railWidth)
        let textWidth = max(1, bodyWidth - horizontalPadding * 2)
        let pad = String(repeating: " ", count: horizontalPadding)
        let rail = ANSIRenderer.colorize("┃", foreground: accent)

        var lines: [String] = []
        for line in NotificationTiming.wordWrap(entry.message, maxWidth: textWidth) {
            let body = (pad + ANSIRenderer.colorize(line, foreground: foreground))
                .padToVisibleWidth(bodyWidth)
            lines.append((rail + body).withPersistentBackground(background) + ANSIRenderer.reset)
        }
        return FrameBuffer(lines: lines)
    }
}
