//  TUIKit - Terminal UI Kit for Swift
//  SecureField+API.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - SecureField Initializers (String Label)

extension SecureField where Label == Text {
  /// Creates a secure field with a text label generated from a title string.
  ///
  /// - Parameters:
  ///   - title: The title of the secure field, describing its purpose.
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

  /// Creates a secure field with a prompt.
  ///
  /// - Parameters:
  ///   - title: The title of the secure field, describing its purpose.
  ///   - text: The text to display and edit.
  ///   - prompt: A Text representing the prompt which provides users with
  ///     guidance on what to type into the secure field.
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

// MARK: - SecureField Initializers (ViewBuilder Label)

extension SecureField {
  /// Creates a secure field with a custom label.
  ///
  /// Use this initializer when you need a custom label view instead of a simple string.
  ///
  /// # Example
  ///
  /// ```swift
  /// SecureField(text: $password, prompt: Text("Required")) {
  ///     HStack {
  ///         Text("Password").bold()
  ///         Text("*").foregroundStyle(.red)
  ///     }
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - text: The text to display and edit.
  ///   - prompt: A Text representing the prompt which provides users with
  ///     guidance on what to type into the secure field.
  ///   - label: A view that describes the purpose of the secure field.
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

// MARK: - SecureField Modifiers

extension SecureField {
  /// Creates a disabled version of this secure field.
  ///
  /// - Parameter disabled: Whether the secure field is disabled.
  /// - Returns: A new secure field with the disabled state.
  public func disabled(_ disabled: Bool = true) -> SecureField {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }

  /// Adds an action to perform when the user submits (presses Enter).
  ///
  /// Use this modifier to invoke an action when the user presses Enter
  /// while the secure field has focus.
  ///
  /// # Example
  ///
  /// ```swift
  /// SecureField("Password", text: $password)
  ///     .onSubmit {
  ///         authenticate()
  ///     }
  /// ```
  ///
  /// - Parameter action: The action to perform on submit.
  /// - Returns: A secure field that performs the action on submit.
  public func onSubmit(_ action: @escaping () -> Void) -> SecureField {
    var copy = self
    copy.onSubmitAction = action
    return copy
  }

  /// Sets a custom focus identifier for this secure field.
  ///
  /// - Parameter id: The unique focus identifier.
  /// - Returns: A secure field with the specified focus identifier.
  public func focusID(_ id: String) -> SecureField {
    var copy = self
    copy.focusID = id
    return copy
  }
}
