/// Measures and truncates text for terminal cell layouts.
public enum TerminalWidth {
  /// Returns the terminal display width of a string.
  public static func width(of text: String) -> Int {
    text.reduce(0) { $0 + width(of: $1) }
  }

  /// Returns the terminal display width of a grapheme.
  public static func width(of grapheme: Character) -> Int {
    let scalars = Array(grapheme.unicodeScalars)
    guard scalars.isEmpty == false else { return 0 }

    let regionalIndicatorCount = scalars.lazy.map(\.value).filter(isRegionalIndicator).count
    if regionalIndicatorCount >= 2 {
      return 2
    }

    let hasEmojiBase = scalars.contains { isEmojiBase($0.value) }
    let hasJoiner = scalars.contains { $0.value == 0x200D }
    let hasEmojiVariation = scalars.contains { $0.value == 0xFE0F }
    let hasKeycap = scalars.contains { $0.value == 0x20E3 }
    if hasEmojiBase, (hasJoiner || hasEmojiVariation || hasKeycap || scalars.contains { isEmojiWide($0.value) }) {
      return 2
    }

    var result = 0
    for scalar in scalars {
      let value = scalar.value
      if isZeroWidth(scalar) || isControl(value) {
        continue
      }
      result = Swift.max(result, isWide(value) ? 2 : 1)
    }
    return result
  }

  /// Returns the longest prefix that fits within a terminal cell width.
  public static func prefix(of text: String, fitting width: Int) -> String {
    precondition(width >= 0)
    var result = ""
    var resultWidth = 0
    for grapheme in text {
      let graphemeWidth = self.width(of: grapheme)
      if resultWidth + graphemeWidth <= width {
        result.append(grapheme)
        resultWidth += graphemeWidth
      } else if graphemeWidth == 2, resultWidth < width {
        result.append("�")
        resultWidth += 1
        break
      } else {
        break
      }
    }
    return result
  }

  private static func isControl(_ value: UInt32) -> Bool {
    value < 0x20 || (0x7F ... 0x9F).contains(value)
  }

  private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .enclosingMark:
      return true
    default:
      break
    }
    let value = scalar.value
    return value == 0x200B || value == 0x200C || value == 0x200D || (0xFE00 ... 0xFE0F).contains(value)
      || (0xE0100 ... 0xE01EF).contains(value) || (0x1F3FB ... 0x1F3FF).contains(value)
  }

  private static func isRegionalIndicator(_ value: UInt32) -> Bool {
    (0x1F1E6 ... 0x1F1FF).contains(value)
  }

  private static func isEmojiBase(_ value: UInt32) -> Bool {
    isEmojiWide(value) || isRegionalIndicator(value) || value == 0x00A9 || value == 0x00AE
      || value == 0x23 || value == 0x2A || (0x30 ... 0x39).contains(value) || (0x203C ... 0x3299).contains(value)
  }

  private static func isEmojiWide(_ value: UInt32) -> Bool {
    (0x1F000 ... 0x1FAFF).contains(value)
  }

  private static func isWide(_ value: UInt32) -> Bool {
    value >= 0x1100
      && (value <= 0x115F
        || value == 0x2329
        || value == 0x232A
        || (0x2E80 ... 0x303E).contains(value)
        || (0x3040 ... 0xA4CF).contains(value)
        || (0xAC00 ... 0xD7A3).contains(value)
        || (0xF900 ... 0xFAFF).contains(value)
        || (0xFE10 ... 0xFE19).contains(value)
        || (0xFE30 ... 0xFE6F).contains(value)
        || (0xFF00 ... 0xFF60).contains(value)
        || (0xFFE0 ... 0xFFE6).contains(value)
        || isEmojiWide(value)
        || (0x20000 ... 0x3FFFD).contains(value))
  }
}
