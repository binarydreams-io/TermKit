//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyBindingCheatSheet.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Binding Cheat Sheet

/// Renders declared key bindings grouped by screen, for the full-screen
/// `?` cheat sheet.
///
/// Bindings render as plain text: a muted group title, then one row per
/// binding with its shortcut padded to the group's widest shortcut and its
/// label after two spaces. Groups appear in first-seen order; bindings
/// without an explicit group render under a "General" title.
///
/// # Example
///
/// ```swift
/// KeyBindingCheatSheet(bindings: [
///     KeyBinding(shortcut: "a", label: "Analyze", group: "Project"),
///     KeyBinding(shortcut: "g", label: "Global scope", group: "Inventory"),
/// ])
/// ```
public struct KeyBindingCheatSheet: View {
  /// The title used for bindings that declare no explicit group.
  private static let defaultGroupTitle = "General"

  /// The bindings to render, typically collected via ``KeyBindingsKey``.
  let bindings: [KeyBinding]

  /// Creates a cheat sheet for the given bindings.
  ///
  /// - Parameter bindings: The bindings to render.
  public init(bindings: [KeyBinding]) {
    self.bindings = bindings
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      for line in Self.lines(for: bindings) {
        Text(line.text)
          .foregroundStyle(line.isTitle ? .palette.foregroundTertiary : .palette.foreground)
      }
    }
  }
}

// MARK: - Line Layout

extension KeyBindingCheatSheet {
  /// A single rendered line: a group title or a padded shortcut/label row.
  fileprivate struct Line {
    let text: String
    let isTitle: Bool
  }

  /// Builds the ordered lines for every group and its bindings.
  ///
  /// Groups keep first-seen order. Each group starts with a title line,
  /// then one row per binding with its shortcut padded to that group's
  /// widest shortcut.
  fileprivate static func lines(for bindings: [KeyBinding]) -> [Line] {
    var groupOrder: [String] = []
    var seenGroups: Set<String> = []
    var rowsByGroup: [String: [KeyBinding]] = [:]

    for binding in bindings {
      if seenGroups.insert(binding.group).inserted {
        groupOrder.append(binding.group)
      }
      rowsByGroup[binding.group, default: []].append(binding)
    }

    var lines: [Line] = []
    for group in groupOrder {
      let rows = rowsByGroup[group] ?? []
      lines.append(Line(text: group.isEmpty ? defaultGroupTitle : group, isTitle: true))

      let shortcutWidth = rows.map(\.shortcut.strippedLength).max() ?? 0
      for row in rows {
        let shortcut = row.shortcut.padToVisibleWidth(shortcutWidth)
        lines.append(Line(text: "\(shortcut)  \(row.label)", isTitle: false))
      }
    }
    return lines
  }
}
