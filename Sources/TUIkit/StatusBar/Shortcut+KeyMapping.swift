//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Shortcut+KeyMapping.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Shortcut Key Mapping

/// Derives the ``Key`` that triggers a shortcut's display text.
///
/// Shared by ``StatusBarItem`` and ``KeyBinding`` so their derivation rules
/// cannot drift apart. Checks, in order: named special keys (escape, enter,
/// tab, backspace, delete, space — both their ``Shortcut`` symbol and common
/// word spellings), arrow/navigation keys, function keys, then falls back to
/// a single character. A shortcut that matches none of these (e.g. the
/// multi-character `"↑↓"`) has no derived key.
///
/// - Parameter shortcut: The shortcut's display text.
/// - Returns: The key that triggers it, or `nil` if none can be derived.
func keyFromShortcutText(_ shortcut: String) -> Key? {
  specialKeyFromShortcutText(shortcut)
    ?? navigationKeyFromShortcutText(shortcut)
    ?? functionKeyFromShortcutText(shortcut)
    ?? (shortcut.count == 1 ? shortcut.first.map(Key.character) : nil)
}

/// Maps special-key shortcut symbols and word spellings to ``Key`` values.
private func specialKeyFromShortcutText(_ shortcut: String) -> Key? {
  switch shortcut {
  case Shortcut.escape, "esc", "escape":
    .escape
  case Shortcut.enter, Shortcut.returnKey, "enter", "return":
    .enter
  case Shortcut.tab, "tab":
    .tab
  case Shortcut.backspace, "backspace", "del":
    .backspace
  case Shortcut.delete:
    .delete
  case Shortcut.space, "space":
    .space
  default:
    nil
  }
}

/// Maps arrow and navigation shortcut symbols to ``Key`` values.
private func navigationKeyFromShortcutText(_ shortcut: String) -> Key? {
  switch shortcut {
  case Shortcut.arrowUp:
    .up
  case Shortcut.arrowDown:
    .down
  case Shortcut.arrowLeft:
    .left
  case Shortcut.arrowRight:
    .right
  case Shortcut.home:
    .home
  case Shortcut.end:
    .end
  case Shortcut.pageUp:
    .pageUp
  case Shortcut.pageDown:
    .pageDown
  default:
    nil
  }
}

/// Maps function-key shortcut symbols to ``Key`` values.
private func functionKeyFromShortcutText(_ shortcut: String) -> Key? {
  switch shortcut {
  case Shortcut.f1: .f1
  case Shortcut.f2: .f2
  case Shortcut.f3: .f3
  case Shortcut.f4: .f4
  case Shortcut.f5: .f5
  case Shortcut.f6: .f6
  case Shortcut.f7: .f7
  case Shortcut.f8: .f8
  case Shortcut.f9: .f9
  case Shortcut.f10: .f10
  case Shortcut.f11: .f11
  case Shortcut.f12: .f12
  default: nil
  }
}
