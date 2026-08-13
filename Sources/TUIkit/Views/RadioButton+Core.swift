//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButton+Core.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of RadioButtonGroup.
struct _RadioButtonGroupCore<Value: Hashable>: View, Renderable {
  let selection: Binding<Value>
  let items: [RadioButtonItem<Value>]
  let orientation: RadioButtonOrientation
  let focusID: String?
  let isDisabled: Bool

  var body: Never {
    fatalError("_RadioButtonGroupCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let palette = context.environment.palette
    let stateStorage = context.environment.stateStorage!

    // Create type-erased selection binding and item values
    let erasedSelection = Binding<AnyHashable>(
      get: { AnyHashable(selection.wrappedValue) },
      set: { newValue in
        if let typedValue = newValue.base as? Value {
          selection.wrappedValue = typedValue
        }
      }
    )
    let itemValues = items.map { AnyHashable($0.value) }

    let persistedFocusID = FocusRegistration.persistFocusID(
      context: context,
      explicitFocusID: focusID,
      defaultPrefix: "radio-group",
      propertyIndex: 1 // focusID
    )

    // Get or create persistent handler from state storage.
    // The handler maintains focusedIndex across renders, enabling Tab navigation.
    let handlerKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0) // handler
    let handlerBox: StateBox<RadioButtonGroupHandler> = stateStorage.storage(
      for: handlerKey,
      default: RadioButtonGroupHandler(
        focusID: persistedFocusID,
        selection: erasedSelection,
        itemValues: itemValues,
        orientation: orientation,
        canBeFocused: !isDisabled
      )
    )
    let handler = handlerBox.value

    // Keep handler in sync with current values (in case items changed)
    handler.selection = erasedSelection
    handler.itemValues = itemValues
    handler.canBeFocused = !isDisabled

    FocusRegistration.register(context: context, handler: handler)
    let groupHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

    // Render items based on orientation
    let lines: [String] = switch orientation {
    case .vertical:
      renderVertical(context: context, handler: handler, groupHasFocus: groupHasFocus, palette: palette)
    case .horizontal:
      renderHorizontal(context: context, handler: handler, groupHasFocus: groupHasFocus, palette: palette)
    }

    return FrameBuffer(lines: lines)
  }

  private func renderVertical(
    context: RenderContext,
    handler: RadioButtonGroupHandler,
    groupHasFocus: Bool,
    palette: Palette
  ) -> [String] {
    items.enumerated().map { index, item in
      renderRadioButton(
        index: index,
        item: item,
        isFocused: handler.focusedIndex == index && groupHasFocus,
        groupHasFocus: groupHasFocus,
        isSelected: selection.wrappedValue == item.value,
        context: context,
        palette: palette
      )
    }
  }

  private func renderHorizontal(
    context: RenderContext,
    handler: RadioButtonGroupHandler,
    groupHasFocus: Bool,
    palette: Palette
  ) -> [String] {
    let itemLines = items.enumerated().map { index, item in
      renderRadioButton(
        index: index,
        item: item,
        isFocused: handler.focusedIndex == index && groupHasFocus,
        groupHasFocus: groupHasFocus,
        isSelected: selection.wrappedValue == item.value,
        context: context,
        palette: palette
      )
    }

    // Join horizontally with spacing
    let spacing = "  "
    return [itemLines.joined(separator: spacing)]
  }

  private func renderRadioButton(
    index: Int,
    item: RadioButtonItem<Value>,
    isFocused: Bool,
    groupHasFocus: Bool,
    isSelected: Bool,
    context: RenderContext,
    palette: Palette
  ) -> String {
    // Radio indicator: ● if selected OR focused, ◯ if neither
    let indicator = (isSelected || isFocused) ? TerminalSymbols.radioSelected : TerminalSymbols.radioUnselected

    // Determine indicator color based on state
    let indicatorColor: Color
    if isDisabled {
      indicatorColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    } else if isFocused {
      // Focused: pulsing accent (whether selected or not)
      let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
      indicatorColor = Color.lerp(dimAccent, palette.accent, phase: context.environment.pulsePhase)
    } else if isSelected {
      // Selected but not focused: solid accent
      indicatorColor = palette.accent
    } else {
      // Unselected and unfocused: dimmed
      indicatorColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
    }

    let styledIndicator = ANSIRenderer.colorize(indicator, foreground: indicatorColor)

    // Render label with theme color
    let labelView = item.labelBuilder()
    let labelBuffer = labelView.renderToBuffer(context: context)
    let labelText = labelBuffer.lines.first ?? ""

    // Combine: indicator + label
    return styledIndicator + " " + labelText
  }
}
