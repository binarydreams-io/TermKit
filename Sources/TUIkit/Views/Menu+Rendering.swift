//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Menu+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of Menu.
struct _MenuCore: View, Renderable {
  let title: String?
  let items: [MenuItem]
  let selectedIndex: Int
  let selectionBinding: Binding<Int>?
  let onSelect: ((Int) -> Void)?
  let itemColor: Color?
  let selectedColor: Color?
  let selectionIndicator: String
  let borderStyle: BorderStyle?
  let borderColor: Color?

  var body: Never {
    fatalError("_MenuCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let palette = context.environment.palette

    // Register key handlers if this is an interactive menu
    if let binding = selectionBinding {
      registerKeyHandlers(binding: binding, context: context)
    }

    var lines: [String] = []

    // Calculate the content width for full-width selection bar
    let contentWidth = maxItemWidth + 2 // +2 for padding

    // Track the divider line index (for T-junction rendering)
    var dividerLineIndex: Int?

    // Title if present
    if let menuTitle = title {
      let titleStyled = ANSIRenderer.render(
        menuTitle,
        with: {
          var style = TextStyle()
          style.isBold = true
          style.foregroundColor = selectedColor?.resolve(with: palette) ?? palette.accent
          return style
        }()
      )
      lines.append(" " + titleStyled)

      // Mark divider position - actual divider will be rendered by applyBorder
      dividerLineIndex = lines.count
      lines.append("") // Placeholder for divider
    }

    // Menu items
    let currentSelection = selectionBinding?.wrappedValue ?? selectedIndex

    for (index, item) in items.enumerated() {
      let isSelected = index == currentSelection

      // Build the label with optional shortcut
      let labelText = if let shortcut = item.shortcut {
        "[\(shortcut)] \(item.label)"
      } else {
        "    \(item.label)"
      }

      // Build the full text with padding
      let fullText = " " + labelText

      // Pad to full width for selection bar
      let visibleLength = fullText.count
      let padding = max(0, contentWidth - visibleLength)
      let paddedText = fullText + String(repeating: " ", count: padding)

      // Apply styling
      var style = TextStyle()
      if isSelected {
        // Selected: bold text with dimmed background, highlighted foreground
        style.isBold = true
        style.foregroundColor = selectedColor?.resolve(with: palette) ?? palette.accent
        // Selected items have no special background — bold + accent is enough
      } else {
        // Use palette foreground color if no custom itemColor is set
        style.foregroundColor = itemColor?.resolve(with: palette) ?? palette.foreground
      }

      let styledLine = ANSIRenderer.render(paddedText, with: style)
      lines.append(styledLine)
    }

    // Create content buffer
    var contentBuffer = FrameBuffer(lines: lines)

    // Apply border — use explicit style, or fall back to appearance default
    let effectiveBorderStyle = borderStyle ?? context.environment.appearance.borderStyle

    contentBuffer = applyBorder(
      to: contentBuffer,
      style: effectiveBorderStyle,
      color: borderColor,
      dividerLineIndex: dividerLineIndex,
      palette: palette
    )

    return contentBuffer
  }

  /// Registers key handlers for menu navigation.
  private func registerKeyHandlers(binding: Binding<Int>, context: RenderContext) {
    let itemCount = items.count
    let menuItems = items
    let selectCallback = onSelect

    context.environment.keyEventDispatcher!.addHandler { event in
      switch event.key {
      case .up:
        // Move selection up
        let current = binding.wrappedValue
        if current > 0 {
          binding.wrappedValue = current - 1
        } else {
          binding.wrappedValue = itemCount - 1 // Wrap to bottom
        }
        return true

      case .down:
        // Move selection down
        let current = binding.wrappedValue
        if current < itemCount - 1 {
          binding.wrappedValue = current + 1
        } else {
          binding.wrappedValue = 0 // Wrap to top
        }
        return true

      case .enter:
        // Select current item
        selectCallback?(binding.wrappedValue)
        return true

      case let .character(character):
        // Check for shortcut
        for (index, item) in menuItems.enumerated() {
          if let shortcut = item.shortcut,
             shortcut.lowercased() == character.lowercased()
          {
            binding.wrappedValue = index
            selectCallback?(index)
            return true
          }
        }
        return false

      default:
        return false
      }
    }
  }

  /// The maximum width of menu items (for sizing).
  private var maxItemWidth: Int {
    items.map { item -> Int in
      let shortcutPart = 4 // "[x] " or "    " — always 4 characters wide
      return shortcutPart + item.label.count
    }.max() ?? 0
  }

  /// Applies a border to the buffer.
  ///
  /// - Parameters:
  ///   - buffer: The content buffer to wrap with border.
  ///   - style: The border style to use.
  ///   - color: The border color (optional).
  ///   - dividerLineIndex: If set, renders a horizontal divider with T-junctions at this line index.
  private func applyBorder(
    to buffer: FrameBuffer,
    style: BorderStyle,
    color: Color?,
    dividerLineIndex: Int? = nil,
    palette: any Palette
  ) -> FrameBuffer {
    guard !buffer.isEmpty else { return buffer }

    let innerWidth = buffer.width
    let borderForeground = color?.resolve(with: palette) ?? palette.border
    var result: [String] = []

    result.append(BorderRenderer.standardTopBorder(style: style, innerWidth: innerWidth, color: borderForeground))

    for (index, line) in buffer.lines.enumerated() {
      if let dividerIndex = dividerLineIndex, index == dividerIndex {
        result.append(BorderRenderer.standardDivider(style: style, innerWidth: innerWidth, color: borderForeground))
      } else {
        result.append(
          BorderRenderer.standardContentLine(
            content: line,
            innerWidth: innerWidth,
            style: style,
            color: borderForeground
          )
        )
      }
    }

    result.append(BorderRenderer.standardBottomBorder(style: style, innerWidth: innerWidth, color: borderForeground))

    return FrameBuffer(lines: result)
  }
}

// MARK: - AnyView Helper
