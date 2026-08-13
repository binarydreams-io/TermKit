//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Events.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Press

extension View {
  /// Adds a handler for key press events.
  ///
  /// The handler is called when any key is pressed while this view
  /// is in the view hierarchy. Return `true` to consume the event,
  /// or `false` to let it propagate to other handlers.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text("Press any key")
  ///     .onKeyPress { event in
  ///         if event.key == .enter {
  ///             doSomething()
  ///             return true  // Consumed
  ///         }
  ///         return false  // Let others handle it
  ///     }
  /// ```
  ///
  /// - Parameter handler: The handler to call on key press. Returns true if handled.
  /// - Returns: A view that handles key presses.
  public func onKeyPress(_ handler: @escaping (KeyEvent) -> Bool) -> some View {
    KeyPressModifier(content: self, keys: nil, handler: handler)
  }

  /// Adds a handler for specific key press events.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text("Use arrow keys")
  ///     .onKeyPress(keys: [.up, .down]) { event in
  ///         if event.key == .up {
  ///             moveUp()
  ///         } else {
  ///             moveDown()
  ///         }
  ///         return true
  ///     }
  /// ```
  ///
  /// - Parameters:
  ///   - keys: The keys to listen for.
  ///   - handler: The handler to call on key press. Returns true if handled.
  /// - Returns: A view that handles specific key presses.
  public func onKeyPress(keys: Set<Key>, handler: @escaping (KeyEvent) -> Bool) -> some View {
    KeyPressModifier(content: self, keys: keys, handler: handler)
  }

  /// Adds a handler for a single key press.
  ///
  /// This handler always consumes the event when the specified key is pressed.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text("Press Enter to continue")
  ///     .onKeyPress(.enter) {
  ///         continueAction()
  ///     }
  /// ```
  ///
  /// - Parameters:
  ///   - key: The key to listen for.
  ///   - action: The action to perform.
  /// - Returns: A view that handles the specific key press.
  public func onKeyPress(_ key: Key, action: @escaping () -> Void) -> some View {
    KeyPressModifier(
      content: self,
      keys: [key],
      handler: { _ in
        action()
        return true
      }
    )
  }
}

// MARK: - Mouse Interaction

extension View {
  /// Runs an action after a left-button press and release on this view.
  ///
  /// The press and release must resolve to the same topmost interaction region.
  public func onClick(_ action: @escaping () -> Void) -> some View {
    MouseInteractionModifier(content: self, click: .action(action), scroll: nil)
  }

  /// Sends a key through the normal input pipeline after a click.
  ///
  /// The normal status bar, view, focus, and default-key guards apply.
  public func onClick(key: Key) -> some View {
    MouseInteractionModifier(content: self, click: .key(key), scroll: nil)
  }

  /// Runs an action when the pointer scrolls inside this view's rendered bounds.
  public func onScroll(
    _ action: @escaping (MouseEvent.ScrollDirection) -> Void
  ) -> some View {
    MouseInteractionModifier(content: self, click: nil, scroll: action)
  }
}

// MARK: - Value Change

extension View {
  /// Adds an action to perform when the given value changes.
  ///
  /// The action receives both the old and new values. Use this to react
  /// to state changes, for example to validate input or trigger side effects.
  ///
  /// # Example
  ///
  /// ```swift
  /// struct ContentView: View {
  ///     @State var selection = 0
  ///
  ///     var body: some View {
  ///         List(selection: $selection) { ... }
  ///             .onChange(of: selection) { oldValue, newValue in
  ///                 loadDetails(for: newValue)
  ///             }
  ///     }
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - value: The value to observe for changes.
  ///   - initial: Whether to call the action on the first render pass.
  ///     When `true`, the action fires immediately with `oldValue == newValue`.
  ///     Defaults to `false`.
  ///   - action: The action to perform when the value changes, receiving
  ///     the old and new values.
  /// - Returns: A view that triggers an action on value changes.
  public func onChange<V: Equatable>(
    of value: V,
    initial: Bool = false,
    _ action: @escaping (V, V) -> Void
  ) -> some View {
    OnChangeModifier(content: self, value: value, initial: initial, action: action)
  }

  /// Adds an action to perform when the given value changes.
  ///
  /// This variant does not receive the old or new values. Use it when
  /// you only need to know that a change occurred.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text("Count: \(count)")
  ///     .onChange(of: count) {
  ///         playSound()
  ///     }
  /// ```
  ///
  /// - Parameters:
  ///   - value: The value to observe for changes.
  ///   - initial: Whether to call the action on the first render pass.
  ///     Defaults to `false`.
  ///   - action: The action to perform when the value changes.
  /// - Returns: A view that triggers an action on value changes.
  public func onChange(
    of value: some Equatable,
    initial: Bool = false,
    _ action: @escaping () -> Void
  ) -> some View {
    OnChangeModifier(content: self, value: value, initial: initial) { _, _ in action() }
  }
}
