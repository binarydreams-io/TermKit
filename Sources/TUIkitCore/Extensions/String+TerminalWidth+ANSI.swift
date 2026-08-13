//  🖥️ TUIKit — Terminal UI Kit for Swift
//  String+TerminalWidth+ANSI.swift
//
//  Created by LAYERED.work
//  License: MIT

extension String {
  // MARK: - ANSI-Aware Splitting

  /// Returns the first `visibleCount` terminal cells worth of visible characters,
  /// preserving all ANSI codes that appear before or within that range.
  ///
  /// Wide characters (emoji, CJK) count as 2 cells. If a wide character would
  /// exceed the limit, it is excluded.
  ///
  /// - Parameter visibleCount: The number of terminal cells to include.
  /// - Returns: A substring with ANSI codes intact up to the visible boundary.
  public func ansiAwarePrefix(visibleCount: Int) -> String {
    guard visibleCount > 0 else { return "" }

    var result = ""
    var visible = 0
    var index = startIndex

    while index < endIndex, visible < visibleCount {
      // Check if we're at the start of an ANSI escape sequence
      if self[index] == "\u{1B}" {
        // Consume the entire ANSI sequence, which spends no visible cell
        let sequenceStart = index
        index = indexAfterEscapeSequence(startingAt: index)
        result += String(self[sequenceStart ..< index])
      } else {
        let charWidth = self[index].terminalWidth
        if visible + charWidth > visibleCount {
          break
        }
        result.append(self[index])
        visible += charWidth
        index = self.index(after: index)
      }
    }

    // The visible budget is spent, but escape sequences anywhere in the
    // remainder (most importantly a trailing reset) still apply to the
    // truncated content and must not be dropped. Drain the rest of the
    // string, appending complete escape sequences and discarding the
    // visible characters between them.
    while index < endIndex {
      if self[index] == "\u{1B}" {
        let sequenceStart = index
        index = indexAfterEscapeSequence(startingAt: index)
        result += String(self[sequenceStart ..< index])
      } else {
        index = self.index(after: index)
      }
    }

    return result
  }

  /// Returns everything after the first `dropCount` terminal cells of visible characters,
  /// preserving ANSI codes that appear at or after that boundary.
  ///
  /// Wide characters count as 2 cells.
  ///
  /// - Parameter dropCount: The number of terminal cells to skip.
  /// - Returns: The remainder of the string with ANSI codes intact.
  public func ansiAwareSuffix(droppingVisible dropCount: Int) -> String {
    var visible = 0
    var index = startIndex

    while index < endIndex, visible < dropCount {
      if self[index] == "\u{1B}" {
        // Skip the entire ANSI sequence
        index = indexAfterEscapeSequence(startingAt: index)
      } else {
        visible += self[index].terminalWidth
        index = self.index(after: index)
      }
    }

    guard index < endIndex else { return "" }
    return String(self[index...])
  }

  // MARK: - ANSI State Extraction

  /// Extracts all leading ANSI SGR sequences that appear before the first
  /// visible character and returns them concatenated.
  ///
  /// This captures the full styling state set up at the beginning of a line
  /// (e.g. background, foreground, dim) so it can be replayed to restore
  /// that state after an interruption (like an overlay insertion).
  ///
  /// Unlike scanning the entire string, this avoids picking up trailing
  /// codes that follow a reset (e.g. the lone background code appended by
  /// `applyPersistentBackground`).
  ///
  /// - Returns: The concatenated leading ANSI sequences, or an empty string
  ///   if the line starts with a visible character.
  public func leadingANSISequences() -> String {
    var result = ""
    var index = startIndex

    while index < endIndex {
      guard self[index] == "\u{1B}" else { break }

      let sequenceStart = index
      index = indexAfterEscapeSequence(startingAt: index)
      result += String(self[sequenceStart ..< index])
    }

    return result
  }
}
