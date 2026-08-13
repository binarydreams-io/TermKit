//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Focus.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Focus Manager

/// Manages focus state across the application.
///
/// The focus manager organizes interactive elements into **focus sections**.
/// Each section is a named, focusable area (e.g. a sidebar, a content panel,
/// a modal) that contains its own list of focusable elements.
///
/// - **Tab / Shift+Tab** cycles between sections.
/// - **Up/Down arrows** navigate within the active section's focusable elements.
/// - **Enter/Space** activates the focused element.
///
/// Elements registered without an explicit section go into a default section.
/// When only one section exists, Tab cycles elements within it (legacy behavior).
///
/// `FocusManager` is injected via the Environment system.
/// Each app instance gets its own `FocusManager`, ensuring test isolation.
///
/// # Usage
///
/// ```swift
/// // Access via Environment in views
/// let focusManager = context.environment.focusManager
///
/// // Register a section (done by .focusSection() modifier)
/// focusManager.registerSection(id: "playlist")
///
/// // Register a focusable element in a section
/// focusManager.register(button, inSection: "playlist")
///
/// // Move focus
/// focusManager.focusNextInSection()     // within active section
/// focusManager.focusPreviousInSection() // within active section
/// focusManager.activateNextSection()    // switch to next section
///
/// // Check focus
/// if focusManager.isFocused(button) {
///     // render focused style
/// }
/// ```
public final class FocusManager: @unchecked Sendable {
  /// The default section ID for elements registered without an explicit section.
  static let defaultSectionID = "__default__"

  /// Registered focus sections in render order.
  var sections: [FocusSection] = []

  /// The ID of the currently active section.
  var activeSectionID: String?

  /// The currently focused element's ID within the active section.
  var focusedID: String?

  /// Callback triggered when focus changes (element or section).
  public var onFocusChange: (() -> Void)?

  /// Creates a new focus manager instance.
  public init() {}

  /// The currently active focus section.
  var activeSection: FocusSection? {
    guard let activeID = activeSectionID else { return nil }
    return section(id: activeID)
  }

  /// The ID of the currently active section, if any.
  var activeSectionIdentifier: String? {
    activeSectionID
  }

  /// All registered section IDs in render order.
  var sectionIDs: [String] {
    sections.map(\.id)
  }

  /// Whether any sections are registered (besides potentially the default).
  var hasSections: Bool {
    !sections.isEmpty
  }

  /// The currently focused element, if any.
  public var currentFocused: Focusable? {
    guard let focusedIdentifier = focusedID else { return nil }
    // Search in active section first, then all sections
    if let section = activeSection,
       let element = section.focusables.first(where: { $0.focusID == focusedIdentifier })
    {
      return element
    }
    for section in sections where section.id != activeSectionID {
      if let element = section.focusables.first(where: { $0.focusID == focusedIdentifier }) {
        return element
      }
    }
    return nil
  }

  /// The ID of the currently focused element, if any.
  public var currentFocusedID: String? {
    focusedID
  }

  /// Whether the currently focused element is a text-input handler.
  ///
  /// When `true`, the input handler should give the focused element
  /// priority for key events before dispatching to other layers.
  var hasTextInputFocus: Bool {
    currentFocused is TextFieldHandler
  }
}

private struct FocusManagerKey: EnvironmentKey {
  static let defaultValue = FocusManager()
}

extension EnvironmentValues {
  /// The focus manager for managing keyboard focus.
  ///
  /// Access via `context.environment.focusManager` in `renderToBuffer(context:)`.
  public var focusManager: FocusManager {
    get { self[FocusManagerKey.self] }
    set { self[FocusManagerKey.self] = newValue }
  }
}
