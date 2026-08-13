//  TUIKit - Terminal UI Kit for Swift
//  TextField.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TextField

/// A control that displays an editable text interface.
///
/// You create a text field with a label and a binding to a string value.
/// The text field updates this value continuously as the user types.
///
/// ## Rendering
///
/// The text field renders as `[ text content ]` with a visible cursor when focused.
/// When empty and unfocused, it displays the prompt text in dim styling.
///
/// ```
/// Unfocused, empty:     [ Enter username... ]    (prompt in dim)
/// Unfocused, with text: [ john.doe           ]   (text in normal)
/// Focused, empty:       [ █                  ]   (cursor, brackets pulse)
/// Focused, with text:   [ john.d█e           ]   (cursor in text)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert character at cursor |
/// | Backspace | Delete character before cursor |
/// | Delete | Delete character at cursor |
/// | Left | Move cursor left |
/// | Right | Move cursor right |
/// | Home | Move cursor to start |
/// | End | Move cursor to end |
/// | Enter | Trigger onSubmit action |
///
/// # Basic Example
///
/// ```swift
/// @State var username = ""
///
/// TextField("Username", text: $username)
/// ```
///
/// # With Prompt
///
/// ```swift
/// TextField("Email", text: $email, prompt: Text("you@example.com"))
/// ```
///
/// # With ViewBuilder Label
///
/// ```swift
/// TextField(text: $username, prompt: Text("Required")) {
///     Text("Username").bold()
/// }
/// ```
///
/// # With Submit Action
///
/// ```swift
/// TextField("Search", text: $query)
///     .onSubmit {
///         performSearch()
///     }
/// ```
public struct TextField<Label: View>: View {
  /// The label view describing the field's purpose.
  let label: Label

  /// The binding to the text content.
  let text: Binding<String>

  /// Optional prompt text shown when the field is empty.
  let prompt: Text?

  /// The unique focus identifier.
  var focusID: String?

  /// Whether the text field is disabled.
  var isDisabled: Bool

  /// Action to perform when the user submits (presses Enter).
  var onSubmitAction: (() -> Void)?

  public var body: some View {
    _TextFieldCore(
      label: label,
      text: text,
      prompt: prompt,
      focusID: focusID,
      isDisabled: isDisabled,
      onSubmitAction: onSubmitAction
    )
  }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of TextField.
private struct _TextFieldCore<Label: View>: View, Renderable, Layoutable {
  let label: Label
  let text: Binding<String>
  let prompt: Text?
  let focusID: String?
  let isDisabled: Bool
  let onSubmitAction: (() -> Void)?

  /// Minimum width for the text field content area.
  private let minContentWidth = 10

  /// Default visible width for the text field content area when no proposal is given.
  private let defaultContentWidth = 20

  var body: Never {
    fatalError("_TextFieldCore renders via Renderable")
  }

  /// Returns the size this text field needs.
  ///
  /// TextField is width-flexible: it has a minimum width but expands
  /// to fill available horizontal space in HStack.
  func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
    let width = proposal.width ?? defaultContentWidth
    return ViewSize(
      width: max(minContentWidth, width),
      height: 1,
      isWidthFlexible: true,
      isHeightFlexible: false
    )
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let stateStorage = context.environment.stateStorage!
    let palette = context.environment.palette
    let cursorStyle = context.environment.textCursorStyle

    // TextField expands to fill available width (reserve 2 chars for caps)
    let contentWidth = max(minContentWidth, context.availableWidth - 2)

    let persistedFocusID = FocusRegistration.persistFocusID(
      context: context,
      explicitFocusID: focusID,
      defaultPrefix: "textfield",
      propertyIndex: 1 // focusID
    )

    // Get or create persistent handler from state storage.
    // The handler maintains cursor position across renders.
    let handlerKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0) // handler
    let handlerBox: StateBox<TextFieldHandler> = stateStorage.storage(
      for: handlerKey,
      default: TextFieldHandler(
        focusID: persistedFocusID,
        text: text,
        canBeFocused: !isDisabled
      )
    )
    let handler = handlerBox.value

    // Keep handler in sync with current values
    handler.text = text
    handler.canBeFocused = !isDisabled
    handler.onSubmit = onSubmitAction
    handler.textContentType = context.environment.textContentType
    handler.clampCursorPosition()

    FocusRegistration.register(context: context, handler: handler)
    let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

    // Build the text field content using shared renderer
    let renderer = TextFieldContentRenderer(
      prompt: prompt,
      isDisabled: isDisabled,
      displayCharacter: { index, text in
        text[text.index(text.startIndex, offsetBy: index)]
      }
    )

    let fieldContent = renderer.buildContent(
      text: text.wrappedValue,
      cursorPosition: handler.cursorPosition,
      selectionRange: handler.selectionRange,
      isFocused: isFocused,
      palette: palette,
      cursorStyle: cursorStyle,
      cursorTimer: context.environment.cursorTimer,
      contentWidth: contentWidth
    )

    // Wrap with half-block caps
    let capColor = palette.accent.opacity(ViewConstants.focusBorderDim)
    let openCap = ANSIRenderer.colorize(String(TerminalSymbols.openCap), foreground: capColor)
    let closeCap = ANSIRenderer.colorize(String(TerminalSymbols.closeCap), foreground: capColor)
    return FrameBuffer(text: openCap + fieldContent + closeCap)
  }
}
