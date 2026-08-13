//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyEvent+Types.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Event

/// Represents a keyboard event.
public struct KeyEvent: Equatable, Sendable {
  /// The key that was pressed.
  public let key: Key

  /// Whether the Ctrl modifier was held.
  public let ctrl: Bool

  /// Whether the Alt/Option modifier was held.
  public let alt: Bool

  /// Whether the Shift modifier was held.
  public let shift: Bool

  /// Creates a key event.
  public init(key: Key, ctrl: Bool = false, alt: Bool = false, shift: Bool = false) {
    self.key = key
    self.ctrl = ctrl
    self.alt = alt
    self.shift = shift
  }

  /// Creates a key event from a character.
  public init(character: Character) {
    self.key = .character(character)
    self.ctrl = false
    self.alt = false
    self.shift = character.isUppercase
  }
}

// MARK: - Key

/// Represents a keyboard key.
public enum Key: Hashable, Sendable {
  // Special keys
  case escape
  case enter
  case tab
  case backspace
  case delete
  case space

  // Arrow keys
  case up
  case down
  case left
  case right

  // Navigation keys
  case home
  case end
  case pageUp
  case pageDown

  /// Function keys
  case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

  /// Character key
  case character(Character)

  /// Bracketed paste (bulk text from terminal paste operation)
  case paste(String)

  /// Creates a Key from a character if it's a simple character.
  public static func from(_ char: Character) -> Self {
    .character(char)
  }
}
