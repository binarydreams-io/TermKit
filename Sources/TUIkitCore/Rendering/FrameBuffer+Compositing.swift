//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBuffer+Compositing.swift
//
//  Created by LAYERED.work
//  License: MIT

extension FrameBuffer {
  /// ANSI SGR reset sequence. Inlined to avoid depending on ANSIRenderer.
  fileprivate static let ansiReset = "\u{1B}[0m"

  /// Creates a new buffer with another buffer composited on top at the specified position.
  ///
  /// This performs character-level compositing: overlay characters replace base characters
  /// only where the overlay has visible content (non-space characters).
  ///
  /// - Parameters:
  ///   - overlay: The buffer to composite on top.
  ///   - position: The (x, y) offset where the overlay should be placed.
  /// - Returns: A new buffer with the overlay composited.
  public func composited(with overlay: Self, at position: (x: Int, y: Int)) -> Self {
    guard !overlay.isEmpty else { return self }

    let resultWidth = max(width, position.x + overlay.width)
    let resultHeight = max(height, position.y + overlay.height)

    var result: [String] = []

    for row in 0 ..< resultHeight {
      // Keep the original (unpadded) line for ANSI state extraction.
      // padToVisibleWidth appends unstyled spaces that lose the base's
      // ANSI state, so insertOverlay needs the original to restore it.
      let originalLine: String? = row < lines.count ? lines[row] : nil
      var baseLine: String = if let original = originalLine {
        original.padToVisibleWidth(resultWidth)
      } else {
        String(repeating: " ", count: resultWidth)
      }

      // Check if this row has overlay content
      let overlayRow = row - position.y
      if overlayRow >= 0, overlayRow < overlay.lines.count {
        let overlayLine = overlay.lines[overlayRow]
        if !overlayLine.isEmpty {
          // Insert overlay content at the x position
          baseLine = insertOverlay(
            base: baseLine,
            overlay: overlayLine,
            atColumn: position.x,
            originalBase: originalLine
          )
        }
      }

      result.append(baseLine)
    }

    let overlayRegions = overlay.regions.map {
      InteractionRegion(
        id: $0.id,
        rect: $0.rect.translatedBy(x: position.x, y: position.y)
      )
    }

    return Self(lines: result, regions: regions + overlayRegions)
  }

  /// Inserts overlay text into base text at the specified column position.
  ///
  /// Splits the base line at visible-character boundaries (ignoring ANSI codes)
  /// and preserves the base's ANSI styling in the prefix and suffix regions.
  /// The overlay replaces the base in its column range, with its own styling intact.
  ///
  /// After the overlay, the base's active ANSI state is restored before the
  /// suffix so the dimmed background (or any other base styling) continues
  /// seamlessly to the right of the overlay.
  ///
  /// - Parameters:
  ///   - base: The base text line (may contain ANSI codes).
  ///   - overlay: The overlay text to insert (may contain ANSI codes).
  ///   - column: The column position (0-based, in visible characters).
  ///   - originalBase: The original base line before padding, used to extract
  ///     the active ANSI state. If `nil`, the state is extracted from `base`.
  /// - Returns: The composited line with base styling preserved around the overlay.
  private func insertOverlay(
    base: String,
    overlay: String,
    atColumn column: Int,
    originalBase: String? = nil
  ) -> String {
    let overlayVisibleWidth = overlay.strippedLength
    let afterOverlayColumn = column + overlayVisibleWidth

    // Split the base into prefix (before overlay) and suffix (after overlay),
    // preserving all ANSI codes in both segments.
    let prefix = base.ansiAwarePrefix(visibleCount: column)
    let suffix = base.ansiAwareSuffix(droppingVisible: afterOverlayColumn)

    // Extract the leading ANSI state from the original (unpadded) base line.
    // The leading sequences contain the full styling setup (BG + FG + dim)
    // before any visible text. This is more reliable than scanning the whole
    // string, because applyPersistentBackground appends a lone BG code after
    // the final reset that doesn't represent the full styling state.
    let styleSource = originalBase ?? base
    let baseStyle = styleSource.leadingANSISequences()

    // Build: [prefix] + [reset] + [overlay] + [reset + base style restore] + [suffix]
    var result = prefix
    result += Self.ansiReset
    result += overlay
    result += Self.ansiReset
    result += baseStyle
    result += suffix

    return result
  }
}
