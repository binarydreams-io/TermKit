/// A stable identifier for an overlay.
public struct OverlayID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
  /// The identifier's string value.
  public var rawValue: String

  /// Creates an overlay identifier from a nonempty string.
  public init(rawValue: String) {
    precondition(rawValue.isEmpty == false, "An overlay identifier must not be empty.")
    self.rawValue = rawValue
  }

  /// Creates an overlay identifier from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

/// A category of overlay presentation.
public enum OverlayKind: Sendable, Hashable {
  /// A dialog overlay.
  case dialog
  /// A menu overlay.
  case menu
  /// A transient toast overlay.
  case toast
  /// An application-defined overlay.
  case custom
}

/// Content and behavior settings for one overlay.
public struct OverlayPresentation<Content: Sendable>: Sendable {
  /// The overlay identifier.
  public var id: OverlayID
  /// The overlay category.
  public var kind: OverlayKind
  /// The presented content.
  public var content: Content
  /// A value that indicates whether the overlay traps focus.
  public var isModal: Bool
  /// A value that indicates whether Escape dismisses the overlay.
  public var dismissOnEscape: Bool
  /// The stacking priority.
  public var zIndex: Int

  /// Creates an overlay presentation.
  public init(
    id: OverlayID,
    content: Content,
    kind: OverlayKind = .custom,
    isModal: Bool = false,
    dismissOnEscape: Bool = true,
    zIndex: Int = 0
  ) {
    self.id = id
    self.kind = kind
    self.content = content
    self.isModal = isModal
    self.dismissOnEscape = dismissOnEscape
    self.zIndex = zIndex
  }
}

/// Manages ordered overlays and modal focus scopes.
@MainActor
public final class OverlayHost<Content: Sendable> {
  /// The overlays in insertion order.
  public private(set) var overlays: [OverlayPresentation<Content>] = []
  /// The focus manager used for modal scopes.
  public let focusManager: FocusManager
  private var initialFocusByOverlay: [OverlayID: FocusID] = [:]

  /// Creates an overlay host.
  public init(focusManager: FocusManager = FocusManager()) {
    self.focusManager = focusManager
  }

  /// The topmost overlay.
  /// - Complexity: O(n log n), where n is the overlay count.
  public var top: OverlayPresentation<Content>? {
    orderedOverlays.last
  }

  /// The overlays ordered by stacking and insertion order.
  /// - Complexity: O(n log n), where n is the overlay count.
  public var orderedOverlays: [OverlayPresentation<Content>] {
    overlays.enumerated().sorted {
      if $0.element.zIndex != $1.element.zIndex {
        return $0.element.zIndex < $1.element.zIndex
      }
      return $0.offset < $1.offset
    }.map(\.element)
  }

  /// Presents or replaces an overlay.
  /// - Complexity: O(n log n), where n is the overlay count.
  public func present(_ overlay: OverlayPresentation<Content>, initialFocus: FocusID? = nil) {
    let previousModalOverlays = orderedOverlays.filter(\.isModal)
    overlays.removeAll { $0.id == overlay.id }
    overlays.append(overlay)
    if overlay.isModal {
      initialFocusByOverlay[overlay.id] = initialFocus
    } else {
      initialFocusByOverlay.removeValue(forKey: overlay.id)
    }
    let modalOverlays = orderedOverlays.filter(\.isModal)
    if previousModalOverlays.map(\.id) != modalOverlays.map(\.id) {
      if let activeOverlay = previousModalOverlays.last,
         let focusedID = focusManager.focusedID
      {
        initialFocusByOverlay[activeOverlay.id] = focusedID
      }
      deactivateScopes(for: previousModalOverlays)
      activateScopes(for: modalOverlays)
    }
  }

  /// Dismisses an overlay when modal ordering permits it.
  /// - Complexity: O(n log n), where n is the overlay count.
  @discardableResult
  public func dismiss(_ id: OverlayID) -> OverlayPresentation<Content>? {
    guard let index = overlays.firstIndex(where: { $0.id == id }) else { return nil }
    if overlays[index].isModal,
       orderedOverlays.last(where: \.isModal)?.id != id
    {
      return nil
    }
    let previousModalOverlays = orderedOverlays.filter(\.isModal)
    let overlay = overlays.remove(at: index)
    if overlay.isModal {
      deactivateScopes(for: previousModalOverlays)
      initialFocusByOverlay.removeValue(forKey: overlay.id)
      activateScopes(for: orderedOverlays.filter(\.isModal))
    } else {
      initialFocusByOverlay.removeValue(forKey: overlay.id)
    }
    return overlay
  }

  /// Dismisses the topmost overlay.
  /// - Complexity: O(n log n), where n is the overlay count.
  @discardableResult
  public func dismissTop() -> OverlayPresentation<Content>? {
    guard let top else { return nil }
    return dismiss(top.id)
  }

  /// Handles Escape by dismissing the eligible top overlay.
  /// - Complexity: O(n log n), where n is the overlay count.
  @discardableResult
  public func handleEscape() -> Bool {
    guard let top, top.dismissOnEscape else { return false }
    return dismiss(top.id) != nil
  }

  /// Creates the semantic group for overlay children.
  /// - Complexity: O(1).
  public func semanticNode(children: [SemanticNode]) -> SemanticNode {
    SemanticNode(id: "overlay-host", role: .group, label: "Overlays", children: children)
  }

  /// Returns the focus scope identifier for an overlay.
  /// - Complexity: O(1).
  public func focusScopeID(for id: OverlayID) -> FocusScopeID {
    scopeID(for: id)
  }

  private func scopeID(for id: OverlayID) -> FocusScopeID {
    FocusScopeID(rawValue: "overlay-\(id.rawValue)")
  }

  private func deactivateScopes(for modalOverlays: [OverlayPresentation<Content>]) {
    for overlay in modalOverlays.reversed() {
      precondition(
        focusManager.deactivateScope(scopeID(for: overlay.id)),
        "The modal focus stack must match the visual overlay order."
      )
    }
  }

  private func activateScopes(for modalOverlays: [OverlayPresentation<Content>]) {
    for overlay in modalOverlays {
      focusManager.activateScope(
        FocusScope(id: scopeID(for: overlay.id), trapsFocus: true),
        initialFocus: initialFocusByOverlay[overlay.id]
      )
    }
  }
}

/// An overlay host used for dialog content.
public typealias DialogHost<Content: Sendable> = OverlayHost<Content>
