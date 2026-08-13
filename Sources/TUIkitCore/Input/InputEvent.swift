//  TUIkit - Terminal UI Kit for Swift
//  InputEvent.swift
//
//  License: MIT

/// An input event from a terminal.
public enum InputEvent: Equatable, Sendable {
  /// A keyboard event.
  case key(KeyEvent)

  /// A mouse event.
  case mouse(MouseEvent)
}

/// A mouse event at a terminal cell.
public struct MouseEvent: Equatable, Sendable {
  /// The mouse action.
  public enum Action: Equatable, Sendable {
    /// A mouse button press.
    case press(Button)

    /// A mouse button release.
    case release(Button)

    /// Pointer movement while a button is pressed.
    case drag(Button)

    /// Pointer movement without a pressed button.
    case move

    /// A scroll-wheel action.
    case scroll(ScrollDirection)
  }

  /// A mouse button.
  public enum Button: Equatable, Sendable {
    case left
    case middle
    case right
  }

  /// A scroll-wheel direction.
  public enum ScrollDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
  }

  /// The mouse action.
  public let action: Action

  /// The zero-based terminal cell column.
  public let column: Int

  /// The zero-based terminal cell row.
  public let row: Int

  /// Whether the Ctrl modifier was held.
  public let ctrl: Bool

  /// Whether the Alt or Option modifier was held.
  public let alt: Bool

  /// Whether the Shift modifier was held.
  public let shift: Bool

  /// Creates a mouse event.
  public init(
    action: Action,
    column: Int,
    row: Int,
    ctrl: Bool = false,
    alt: Bool = false,
    shift: Bool = false
  ) {
    self.action = action
    self.column = column
    self.row = row
    self.ctrl = ctrl
    self.alt = alt
    self.shift = shift
  }
}
