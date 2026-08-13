//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Focus+Sections.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal API

extension FocusManager {
  /// Registers a focus section.
  ///
  /// If a section with the same ID already exists, it is reused (not duplicated).
  /// The first registered section becomes the active section automatically.
  ///
  /// - Parameter id: The unique section identifier.
  func registerSection(id: String) {
    guard !sections.contains(where: { $0.id == id }) else { return }
    let section = FocusSection(id: id)
    sections.append(section)

    // Auto-activate first section
    if activeSectionID == nil {
      activeSectionID = id
    }
  }

  /// Returns the section with the given ID, or nil if not found.
  ///
  /// - Parameter id: The section identifier.
  /// - Returns: The focus section, or nil.
  func section(id: String) -> FocusSection? {
    sections.first { $0.id == id }
  }

  /// Prepares the focus manager for a new render pass.
  ///
  /// Clears all sections and focusable elements so they can be re-registered
  /// from the current view tree. The active section ID and focused element ID
  /// are **preserved** — if they still exist after the render pass, focus
  /// continues seamlessly. If they don't, the first available element is
  /// auto-focused.
  ///
  /// Call this at the start of each render pass instead of ``clear()``.
  func beginRenderPass() {
    sections.removeAll()
    // activeSectionID and focusedID are intentionally preserved.
    // They will be validated after the render pass re-registers sections.
  }

  /// Validates focus state after a render pass.
  ///
  /// If the previously active section no longer exists, the first
  /// registered section is activated. If the previously focused element
  /// no longer exists, the first focusable in the active section is focused.
  func endRenderPass() {
    // Validate active section
    if let activeID = activeSectionID,
       !sections.contains(where: { $0.id == activeID })
    {
      activeSectionID = sections.first?.id
    }

    // Validate focused element
    if let focusID = focusedID, let section = activeSection {
      if !section.focusables.contains(where: { $0.focusID == focusID }) {
        // Previously focused element is gone — auto-focus first available
        focusedID = nil
        if let firstFocusable = section.focusables.first(where: { $0.canBeFocused }) {
          focusedID = firstFocusable.focusID
          firstFocusable.onFocusReceived()
        }
      }
    } else if focusedID == nil, let section = activeSection,
              let firstFocusable = section.focusables.first(where: { $0.canBeFocused })
    {
      focusedID = firstFocusable.focusID
      firstFocusable.onFocusReceived()
    }
  }
}
