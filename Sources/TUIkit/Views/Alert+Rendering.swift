//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alert+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Alert Core Rendering

/// Internal view that handles Alert rendering.
///
/// This separation ensures `Alert.body` returns a real `View`, allowing
/// environment modifiers like `.foregroundStyle()` to propagate correctly.
struct _AlertCore<Actions: View>: View, Renderable {
  let title: String
  let message: String
  let config: ContainerConfig
  let actions: Actions

  var body: Never {
    fatalError("_AlertCore renders via Renderable")
  }

  /// Maximum width for alerts (characters).
  private static var maxWidth: Int {
    60
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    // Limit alert width
    var alertContext = context
    alertContext.availableWidth = min(context.availableWidth, Self.maxWidth)

    // Extract buttons from actions and create horizontal layout
    let buttons = extractButtons(from: actions)
    let hasActions = !buttons.isEmpty

    let footerView: AlertButtonRow? = hasActions ? AlertButtonRow(buttons: buttons) : nil

    return renderContainer(
      title: title,
      config: config,
      content: Text(message),
      footer: footerView,
      context: alertContext
    )
  }

  /// Extracts Button instances from a view hierarchy using the `ButtonProvider` protocol.
  private func extractButtons(from view: some View) -> [Button] {
    if let provider = view as? ButtonProvider {
      return provider.extractButtons()
    }
    return []
  }
}

// MARK: - Alert Button Row

/// Internal view that renders buttons horizontally for alerts.
struct AlertButtonRow: View, Renderable {
  let buttons: [Button]

  var body: Never {
    fatalError("AlertButtonRow renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    guard !buttons.isEmpty else {
      return FrameBuffer(lines: [])
    }

    // Sort buttons: cancel on left, others on right
    let sortedButtons = buttons.sorted { lhs, rhs in
      let lhsIsCancel = lhs.role == .cancel
      let rhsIsCancel = rhs.role == .cancel
      if lhsIsCancel != rhsIsCancel {
        return lhsIsCancel // Cancel comes first (left)
      }
      return false // Keep original order otherwise
    }

    // Render each button
    var buttonBuffers: [FrameBuffer] = []
    for (index, button) in sortedButtons.enumerated() {
      let buttonContext = context.withChildIdentity(type: Button.self, index: index)
      let buffer = TUIkit.renderToBuffer(button, context: buttonContext)
      buttonBuffers.append(buffer)
    }

    // Find the maximum height
    let maxHeight = buttonBuffers.map(\.height).max() ?? 0

    // Calculate total width needed (buttons + spacing)
    let spacing = 1
    let totalButtonWidth = buttonBuffers.reduce(0) { $0 + $1.width }
    let totalSpacingWidth = max(0, buttonBuffers.count - 1) * spacing
    let totalNeededWidth = totalButtonWidth + totalSpacingWidth

    // Available width from context
    let availableWidth = context.availableWidth

    // Right-align: calculate left padding
    let leftPadding = max(0, availableWidth - totalNeededWidth)

    // Combine horizontally (right-aligned)
    var resultLines: [String] = Array(repeating: "", count: maxHeight)
    var regions: [InteractionRegion] = []
    let spacer = String(repeating: " ", count: spacing)
    var horizontalOffset = leftPadding

    for (index, buffer) in buttonBuffers.enumerated() {
      if index > 0 {
        horizontalOffset += spacing
      }
      regions.append(contentsOf: buffer.regions.map {
        InteractionRegion(
          id: $0.id,
          rect: $0.rect.translatedBy(x: horizontalOffset, y: 0)
        )
      })
      horizontalOffset += buffer.width
    }

    for lineIndex in 0 ..< maxHeight {
      // Add left padding
      resultLines[lineIndex] = String(repeating: " ", count: leftPadding)

      // Add buttons
      for (index, buffer) in buttonBuffers.enumerated() {
        let buttonWidth = buffer.width

        if index > 0 {
          resultLines[lineIndex] += spacer
        }

        if lineIndex < buffer.height {
          resultLines[lineIndex] += buffer.lines[lineIndex]
        } else {
          resultLines[lineIndex] += String(repeating: " ", count: buttonWidth)
        }
      }
    }

    return FrameBuffer(lines: resultLines, regions: regions)
  }
}
