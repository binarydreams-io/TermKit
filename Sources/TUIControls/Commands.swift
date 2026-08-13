import TUIFoundation

public struct KeyboardModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = KeyboardModifiers(rawValue: 1 << 0)
    public static let option = KeyboardModifiers(rawValue: 1 << 1)
    public static let shift = KeyboardModifiers(rawValue: 1 << 2)
    public static let command = KeyboardModifiers(rawValue: 1 << 3)
}

public enum KeyboardKey: Sendable, Hashable {
    case character(Character)
    case enter
    case escape
    case tab
    case backspace
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

public struct KeyboardShortcut: Sendable, Hashable {
    public var key: KeyboardKey
    public var modifiers: KeyboardModifiers

    public init(_ key: KeyboardKey, modifiers: KeyboardModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

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

public struct KeyboardCommand: Sendable {
    public var id: String
    public var title: String
    public var shortcut: KeyboardShortcut
    public var isEnabled: Bool
    public var action: @MainActor @Sendable () -> Void

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

    @MainActor
    @discardableResult
    public func perform() -> Bool {
        guard isEnabled else { return false }
        action()
        return true
    }
}

@MainActor
public final class KeyboardCommandSet {
    public var commands: [KeyboardCommand]

    public init(_ commands: [KeyboardCommand] = []) {
        self.commands = commands
    }

    @discardableResult
    public func dispatch(_ shortcut: KeyboardShortcut) -> String? {
        guard let command = commands.last(where: { $0.shortcut == shortcut && $0.isEnabled }) else { return nil }
        command.action()
        return command.id
    }
}

public enum MouseButton: Sendable, Hashable {
    case primary
    case secondary
    case middle
}

public enum MouseAction: Sendable, Hashable {
    case press(MouseButton)
    case release(MouseButton)
    case click(MouseButton)
    case doubleClick(MouseButton)
    case move
    case scroll(lines: Int)
}

public struct MouseEvent: Sendable, Hashable {
    public var location: CellPoint
    public var action: MouseAction
    public var modifiers: KeyboardModifiers

    public init(location: CellPoint, action: MouseAction, modifiers: KeyboardModifiers = []) {
        self.location = location
        self.action = action
        self.modifiers = modifiers
    }
}

public struct MouseHitRegion: Sendable {
    public var id: String
    public var frame: CellRect
    public var zIndex: Int
    public var isEnabled: Bool
    public var handler: @MainActor @Sendable (MouseEvent) -> Bool

    public init(
        id: String,
        frame: CellRect,
        zIndex: Int = 0,
        isEnabled: Bool = true,
        handler: @escaping @MainActor @Sendable (MouseEvent) -> Bool
    ) {
        self.id = id
        self.frame = frame
        self.zIndex = zIndex
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

@MainActor
public struct MouseDispatcher {
    public var regions: [MouseHitRegion]

    public init(regions: [MouseHitRegion] = []) {
        self.regions = regions
    }

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
