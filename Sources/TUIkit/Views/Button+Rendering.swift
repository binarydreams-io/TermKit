//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Button+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension Button {
  public var body: some View {
    _ButtonCore(
      label: label,
      action: action,
      role: role,
      style: style,
      focusedStyle: focusedStyle,
      focusID: focusID,
      isDisabled: isDisabled
    )
  }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of Button.
private struct _ButtonCore: View, Renderable {
  let label: String
  let action: () -> Void
  let role: ButtonRole?
  let style: ButtonStyle
  let focusedStyle: ButtonStyle
  let focusID: String?
  let isDisabled: Bool

  var body: Never {
    fatalError("_ButtonCore renders via Renderable")
  }

  private enum StateIndex {
    static let focusID = 0
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let persistedFocusID = FocusRegistration.persistFocusID(
      context: context,
      explicitFocusID: focusID,
      defaultPrefix: "button",
      propertyIndex: StateIndex.focusID
    )
    let handler = ActionHandler(
      focusID: persistedFocusID,
      action: action,
      canBeFocused: !isDisabled
    )
    FocusRegistration.register(context: context, handler: handler)
    let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
    let currentStyle = isFocused ? focusedStyle : style
    let palette = context.environment.palette
    let isPlainStyle = currentStyle.horizontalPadding == 0 && style.foregroundColor == nil && !style.isBold

    // Build the label with padding
    let padding = String(repeating: " ", count: currentStyle.horizontalPadding)
    let paddedLabel = padding + label + padding

    // Resolve foreground color
    let foregroundColor: Color = if isDisabled {
      // Use tertiary at 50% opacity for clearly disabled appearance
      palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    } else {
      currentStyle.foregroundColor?.resolve(with: palette) ?? palette.accent
    }

    // Build text style
    var textStyle = TextStyle()
    textStyle.foregroundColor = foregroundColor
    textStyle.isBold = currentStyle.isBold && !isDisabled

    // Determine rendering mode
    let buffer: FrameBuffer
    if isPlainStyle {
      // Plain: pulsing dot prefix + label, no brackets
      let focusPrefix = BorderRenderer.focusIndicatorPrefix(
        isFocused: isFocused && !isDisabled,
        pulsePhase: context.environment.pulsePhase,
        palette: palette
      )
      let styledLabel = ANSIRenderer.render(paddedLabel, with: textStyle)
      let fullLine = focusPrefix + styledLabel
      buffer = FrameBuffer(lines: [fullLine])
    } else {
      // Standard: half-block caps with accent-tinted background
      let buttonBg = palette.accent.opacity(ViewConstants.focusBorderDim)

      // Label foreground: primary = accent/highlight, others = dimmed foreground
      let labelFg: Color = if isDisabled {
        palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
      } else if currentStyle.isBold {
        currentStyle.foregroundColor?.resolve(with: palette) ?? palette.accent
      } else {
        palette.foregroundSecondary
      }

      // Caps: match button background normally, pulse to accent when focused
      let resolvedCapColor: Color = if isDisabled {
        buttonBg
      } else if isFocused {
        Color.lerp(
          buttonBg,
          palette.accent.opacity(ViewConstants.buttonCapPulseBright),
          phase: context.environment.pulsePhase
        )
      } else {
        buttonBg
      }

      let openCap = ANSIRenderer.colorize(String(TerminalSymbols.openCap), foreground: resolvedCapColor)
      let closeCap = ANSIRenderer.colorize(String(TerminalSymbols.closeCap), foreground: resolvedCapColor)
      let styledLabel = ANSIRenderer.colorize(
        paddedLabel,
        foreground: labelFg,
        background: buttonBg,
        bold: currentStyle.isBold && !isDisabled
      )

      let line = openCap + styledLabel + closeCap
      buffer = FrameBuffer(lines: [line])
    }

    guard !isDisabled,
          !context.isMeasuring,
          let interactionDispatcher = context.environment.interactionDispatcher
    else {
      return buffer
    }

    let interactionID = "button-interaction-\(persistedFocusID)"
    let focusManager = context.environment.focusManager
    interactionDispatcher.registerClick(id: interactionID) {
      focusManager.focus(id: persistedFocusID)
      action()
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
