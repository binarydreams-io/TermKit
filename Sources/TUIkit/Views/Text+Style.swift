//  TUIKit - Terminal UI Kit for Swift
//  Text+Style.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TextStyle

/// The style of a text view.
///
/// Contains all formatting options like color, bold, etc.
public struct TextStyle: Sendable, Equatable {
  /// The foreground color of the text.
  public var foregroundColor: Color?

  /// The background color of the text.
  public var backgroundColor: Color?

  /// Whether the text is bold.
  public var isBold: Bool = false

  /// Whether the text is italic.
  public var isItalic: Bool = false

  /// Whether the text is underlined.
  public var isUnderlined: Bool = false

  /// Whether the text is strikethrough.
  public var isStrikethrough: Bool = false

  /// Whether the text is dimmed.
  public var isDim: Bool = false

  /// Whether the text blinks.
  public var isBlink: Bool = false

  /// Whether foreground and background colors are inverted.
  public var isInverted: Bool = false

  /// Creates a default TextStyle with no formatting.
  public init() {}
}

// MARK: - Public API

extension TextStyle {
  /// Resolves any semantic colors in this style against the given palette.
  ///
  /// Non-semantic colors are left unchanged. Call this before passing
  /// the style to `ANSIRenderer`.
  ///
  /// - Parameter palette: The palette to resolve semantic colors against.
  /// - Returns: A copy with all colors resolved to concrete values.
  public func resolved(with palette: any Palette) -> TextStyle {
    var copy = self
    copy.foregroundColor = foregroundColor?.resolve(with: palette)
    copy.backgroundColor = backgroundColor?.resolve(with: palette)
    return copy
  }
}
