//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Focus+Registration.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Public API

extension FocusManager {
  /// Registers a focusable element in a specific section.
  ///
  /// If the section doesn't exist, it is created automatically.
  /// If no element is focused yet in the active section, the element
  /// is auto-focused.
  ///
  /// - Parameters:
  ///   - element: The element to register.
  ///   - sectionID: The section to register in. Defaults to the active section
  ///     or the default section if no section is active.
  public func register(_ element: Focusable, inSection sectionID: String? = nil) {
    let targetID = sectionID ?? activeSectionID ?? Self.defaultSectionID

    // Ensure section exists
    if !sections.contains(where: { $0.id == targetID }) {
      registerSection(id: targetID)
    }

    guard let section = section(id: targetID) else { return }
    section.register(element)

    // Auto-activate section and auto-focus first element if needed
    if activeSectionID == nil {
      activeSectionID = targetID
    }
    if targetID == activeSectionID, focusedID == nil, element.canBeFocused {
      focus(element)
    }
  }

  /// Registers a focusable element (legacy API, uses active or default section).
  ///
  /// This overload exists for backward compatibility. New code should use
  /// ``register(_:inSection:)`` to explicitly assign sections.
  ///
  /// - Parameter element: The element to register.
  public func register(_ element: Focusable) {
    register(element, inSection: nil)
  }

  /// Unregisters a focusable element from all sections.
  ///
  /// - Parameter element: The element to unregister.
  public func unregister(_ element: Focusable) {
    for section in sections {
      section.unregister(element)
    }

    // If the removed element was focused, focus the next available
    if focusedID == element.focusID {
      focusedID = nil
      focusNextInSection()
    }
  }

  /// Clears all sections and focusable elements, including selection state.
  ///
  /// This is a hard reset. For per-frame clearing that preserves the active
  /// section and focused element, use `beginRenderPass()` instead.
  public func clear() {
    sections.removeAll()
    activeSectionID = nil
    focusedID = nil
  }

  /// Focuses an element by ID (searches all sections).
  ///
  /// - Parameter id: The focus ID of the element to focus.
  public func focus(id: String) {
    for section in sections {
      if let element = section.focusables.first(where: { $0.focusID == id && $0.canBeFocused }) {
        // Also activate the section containing this element
        if activeSectionID != section.id {
          activeSectionID = section.id
        }
        focus(element)
        return
      }
    }
  }

  /// Returns whether the given element is currently focused.
  ///
  /// - Parameter element: The element to check.
  /// - Returns: True if the element is focused.
  public func isFocused(_ element: Focusable) -> Bool {
    focusedID == element.focusID
  }

  /// Returns whether an element with the given ID is currently focused.
  ///
  /// - Parameter id: The focus ID to check.
  /// - Returns: True if the element is focused.
  public func isFocused(id: String) -> Bool {
    focusedID == id
  }

  /// Returns whether the given section is currently active.
  ///
  /// - Parameter sectionID: The section identifier to check.
  /// - Returns: True if the section is active.
  public func isActiveSection(_ sectionID: String) -> Bool {
    activeSectionID == sectionID
  }
}
