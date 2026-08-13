//  TUIKit - Terminal UI Kit for Swift
//  SecureField.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - SecureField

/// A control for secure text entry, where the display masks the user's input.
///
/// Use `SecureField` when you need to collect sensitive data like passwords.
/// The field behaves identically to `TextField` but displays bullet characters
/// (●) instead of the actual text.
///
/// ## Rendering
///
/// The secure field renders masked text with a visible cursor when focused.
/// When empty and unfocused, it displays the prompt text in dim styling.
///
/// ```
/// Unfocused, empty:     Enter password...       (prompt in dim)
/// Unfocused, with text: ●●●●●●●●                (bullets)
/// Focused, empty:       ❙ █                   ❙ (cursor, bars pulse)
/// Focused, with text:   ❙ ●●●●█●●●            ❙ (bullets + cursor)
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
/// @State var password = ""
///
/// SecureField("Password", text: $password)
/// ```
///
/// # With Prompt
///
/// ```swift
/// SecureField("Password", text: $password, prompt: Text("Required"))
/// ```
///
/// # With Submit Action
///
/// ```swift
/// SecureField("Password", text: $password)
///     .onSubmit {
///         authenticate()
///     }
/// ```
public struct SecureField<Label: View>: View {
  /// The label view describing the field's purpose.
  let label: Label

  /// The binding to the text content.
  let text: Binding<String>

  /// Optional prompt text shown when the field is empty.
  let prompt: Text?

  /// The unique focus identifier.
  var focusID: String?

  /// Whether the secure field is disabled.
  var isDisabled: Bool

  /// Action to perform when the user submits (presses Enter).
  var onSubmitAction: (() -> Void)?

  public var body: some View {
    _SecureFieldCore(
      text: text,
      prompt: prompt,
      focusID: focusID,
      isDisabled: isDisabled,
      onSubmitAction: onSubmitAction
    )
  }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of SecureField.
private struct _SecureFieldCore: View, Renderable, Layoutable {
  let text: Binding<String>
  let prompt: Text?
  let focusID: String?
  let isDisabled: Bool
  let onSubmitAction: (() -> Void)?

  /// Minimum width for the secure field content area.
  private let minContentWidth = 10

  /// Default visible width for the secure field content area when no proposal is given.
  private let defaultContentWidth = 20

  var body: Never {
    fatalError("_SecureFieldCore renders via Renderable")
  }

  /// Returns the size this secure field needs.
  ///
  /// SecureField is width-flexible: it has a minimum width but expands
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

    // SecureField expands to fill available width (reserve 2 chars for caps)
    let contentWidth = max(minContentWidth, context.availableWidth - 2)

    let persistedFocusID = FocusRegistration.persistFocusID(
      context: context,
      explicitFocusID: focusID,
      defaultPrefix: "securefield",
      propertyIndex: 1 // focusID
    )

    // Get or create persistent handler from state storage.
    // Reuses TextFieldHandler since key handling is identical.
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

    // Build the secure field content using shared renderer
    let renderer = TextFieldContentRenderer(
      prompt: prompt,
      isDisabled: isDisabled,
      displayCharacter: { _, _ in TerminalSymbols.maskBullet }
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
