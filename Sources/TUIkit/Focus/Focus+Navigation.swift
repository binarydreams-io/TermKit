//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Focus+Navigation.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Navigation

extension FocusManager {
  /// Focuses a specific element.
  ///
  /// - Parameter element: The element to focus.
  public func focus(_ element: Focusable) {
    guard element.canBeFocused else { return }

    notifyFocusLost()

    focusedID = element.focusID
    element.onFocusReceived()
    onFocusChange?()
  }

  /// Activates the next section (wrapping around).
  ///
  /// When switching sections, the first focusable element in the new
  /// section receives focus automatically.
  func activateNextSection() {
    cycleSection(direction: .forward)
  }

  /// Activates the previous section (wrapping around).
  ///
  /// When switching sections, the first focusable element in the new
  /// section receives focus automatically.
  func activatePreviousSection() {
    cycleSection(direction: .backward)
  }

  /// Activates a specific section by ID.
  ///
  /// The first focusable element in the section receives focus.
  ///
  /// - Parameter id: The section identifier to activate.
  func activateSection(id: String) {
    guard sections.contains(where: { $0.id == id }) else { return }
    guard activeSectionID != id else { return }

    // Notify current focused element
    notifyFocusLost()

    activeSectionID = id
    focusedID = nil

    // Auto-focus first element in the new section
    if let section = activeSection,
       let firstFocusable = section.focusables.first(where: { $0.canBeFocused })
    {
      focusedID = firstFocusable.focusID
      firstFocusable.onFocusReceived()
    }

    onFocusChange?()
  }

  /// Moves focus to the next element within the active section.
  ///
  /// Arrow-key navigation: does **not** wrap at the boundary.
  public func focusNextInSection() {
    moveFocusInSection(direction: .forward, wrap: false)
  }

  /// Moves focus to the previous element within the active section.
  ///
  /// Arrow-key navigation: does **not** wrap at the boundary.
  public func focusPreviousInSection() {
    moveFocusInSection(direction: .backward, wrap: false)
  }

  /// Moves focus to the next focusable element.
  ///
  /// When multiple sections exist, Tab navigates within the current section
  /// first. Only when the current element is the last in its section does
  /// Tab switch to the next section.
  /// When only one section exists, this cycles within it (wrapping).
  public func focusNext() {
    if sections.count > 1 {
      let moved = moveFocusInSection(direction: .forward, wrap: false)
      if !moved {
        activateNextSection()
      }
    } else {
      moveFocusInSection(direction: .forward, wrap: true)
    }
  }

  /// Moves focus to the previous focusable element.
  ///
  /// When multiple sections exist, Shift+Tab navigates within the current
  /// section first. Only when the current element is the first in its section
  /// does Shift+Tab switch to the previous section.
  /// When only one section exists, this cycles within it (wrapping).
  public func focusPrevious() {
    if sections.count > 1 {
      let moved = moveFocusInSection(direction: .backward, wrap: false)
      if !moved {
        activatePreviousSection()
      }
    } else {
      moveFocusInSection(direction: .backward, wrap: true)
    }
  }

  /// Dispatches a key event through the focus system.
  ///
  /// Navigation model:
  /// - **Tab / Shift+Tab**: Cycles between sections (or within a single section).
  /// - **Up / Down arrows**: Cycles between focusable elements within the active section.
  /// - **Enter / Space**: Dispatched to the focused element for activation.
  /// - **Other keys**: Dispatched to the focused element.
  ///
  /// - Parameter event: The key event to dispatch.
  /// - Returns: True if the event was handled.
  @discardableResult
  public func dispatchKeyEvent(_ event: KeyEvent) -> Bool {
    // Dispatch to focused element first — let it handle keys like Up/Down/Left/Right.
    // If element consumes the event, stop here.
    if let focused = currentFocused {
      if focused.handleKeyEvent(event) {
        return true
      }
    }

    // Tab navigation: cycle sections (or elements within single section)
    if event.key == .tab {
      if event.shift {
        focusPrevious()
      } else {
        focusNext()
      }
      return true
    }

    // Arrow keys: navigate within the active section (fallback if element didn't handle)
    // Up/Left go to previous, Down/Right go to next
    switch event.key {
    case .up, .left:
      focusPreviousInSection()
      return true
    case .down, .right:
      focusNextInSection()
      return true
    default:
      break
    }

    return false
  }
}

// MARK: - Private Helpers

/// The direction in which focus moves.
private enum FocusDirection {
  case forward, backward
}

extension FocusManager {
  /// Cycles the active section in the given direction.
  private func cycleSection(direction: FocusDirection) {
    guard sections.count > 1 else { return }

    let sectionIndex: Int = if let activeID = activeSectionID,
                               let currentIndex = sections.firstIndex(where: { $0.id == activeID })
    {
      switch direction {
      case .forward:
        (currentIndex + 1) % sections.count
      case .backward:
        currentIndex == 0 ? sections.count - 1 : currentIndex - 1
      }
    } else {
      direction == .forward ? 0 : sections.count - 1
    }

    activateSection(id: sections[sectionIndex].id)
  }

  /// Moves focus within the active section.
  ///
  /// - Parameters:
  ///   - direction: The direction in which to move focus.
  ///   - wrap: When `true`, focus wraps around from the last element to the
  ///     first (and vice versa). When `false`, focus stops at the boundary
  ///     and the method returns `false`.
  /// - Returns: `true` if focus moved to a new element, `false` if the
  ///   boundary was reached (and `wrap` is `false`) or no element is available.
  @discardableResult
  private func moveFocusInSection(direction: FocusDirection, wrap: Bool = true) -> Bool {
    guard let section = activeSection else { return false }

    let available = section.focusables.filter(\.canBeFocused)
    guard !available.isEmpty else { return false }

    if let currentID = focusedID,
       let currentIndex = available.firstIndex(where: { $0.focusID == currentID })
    {
      let targetIndex: Int
      switch direction {
      case .forward:
        if currentIndex == available.count - 1 {
          guard wrap else { return false }
          targetIndex = 0
        } else {
          targetIndex = currentIndex + 1
        }
      case .backward:
        if currentIndex == 0 {
          guard wrap else { return false }
          targetIndex = available.count - 1
        } else {
          targetIndex = currentIndex - 1
        }
      }
      focus(available[targetIndex])
      return true
    } else {
      let fallbackIndex = direction == .forward ? 0 : available.count - 1
      focus(available[fallbackIndex])
      return true
    }
  }

  /// Notifies the currently focused element that it lost focus.
  private func notifyFocusLost() {
    guard let currentID = focusedID else { return }
    for section in sections {
      if let current = section.focusables.first(where: { $0.focusID == currentID }) {
        current.onFocusLost()
        return
      }
    }
  }
}
