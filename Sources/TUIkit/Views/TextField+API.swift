//  TUIKit - Terminal UI Kit for Swift
//  TextField+API.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TextField Initializers (Label == Text)

extension TextField where Label == Text {
  /// Creates a text field with a text label generated from a title string.
  ///
  /// - Parameters:
  ///   - title: The title of the text field, describing its purpose.
  ///   - text: The text to display and edit.
  public init(_ title: String, text: Binding<String>) {
    self.label = Text(title)
    self.text = text
    self.prompt = nil
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false
    self.onSubmitAction = nil
  }

  /// Creates a text field with a prompt.
  ///
  /// - Parameters:
  ///   - title: The title of the text field, describing its purpose.
  ///   - text: The text to display and edit.
  ///   - prompt: A Text representing the prompt which provides users with
  ///     guidance on what to type into the text field.
  public init(_ title: String, text: Binding<String>, prompt: Text?) {
    self.label = Text(title)
    self.text = text
    self.prompt = prompt
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false
    self.onSubmitAction = nil
  }
}

// MARK: - TextField Initializers (Generic Label)

extension TextField {
  /// Creates a text field with a prompt generated from a `Text` and a custom label.
  ///
  /// Use this initializer when you need a custom label view instead of a simple string.
  ///
  /// # Example
  ///
  /// ```swift
  /// TextField(text: $username, prompt: Text("Required")) {
  ///     HStack {
  ///         Text("Username").bold()
  ///         Text("*").foregroundStyle(.red)
  ///     }
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - text: The text to display and edit.
  ///   - prompt: A Text representing the prompt which provides users with
  ///     guidance on what to type into the text field.
  ///   - label: A view that describes the purpose of the text field.
  public init(
    text: Binding<String>,
    prompt: Text? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.label = label()
    self.text = text
    self.prompt = prompt
    self.focusID = nil
    self.isDisabled = false
    self.onSubmitAction = nil
  }
}

// MARK: - TextField Modifiers

extension TextField {
  /// Creates a disabled version of this text field.
  ///
  /// - Parameter disabled: Whether the text field is disabled.
  /// - Returns: A new text field with the disabled state.
  public func disabled(_ disabled: Bool = true) -> TextField {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }

  /// Adds an action to perform when the user submits (presses Enter).
  ///
  /// Use this modifier to invoke an action when the user presses Enter
  /// while the text field has focus.
  ///
  /// # Example
  ///
  /// ```swift
  /// TextField("Search", text: $query)
  ///     .onSubmit {
  ///         performSearch()
  ///     }
  /// ```
  ///
  /// - Parameter action: The action to perform on submit.
  /// - Returns: A text field that performs the action on submit.
  public func onSubmit(_ action: @escaping () -> Void) -> TextField {
    var copy = self
    copy.onSubmitAction = action
    return copy
  }

  /// Sets a custom focus identifier for this text field.
  ///
  /// - Parameter id: The unique focus identifier.
  /// - Returns: A text field with the specified focus identifier.
  public func focusID(_ id: String) -> TextField {
    var copy = self
    copy.focusID = id
    return copy
  }
}
