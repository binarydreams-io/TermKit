//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarState+DerivedValues.swift
//
//  Created by LAYERED.work
//  License: MIT

extension StatusBarState {
  /// Whether quit is currently allowed based on `quitBehavior`.
  public var isQuitAllowed: Bool {
    switch quitBehavior {
    case .always: true
    case .rootOnly: isAtRoot
    }
  }

  /// The current system items based on configuration flags.
  public var currentSystemItems: [StatusBarItem] {
    guard showSystemItems else { return [] }

    var items: [StatusBarItem] = []
    if isQuitAllowed {
      items.append(StatusBarItem(
        shortcut: quitShortcut.shortcutSymbol,
        label: quitShortcut.label,
        order: .quit
      ))
    }
    if showAppearanceItem {
      items.append(SystemStatusBarItem.appearance)
    }
    if showThemeItem {
      items.append(SystemStatusBarItem.theme)
    }
    return items
  }

  /// All currently active items for rendering and event handling.
  public var currentItems: [any StatusBarItemProtocol] {
    let userShortcuts = Set(currentUserItems.map(\.shortcut))
    let filteredSystemItems = currentSystemItems.filter { !userShortcuts.contains($0.shortcut) }
    let sortedUserItems = currentUserItems.sorted { $0.order < $1.order }
    return sortedUserItems + filteredSystemItems
  }

  /// Whether the status bar has any items to display.
  public var hasItems: Bool {
    !currentItems.isEmpty
  }

  /// Whether there are any user items (ignoring system items).
  public var hasUserItems: Bool {
    !currentUserItems.isEmpty
  }

  /// The height of the status bar in lines.
  public var height: Int {
    guard hasItems else { return 0 }
    switch style {
    case .compact: return 1
    case .bordered: return 3
    }
  }
}
