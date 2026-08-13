//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CopyOnClickModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Copy On Click Modifier

/// A modifier that copies text when its content is clicked.
struct CopyOnClickModifier<Content: View>: View {
  /// The content view.
  let content: Content

  /// The text a click copies.
  let text: String

  var body: Never {
    fatalError("CopyOnClickModifier renders via Renderable")
  }
}

extension CopyOnClickModifier: Renderable {
  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let contentContext = context.withIdentityScope("copyOnClick.content")
    var buffer = TUIkit.renderToBuffer(content, context: contentContext)

    // A measurement pass renders the same content again for the real
    // frame; registering there would leave a stale, unbounded region.
    guard context.isMeasuring == false,
      buffer.width > 0,
      buffer.height > 0,
      let dispatcher = context.environment.interactionDispatcher
    else {
      return buffer
    }

    let id = "copy-on-click-\(context.identity.path)"
    let clipboard = context.environment.clipboard
    let notifications = context.environment.notificationService
    let text = text
    dispatcher.registerClick(id: id) {
      clipboard.copy(text)
      notifications.post("Copied")
    }
    // Inserted at the back (index 0), not appended: `activeRegions.reversed()`
    // in `InteractionDispatcher.topmostTarget` checks the last region first,
    // so a region appended here would sit on top of any interactive child
    // (e.g. a `Button`) that `content` already registered. A click on that
    // child must reach it, not this whole-area copy region.
    buffer.regions.insert(
      InteractionRegion(
        id: id,
        rect: TerminalCellRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
      ),
      at: 0
    )
    return buffer
  }
}

// MARK: - View Extension

extension View {
  /// Copies text when the user clicks this view.
  ///
  /// This modifier is specific to TUIkit and has no SwiftUI equivalent: the
  /// name deliberately avoids SwiftUI's `copyable(_:)`, which takes a
  /// `Transferable` payload for the system share sheet, a concept the
  /// terminal has no counterpart for.
  ///
  /// The copy goes through the terminal, so it also reaches the local
  /// clipboard from an SSH session. A short "Copied" notification confirms
  /// the copy.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text(project.path)
  ///     .copyOnClick(project.path)
  /// ```
  ///
  /// - Parameter text: The text a click copies.
  /// - Returns: A view that copies `text` when clicked.
  public func copyOnClick(_ text: String) -> some View {
    CopyOnClickModifier(content: self, text: text)
  }
}
