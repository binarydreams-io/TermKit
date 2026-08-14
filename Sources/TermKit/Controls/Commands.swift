/// Modifier keys held during keyboard input.
public struct KeyboardModifiers: OptionSet, Sendable, Hashable {
    /// The option-set bit field.
    public let rawValue: UInt8

    /// Creates modifiers from a bit field.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The Control key.
    public static let control = KeyboardModifiers(rawValue: 1 << 0)
    /// The Option or Alt key.
    public static let option = KeyboardModifiers(rawValue: 1 << 1)
    /// The Shift key.
    public static let shift = KeyboardModifiers(rawValue: 1 << 2)
    /// The Command key.
    public static let command = KeyboardModifiers(rawValue: 1 << 3)
}

/// A keyboard key independent of modifiers.
public enum KeyboardKey: Sendable, Hashable {
    /// A printable character key.
    case character(Character)
    /// The Enter key.
    case enter
    /// The Escape key.
    case escape
    /// The Tab key.
    case tab
    /// The Backspace key.
    case backspace
    /// The forward Delete key.
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

/// A key and modifier combination.
public struct KeyboardShortcut: Sendable, Hashable {
    /// The primary key.
    public var key: KeyboardKey
    /// The required modifiers.
    public var modifiers: KeyboardModifiers

    /// Creates a keyboard shortcut.
    public init(_ key: KeyboardKey, modifiers: KeyboardModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// A normalized display description of the shortcut.
    /// - Complexity: O(1).
    public var normalizedDescription: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(key.description)
        return parts.joined(separator: "+")
    }
}

extension KeyboardKey: CustomStringConvertible {
    /// A display description of the key.
    public var description: String {
        switch self {
        case .character(let character): String(character).uppercased()
        case .enter: "Enter"
        case .escape: "Esc"
        case .tab: "Tab"
        case .backspace: "Backspace"
        case .delete: "Delete"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "PageUp"
        case .pageDown: "PageDown"
        case .function(let number): "F\(number)"
        }
    }
}

extension TerminalKeyEvent {
    var keyboardShortcut: KeyboardShortcut? {
        let mappedKey: KeyboardKey? =
            switch key {
            case .text(let text) where text.count == 1: text.first.map(KeyboardKey.character)
            case .enter: .enter
            case .escape: .escape
            case .tab: .tab
            case .backspace: .backspace
            case .delete: .delete
            case .up: .up
            case .down: .down
            case .left: .left
            case .right: .right
            case .home: .home
            case .end: .end
            case .pageUp: .pageUp
            case .pageDown: .pageDown
            case .function(let number): .function(number)
            default: nil
            }
        guard let mappedKey else { return nil }
        var mappedModifiers: KeyboardModifiers = []
        if modifiers.contains(.control) { mappedModifiers.insert(.control) }
        if modifiers.contains(.alt) { mappedModifiers.insert(.option) }
        if modifiers.contains(.shift) { mappedModifiers.insert(.shift) }
        if modifiers.contains(.super) { mappedModifiers.insert(.command) }
        return KeyboardShortcut(mappedKey, modifiers: mappedModifiers)
    }
}

/// An action bound to a keyboard shortcut.
public struct KeyboardCommand: Sendable {
    /// The command identifier.
    public var id: String
    /// The display title.
    public var title: String
    /// The triggering shortcut.
    public var shortcut: KeyboardShortcut
    /// A value that indicates whether the command can run.
    public var isEnabled: Bool
    /// The command action.
    public var action: @MainActor @Sendable () -> Void

    /// Creates a keyboard command.
    public init(
        id: String,
        title: String,
        shortcut: KeyboardShortcut,
        isEnabled: Bool = true,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        precondition(id.isEmpty == false, "A keyboard command identifier must not be empty.")
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.action = action
    }

    /// Runs the command when enabled.
    /// - Complexity: O(1), excluding the action.
    @MainActor
    @discardableResult
    public func perform() -> Bool {
        guard isEnabled else { return false }
        action()
        return true
    }
}

/// An ordered collection of keyboard commands.
@MainActor
public final class KeyboardCommandSet {
    /// The commands in dispatch order.
    public var commands: [KeyboardCommand]

    /// Creates a command set.
    public init(_ commands: [KeyboardCommand] = []) {
        self.commands = commands
    }

    /// Dispatches a shortcut to the last matching enabled command.
    /// - Complexity: O(n), where n is the command count.
    @discardableResult
    public func dispatch(_ shortcut: KeyboardShortcut) -> String? {
        guard let command = commands.last(where: { $0.shortcut == shortcut && $0.isEnabled }) else { return nil }
        command.action()
        return command.id
    }
}

/// A physical mouse button.
public enum MouseButton: Sendable, Hashable {
    /// The primary mouse button.
    case primary
    /// The secondary mouse button.
    case secondary
    /// The middle mouse button.
    case middle
}

/// An action reported by a mouse input event.
public enum MouseAction: Sendable, Hashable {
    /// A button press.
    case press(MouseButton)
    /// A button release.
    case release(MouseButton)
    /// A single click.
    case click(MouseButton)
    /// A double click.
    case doubleClick(MouseButton)
    /// Pointer movement.
    case move
    /// Vertical scrolling by a line count.
    case scroll(lines: Int)
}

/// A mouse action with its location and modifiers.
public struct MouseEvent: Sendable, Hashable {
    /// The event location in cells.
    public var location: CellPoint
    /// The mouse action.
    public var action: MouseAction
    /// The held keyboard modifiers.
    public var modifiers: KeyboardModifiers

    /// Creates a mouse event.
    public init(location: CellPoint, action: MouseAction, modifiers: KeyboardModifiers = []) {
        self.location = location
        self.action = action
        self.modifiers = modifiers
    }
}

/// A rectangular mouse target and its event handler.
public struct MouseHitRegion: Sendable {
    /// The region identifier.
    public var id: String
    /// The hit-test rectangle.
    public var frame: CellRect
    /// The stacking priority.
    public var zIndex: Int
    /// A value that indicates whether the region accepts events.
    public var isEnabled: Bool
    /// The event handler.
    public var handler: @MainActor @Sendable (_ event: MouseEvent) -> Bool

    /// Creates a mouse hit region.
    public init(
        id: String,
        frame: CellRect,
        zIndex: Int = 0,
        isEnabled: Bool = true,
        handler: @escaping @MainActor @Sendable (_ event: MouseEvent) -> Bool
    ) {
        self.id = id
        self.frame = frame
        self.zIndex = zIndex
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

/// Dispatches mouse events by stacking and registration order.
@MainActor
public struct MouseDispatcher {
    /// The registered hit regions.
    public var regions: [MouseHitRegion]

    /// Creates a mouse dispatcher.
    public init(regions: [MouseHitRegion] = []) {
        self.regions = regions
    }

    /// Dispatches an event and returns the handling region identifier.
    /// - Complexity: O(n log n), where n is the region count.
    @discardableResult
    public func dispatch(_ event: MouseEvent) -> String? {
        let candidates = regions.enumerated()
            .filter { $0.element.isEnabled && $0.element.frame.contains(event.location) }
            .sorted {
                if $0.element.zIndex != $1.element.zIndex {
                    return $0.element.zIndex > $1.element.zIndex
                }
                return $0.offset > $1.offset
            }
        for candidate in candidates where candidate.element.handler(event) {
            return candidate.element.id
        }
        return nil
    }
}
