public struct OverlayID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "An overlay identifier must not be empty.")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public enum OverlayKind: Sendable, Hashable {
    case dialog
    case menu
    case toast
    case custom
}

public struct OverlayPresentation<Content: Sendable>: Sendable {
    public var id: OverlayID
    public var kind: OverlayKind
    public var content: Content
    public var isModal: Bool
    public var dismissOnEscape: Bool
    public var zIndex: Int

    public init(
        id: OverlayID,
        kind: OverlayKind = .custom,
        content: Content,
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

@MainActor
public final class OverlayHost<Content: Sendable> {
    public private(set) var overlays: [OverlayPresentation<Content>] = []
    public let focusManager: FocusManager
    private var initialFocusByOverlay: [OverlayID: FocusID] = [:]

    public init(focusManager: FocusManager = FocusManager()) {
        self.focusManager = focusManager
    }

    public var top: OverlayPresentation<Content>? {
        orderedOverlays.last
    }

    public var orderedOverlays: [OverlayPresentation<Content>] {
        overlays.enumerated().sorted {
            if $0.element.zIndex != $1.element.zIndex { return $0.element.zIndex < $1.element.zIndex }
            return $0.offset < $1.offset
        }.map(\.element)
    }

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

    @discardableResult
    public func dismissTop() -> OverlayPresentation<Content>? {
        guard let top else { return nil }
        return dismiss(top.id)
    }

    @discardableResult
    public func handleEscape() -> Bool {
        guard let top, top.dismissOnEscape else { return false }
        return dismiss(top.id) != nil
    }

    public func semanticNode(children: [SemanticNode]) -> SemanticNode {
        SemanticNode(id: "overlay-host", role: .group, label: "Overlays", children: children)
    }

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

public typealias DialogHost<Content: Sendable> = OverlayHost<Content>
