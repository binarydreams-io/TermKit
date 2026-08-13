//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollIndicator.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Scroll Direction

/// The direction of a scroll indicator arrow.
enum ScrollDirection {
    case up, down
}

// MARK: - Scroll Indicator Rendering

/// Renders a scroll indicator line with an arrow and label.
///
/// Used by `_ListCore`, `_TableCore`, and `ScrollView` to show "more above" /
/// "more below" indicators when content extends beyond the visible viewport.
///
/// The indicator is chrome, not content: it renders in the muted tertiary
/// foreground and sits against the trailing edge, where a scrollbar or a
/// scroll counter would be. A centred label reads as a line of content and
/// pulls the eye into the middle of the viewport.
///
/// - Parameters:
///   - direction: Whether the indicator points up or down.
///   - width: The total width available for the indicator line.
///   - palette: The color palette for styling.
/// - Returns: A styled string with a trailing scroll indicator.
@MainActor
func renderScrollIndicator(direction: ScrollDirection, width: Int, palette: any Palette) -> String {
    let arrow = direction == .up ? "▲" : "▼"
    let label = direction == .up ? " more above " : " more below "

    let styledArrow = ANSIRenderer.colorize(arrow, foreground: palette.foregroundTertiary)
    let styledLabel = ANSIRenderer.colorize(label, foreground: palette.foregroundTertiary)

    let indicatorWidth = 1 + label.count
    let padding = max(0, width - indicatorWidth)

    return String(repeating: " ", count: padding) + styledArrow + styledLabel
}
