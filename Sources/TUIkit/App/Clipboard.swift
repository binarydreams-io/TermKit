//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Clipboard.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Clipboard Writing

/// A destination for text copied from the interface.
@MainActor
public protocol ClipboardWriting: AnyObject {
  /// Copies text to the clipboard.
  ///
  /// - Parameter text: The text to copy.
  func copy(_ text: String)
}

// MARK: - OSC 52 Clipboard

/// A clipboard that asks the terminal emulator to perform the copy.
///
/// The OSC 52 sequence travels over the same channel as the rendered
/// output, so the copy also works through SSH sessions and multiplexers,
/// where a local clipboard API would write on the wrong machine. Terminals
/// that do not implement OSC 52, or that disable it for security, ignore
/// the sequence, and the copy silently does nothing.
final class OSC52Clipboard: ClipboardWriting {
  /// The terminal receiving the escape sequence.
  private let terminal: any TerminalProtocol

  /// Creates a clipboard bound to a terminal.
  ///
  /// - Parameter terminal: The terminal receiving the escape sequence.
  init(terminal: any TerminalProtocol) {
    self.terminal = terminal
  }

  func copy(_ text: String) {
    let payload = Data(text.utf8).base64EncodedString()
    terminal.write("\(ANSIRenderer.escape)]52;c;\(payload)\u{07}")
  }
}

// MARK: - Detached Clipboard

/// A clipboard that drops every copy.
///
/// Used outside a running application, where no terminal can perform the
/// copy.
final class DetachedClipboard: ClipboardWriting {
  /// Creates a clipboard that drops every copy.
  ///
  /// Non-isolated so the environment can supply a default value outside
  /// the main actor.
  nonisolated init() {}

  func copy(_: String) {}
}

// MARK: - Environment Key

/// Environment key for the clipboard.
private struct ClipboardKey: EnvironmentKey {
  static var defaultValue: any ClipboardWriting { DetachedClipboard() }
}

extension EnvironmentValues {
  /// The clipboard that receives copied text.
  ///
  /// The running application injects a clipboard backed by its terminal.
  /// Read it with `@Environment(\.clipboard)` and retain it in callbacks:
  ///
  /// ```swift
  /// @Environment(\.clipboard) private var clipboard
  ///
  /// Button("Copy path") { clipboard.copy(path) }
  /// ```
  public var clipboard: any ClipboardWriting {
    get { self[ClipboardKey.self] }
    set { self[ClipboardKey.self] = newValue }
  }
}
