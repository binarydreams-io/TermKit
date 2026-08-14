/// Modifier keys attached to a terminal key event.
public struct TerminalKeyModifiers: OptionSet, Equatable, Hashable, Sendable {
  /// The encoded modifier bit field.
  public let rawValue: UInt16

  /// Creates modifiers from an encoded bit field.
  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  /// The Shift modifier.
  public static let shift = Self(rawValue: 1 << 0)
  /// The Alt modifier.
  public static let alt = Self(rawValue: 1 << 1)
  /// The Control modifier.
  public static let control = Self(rawValue: 1 << 2)
  /// The Super modifier.
  public static let `super` = Self(rawValue: 1 << 3)
  /// The Hyper modifier.
  public static let hyper = Self(rawValue: 1 << 4)
  /// The Meta modifier.
  public static let meta = Self(rawValue: 1 << 5)
  /// The Caps Lock modifier.
  public static let capsLock = Self(rawValue: 1 << 6)
  /// The Num Lock modifier.
  public static let numLock = Self(rawValue: 1 << 7)
}

/// A key recognized by the terminal input parser.
public enum TerminalKey: Equatable, Hashable, Sendable {
  /// Text input.
  case text(String)
  /// The Escape key.
  case escape
  /// The Enter key.
  case enter
  /// The Tab key.
  case tab
  /// The Backspace key.
  case backspace
  /// The Insert key.
  case insert
  /// The Delete key.
  case delete
  /// The Up Arrow key.
  case up
  /// The Down Arrow key.
  case down
  /// The Left Arrow key.
  case left
  /// The Right Arrow key.
  case right
  /// The Home key.
  case home
  /// The End key.
  case end
  /// The Page Up key.
  case pageUp
  /// The Page Down key.
  case pageDown
  /// A numbered function key.
  case function(Int)
}

/// The action reported for a key.
public enum TerminalKeyAction: Equatable, Hashable, Sendable {
  /// The key was pressed.
  case press
  /// The key press repeated.
  case `repeat`
  /// The key was released.
  case release
}

/// A parsed terminal key event.
public struct TerminalKeyEvent: Equatable, Hashable, Sendable {
  /// The reported key.
  public var key: TerminalKey
  /// The active modifiers.
  public var modifiers: TerminalKeyModifiers
  /// The key action.
  public var action: TerminalKeyAction
  /// The shifted key reported by the Kitty keyboard protocol.
  public var shiftedKey: UnicodeScalar?
  /// The key at the same position in the standard PC-101 layout.
  public var baseLayoutKey: UnicodeScalar?

  /// Text normalized to the standard PC-101 layout when possible.
  ///
  /// This property uses Kitty base-layout data first. It otherwise maps both cases of the full JCUKEN layout.
  /// ASCII digits and punctuation pass through unchanged.
  ///
  /// - Complexity: O(n), where n is the number of Unicode scalars in the text.
  public var normalizedText: String? {
    guard case let .text(text) = key else { return nil }
    if let baseLayoutKey {
      return String(baseLayoutKey)
    }
    if modifiers.contains(.shift), let shiftedKey {
      return String(shiftedKey)
    }
    var normalized = ""
    for scalar in text.unicodeScalars {
      normalized.unicodeScalars.append(Self.jcukenFallback[scalar] ?? scalar)
    }
    return normalized
  }

  /// Creates a terminal key event.
  public init(
    key: TerminalKey,
    modifiers: TerminalKeyModifiers = [],
    action: TerminalKeyAction = .press
  ) {
    self.init(
      key: key,
      modifiers: modifiers,
      action: action,
      shiftedKey: nil,
      baseLayoutKey: nil
    )
  }

  /// Creates a terminal key event with Kitty alternate-key data.
  public init(
    key: TerminalKey,
    modifiers: TerminalKeyModifiers = [],
    action: TerminalKeyAction = .press,
    shiftedKey: UnicodeScalar?,
    baseLayoutKey: UnicodeScalar? = nil
  ) {
    self.key = key
    self.modifiers = modifiers
    self.action = action
    self.shiftedKey = shiftedKey
    self.baseLayoutKey = baseLayoutKey
  }

  private static let jcukenFallback: [UnicodeScalar: UnicodeScalar] = {
    let cyrillic = "ёйцукенгшщзхъфывапролджэячсмитьбюЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ"
    let pc101 = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>"
    return Dictionary(uniqueKeysWithValues: zip(cyrillic.unicodeScalars, pc101.unicodeScalars))
  }()
}

/// A terminal mouse button.
public enum TerminalMouseButton: Equatable, Hashable, Sendable {
  /// The left mouse button.
  case left
  /// The middle mouse button.
  case middle
  /// The right mouse button.
  case right
}

/// A mouse wheel direction.
public enum TerminalScrollDirection: Equatable, Hashable, Sendable {
  /// Upward scrolling.
  case up
  /// Downward scrolling.
  case down
  /// Leftward scrolling.
  case left
  /// Rightward scrolling.
  case right
}

/// A terminal mouse action.
public enum TerminalMouseAction: Equatable, Hashable, Sendable {
  /// A mouse button press.
  case press(TerminalMouseButton)
  /// A mouse button release, or an unspecified release.
  case release(TerminalMouseButton?)
  /// A drag with a pressed button.
  case drag(TerminalMouseButton)
  /// Pointer movement without a pressed button.
  case move
  /// A mouse wheel action.
  case scroll(TerminalScrollDirection)
}

/// A parsed SGR mouse event.
public struct TerminalMouseEvent: Equatable, Hashable, Sendable {
  /// The mouse action.
  public var action: TerminalMouseAction
  /// The zero-based terminal position.
  public var position: TerminalCellPoint
  /// The active keyboard modifiers.
  public var modifiers: TerminalKeyModifiers

  /// Creates a terminal mouse event.
  public init(
    action: TerminalMouseAction,
    position: TerminalCellPoint,
    modifiers: TerminalKeyModifiers = []
  ) {
    self.action = action
    self.position = position
    self.modifiers = modifiers
  }
}

/// A focus change reported by a terminal.
public enum TerminalFocusEvent: Equatable, Hashable, Sendable {
  /// The terminal gained focus.
  case gained
  /// The terminal lost focus.
  case lost
}

/// An event produced from terminal input bytes.
public enum TerminalInputEvent: Equatable, Hashable, Sendable {
  /// A key event.
  case key(TerminalKeyEvent)
  /// A bracketed-paste payload.
  case paste(String)
  /// An SGR mouse event.
  case mouse(TerminalMouseEvent)
  /// A terminal focus event.
  case focus(TerminalFocusEvent)
}

/// A recoverable terminal input parsing error.
public enum TerminalInputParseError: Error, Equatable, Sendable {
  /// Input contains invalid UTF-8 bytes.
  case invalidUTF8([UInt8])
  /// An escape sequence is not recognized.
  case unknownEscapeSequence([UInt8])
  /// An SGR mouse sequence is invalid.
  case invalidMouseSequence([UInt8])
  /// A Kitty keyboard sequence is invalid.
  case invalidKittyKeyboardSequence([UInt8])
  /// An escape sequence exceeds the configured limit.
  case sequenceTooLong(limit: Int)
  /// A paste payload exceeds the configured limit.
  case pasteTooLarge(limit: Int)
  /// The input ended inside a sequence.
  case incompleteSequence([UInt8])
}

/// Events and recoverable errors produced by one parser operation.
public struct TerminalInputParserOutput: Equatable, Sendable {
  /// The parsed input events.
  public var events: [TerminalInputEvent]
  /// The recoverable parsing errors.
  public var errors: [TerminalInputParseError]

  /// Creates parser output.
  public init(events: [TerminalInputEvent] = [], errors: [TerminalInputParseError] = []) {
    self.events = events
    self.errors = errors
  }
}

/// Resource limits and optional protocols for terminal input parsing.
public struct TerminalInputParserConfiguration: Equatable, Sendable {
  /// The maximum escape-sequence size in bytes.
  public var maximumSequenceByteCount: Int
  /// The maximum paste payload size in bytes.
  public var maximumPasteByteCount: Int
  /// Whether Kitty keyboard sequences are parsed.
  public var enablesKittyKeyboard: Bool

  /// Creates a bounded parser configuration.
  public init(
    maximumSequenceByteCount: Int = 1024,
    maximumPasteByteCount: Int = 1048576,
    enablesKittyKeyboard: Bool = false
  ) {
    self.maximumSequenceByteCount = min(max(maximumSequenceByteCount, 16), 65536)
    self.maximumPasteByteCount = min(max(maximumPasteByteCount, 1), 16_777_216)
    self.enablesKittyKeyboard = enablesKittyKeyboard
  }
}
