/// Modifier keys attached to a terminal key event.
public struct TerminalKeyModifiers: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let alt = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let `super` = Self(rawValue: 1 << 3)
    public static let hyper = Self(rawValue: 1 << 4)
    public static let meta = Self(rawValue: 1 << 5)
    public static let capsLock = Self(rawValue: 1 << 6)
    public static let numLock = Self(rawValue: 1 << 7)
}

/// A key recognized by the terminal input parser.
public enum TerminalKey: Equatable, Hashable, Sendable {
    case text(String)
    case escape
    case enter
    case tab
    case backspace
    case insert
    case delete
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case function(Int)
}

/// The action reported for a key.
public enum TerminalKeyAction: Equatable, Hashable, Sendable {
    case press
    case `repeat`
    case release
}

/// A parsed terminal key event.
public struct TerminalKeyEvent: Equatable, Hashable, Sendable {
    public var key: TerminalKey
    public var modifiers: TerminalKeyModifiers
    public var action: TerminalKeyAction

    public init(
        key: TerminalKey,
        modifiers: TerminalKeyModifiers = [],
        action: TerminalKeyAction = .press
    ) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }
}

/// A terminal mouse button.
public enum TerminalMouseButton: Equatable, Hashable, Sendable {
    case left
    case middle
    case right
}

/// A mouse wheel direction.
public enum TerminalScrollDirection: Equatable, Hashable, Sendable {
    case up
    case down
    case left
    case right
}

/// A terminal mouse action.
public enum TerminalMouseAction: Equatable, Hashable, Sendable {
    case press(TerminalMouseButton)
    case release(TerminalMouseButton?)
    case drag(TerminalMouseButton)
    case move
    case scroll(TerminalScrollDirection)
}

/// A parsed SGR mouse event.
public struct TerminalMouseEvent: Equatable, Hashable, Sendable {
    public var action: TerminalMouseAction
    public var position: TerminalCellPoint
    public var modifiers: TerminalKeyModifiers

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
    case gained
    case lost
}

/// An event produced from terminal input bytes.
public enum TerminalInputEvent: Equatable, Hashable, Sendable {
    case key(TerminalKeyEvent)
    case paste(String)
    case mouse(TerminalMouseEvent)
    case focus(TerminalFocusEvent)
}

/// A recoverable terminal input parsing error.
public enum TerminalInputParseError: Error, Equatable, Sendable {
    case invalidUTF8([UInt8])
    case unknownEscapeSequence([UInt8])
    case invalidMouseSequence([UInt8])
    case invalidKittyKeyboardSequence([UInt8])
    case sequenceTooLong(limit: Int)
    case pasteTooLarge(limit: Int)
    case incompleteSequence([UInt8])
}

/// Events and recoverable errors produced by one parser operation.
public struct TerminalInputParserOutput: Equatable, Sendable {
    public var events: [TerminalInputEvent]
    public var errors: [TerminalInputParseError]

    public init(events: [TerminalInputEvent] = [], errors: [TerminalInputParseError] = []) {
        self.events = events
        self.errors = errors
    }
}

/// Resource limits and optional protocols for terminal input parsing.
public struct TerminalInputParserConfiguration: Equatable, Sendable {
    public var maximumSequenceByteCount: Int
    public var maximumPasteByteCount: Int
    public var enablesKittyKeyboard: Bool

    public init(
        maximumSequenceByteCount: Int = 1_024,
        maximumPasteByteCount: Int = 1_048_576,
        enablesKittyKeyboard: Bool = false
    ) {
        self.maximumSequenceByteCount = min(max(maximumSequenceByteCount, 16), 65_536)
        self.maximumPasteByteCount = min(max(maximumPasteByteCount, 1), 16_777_216)
        self.enablesKittyKeyboard = enablesKittyKeyboard
    }
}
