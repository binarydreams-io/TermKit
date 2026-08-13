//  TUIKit - Terminal UI Kit for Swift
//  Toggle+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension Toggle {
  public var body: some View {
    _ToggleCore(
      isOn: isOn,
      label: label,
      focusID: focusID,
      isDisabled: isDisabled
    )
  }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of Toggle.
private struct _ToggleCore<Label: View>: View, Renderable {
  let isOn: Binding<Bool>
  let label: Label
  let focusID: String?
  let isDisabled: Bool

  var body: Never {
    fatalError("_ToggleCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let palette = context.environment.palette

    let persistedFocusID = FocusRegistration.persistFocusID(
      context: context,
      explicitFocusID: focusID,
      defaultPrefix: "toggle",
      propertyIndex: 0 // focusID
    )
    let binding = isOn
    let handler = ActionHandler(
      focusID: persistedFocusID,
      action: { binding.wrappedValue.toggle() },
      canBeFocused: !isDisabled
    )
    FocusRegistration.register(context: context, handler: handler)
    let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
    let isOnValue = isOn.wrappedValue

    // Render the label to get its text
    let labelBuffer = TUIkit.renderToBuffer(label, context: context)
    let labelText = labelBuffer.lines.joined(separator: " ").stripped

    // Bracket color: pulsing accent when focused, dimmed otherwise
    let bracketColor: Color
    if isDisabled {
      bracketColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    } else if isFocused {
      let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
      bracketColor = Color.lerp(dimAccent, palette.accent, phase: context.environment.pulsePhase)
    } else {
      bracketColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    }

    let openBracket = ANSIRenderer.colorize("[", foreground: bracketColor)
    let closeBracket = ANSIRenderer.colorize("]", foreground: bracketColor)

    // Content: [ ] (OFF) or [x] (ON)
    let contentColor: Color = if isDisabled {
      palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    } else if isOnValue {
      palette.accent
    } else {
      palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    }

    let content = isOnValue ? "x" : " "
    let styledContent = ANSIRenderer.colorize(content, foreground: contentColor)
    let styledIndicator = openBracket + styledContent + closeBracket

    // Combine: [indicator] label
    let combinedLine = styledIndicator + " " + labelText

    let buffer = FrameBuffer(lines: [combinedLine])
    guard !isDisabled,
          !context.isMeasuring,
          let interactionDispatcher = context.environment.interactionDispatcher
    else {
      return buffer
    }

    let interactionID = "toggle-interaction-\(persistedFocusID)"
    let focusManager = context.environment.focusManager
    interactionDispatcher.registerClick(id: interactionID) {
      focusManager.focus(id: persistedFocusID)
      binding.wrappedValue.toggle()
    }

    var interactiveBuffer = buffer
    interactiveBuffer.regions.append(
      InteractionRegion(
        id: interactionID,
        rect: TerminalCellRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
      )
    )
    return interactiveBuffer
  }
}
