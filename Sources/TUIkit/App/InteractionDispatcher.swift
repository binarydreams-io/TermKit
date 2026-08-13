//  TUIkit - Terminal UI Kit for Swift
//  InteractionDispatcher.swift
//
//  License: MIT

/// Resolves mouse events against the interaction regions from the active frame.
///
/// Frame buffers contain stable identifiers and bounds only. This dispatcher
/// stores the closures for those identifiers on the main actor.
@MainActor
final class InteractionDispatcher {
    private enum ClickBehavior {
        case action(() -> Void)
        case key(Key)
    }

    private struct Registration {
        var click: ClickBehavior?
        var scroll: ((MouseEvent.ScrollDirection) -> Void)?
    }

    private var registrations: [String: Registration] = [:]
    private(set) var activeRegions: [InteractionRegion] = []
    private var pressedTargetID: String?
    private var acceptsRegistrations = true

    nonisolated init() {}
}

// MARK: - Render Registration

extension InteractionDispatcher {
    /// Removes registrations from the previous render pass.
    func beginRenderPass() {
        registrations.removeAll(keepingCapacity: true)
        acceptsRegistrations = true
    }

    /// Replaces the hit map with regions from the completed frame.
    func activate(regions: [InteractionRegion]) {
        activeRegions = regions
        if let pressedTargetID,
            regions.contains(where: { $0.id == pressedTargetID }) == false
        {
            self.pressedTargetID = nil
        }
    }

    /// Registers an action for a clickable region identifier.
    func registerClick(id: String, action: @escaping () -> Void) {
        guard acceptsRegistrations else { return }
        registrations[id, default: Registration()].click = .action(action)
    }

    /// Registers a key for a clickable region identifier.
    func registerClick(id: String, key: Key) {
        guard acceptsRegistrations else { return }
        registrations[id, default: Registration()].click = .key(key)
    }

    /// Registers a scroll callback for a region identifier.
    func registerScroll(
        id: String,
        action: @escaping (MouseEvent.ScrollDirection) -> Void
    ) {
        guard acceptsRegistrations else { return }
        registrations[id, default: Registration()].scroll = action
    }

    /// Starts a registration scope that excludes previously rendered content.
    func beginExclusiveScope() {
        registrations.removeAll(keepingCapacity: true)
        acceptsRegistrations = true
    }

    /// Prevents content outside an exclusive scope from registering handlers.
    func endExclusiveScope() {
        acceptsRegistrations = false
    }

    /// Removes all registrations and active interaction state.
    func reset() {
        registrations.removeAll()
        activeRegions.removeAll()
        pressedTargetID = nil
        acceptsRegistrations = true
    }
}

// MARK: - Event Dispatch

extension InteractionDispatcher {
    /// Dispatches a mouse event and returns a synthetic key when needed.
    func dispatch(_ event: MouseEvent) -> KeyEvent? {
        switch event.action {
        case .press(.left):
            pressedTargetID = topmostClickTarget(atColumn: event.column, row: event.row)

        case .release(.left):
            defer { pressedTargetID = nil }
            guard let pressedTargetID,
                pressedTargetID == topmostClickTarget(atColumn: event.column, row: event.row),
                let click = registrations[pressedTargetID]?.click
            else {
                return nil
            }

            switch click {
            case .action(let action):
                action()
            case .key(let key):
                return KeyEvent(key: key)
            }

        case .scroll(let direction):
            guard let targetID = topmostScrollTarget(atColumn: event.column, row: event.row) else {
                return nil
            }
            registrations[targetID]?.scroll?(direction)

        case .press, .release, .drag, .move:
            break
        }

        return nil
    }
}

// MARK: - Hit Testing

extension InteractionDispatcher {
    fileprivate func topmostClickTarget(atColumn column: Int, row: Int) -> String? {
        topmostTarget(atColumn: column, row: row) { $0.click != nil }
    }

    fileprivate func topmostScrollTarget(atColumn column: Int, row: Int) -> String? {
        topmostTarget(atColumn: column, row: row) { $0.scroll != nil }
    }

    private func topmostTarget(
        atColumn column: Int,
        row: Int,
        matching predicate: (Registration) -> Bool
    ) -> String? {
        for region in activeRegions.reversed() {
            guard region.rect.x <= column,
                column < region.rect.maxX,
                region.rect.y <= row,
                row < region.rect.maxY,
                let registration = registrations[region.id],
                predicate(registration)
            else {
                continue
            }
            return region.id
        }
        return nil
    }
}
