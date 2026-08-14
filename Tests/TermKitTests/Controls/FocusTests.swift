import Testing

@testable import TermKit

@MainActor
struct FocusTests {
    @Test("A trapping scope cycles only through its enabled targets")
    func trapSkipsDisabledAndOutsideTargets() {
        let manager = FocusManager()
        manager.register(FocusTarget(id: "outside", order: 0))
        manager.register(FocusTarget(id: "first", scopeID: "dialog", order: 0))
        manager.register(FocusTarget(id: "disabled", scopeID: "dialog", isEnabled: false, order: 1))
        manager.register(FocusTarget(id: "last", scopeID: "dialog", order: 2))
        #expect(manager.requestFocus("outside"))

        manager.activateScope(FocusScope(id: "dialog", trapsFocus: true), initialFocus: "first")

        #expect(manager.focusedID == "first")
        #expect(manager.requestFocus("outside") == false)
        #expect(manager.moveFocus() == "last")
        #expect(manager.moveFocus() == "first")
    }

    @Test("Closing a scope restores the previous enabled target")
    func restoration() {
        let manager = FocusManager()
        manager.register(FocusTarget(id: "source"))
        manager.register(FocusTarget(id: "disabled", isEnabled: false))
        manager.register(FocusTarget(id: "dialog-button", scopeID: "dialog"))
        manager.requestFocus("source")
        manager.activateScope(FocusScope(id: "dialog", trapsFocus: true), initialFocus: "dialog-button")

        #expect(manager.deactivateScope("dialog"))
        #expect(manager.focusedID == "source")
        #expect(manager.requestFocus("disabled") == false)
        #expect(manager.focusedID == "source")
    }

    @Test("Nested modal overlays dismiss in stack order and restore focus")
    func nestedOverlayRestoration() {
        let manager = FocusManager()
        manager.register(FocusTarget(id: "source"))
        manager.register(FocusTarget(id: "first-button", scopeID: "overlay-first"))
        manager.register(FocusTarget(id: "second-button", scopeID: "overlay-second"))
        manager.requestFocus("source")
        let host = OverlayHost<String>(focusManager: manager)
        host.present(
            OverlayPresentation(id: "first", content: "first", kind: .dialog, isModal: true),
            initialFocus: "first-button"
        )
        host.present(
            OverlayPresentation(id: "second", content: "second", kind: .dialog, isModal: true),
            initialFocus: "second-button"
        )

        #expect(host.dismiss("first") == nil)
        #expect(manager.focusedID == "second-button")
        #expect(host.dismissTop()?.id == "second")
        #expect(manager.focusedID == "first-button")
        #expect(host.dismissTop()?.id == "first")
        #expect(manager.focusedID == "source")
    }

    @Test("Modal focus order follows visual z-order and Escape restores focus")
    func overlayZOrderRestoration() {
        let manager = FocusManager()
        manager.register(FocusTarget(id: "source"))
        manager.register(FocusTarget(id: "front-button", scopeID: "overlay-front"))
        manager.register(FocusTarget(id: "front-secondary", scopeID: "overlay-front"))
        manager.register(FocusTarget(id: "back-button", scopeID: "overlay-back"))
        manager.requestFocus("source")
        let host = OverlayHost<String>(focusManager: manager)

        host.present(
            OverlayPresentation(id: "front", content: "front", isModal: true, zIndex: 100),
            initialFocus: "front-button"
        )
        manager.requestFocus("front-secondary")
        host.present(
            OverlayPresentation(id: "back", content: "back", isModal: true, zIndex: 10),
            initialFocus: "back-button"
        )

        #expect(host.orderedOverlays.map(\.id) == ["back", "front"])
        #expect(manager.activeScopeID == "overlay-front")
        #expect(manager.focusedID == "front-secondary")
        #expect(host.handleEscape())
        #expect(host.top?.id == "back")
        #expect(manager.activeScopeID == "overlay-back")
        #expect(manager.focusedID == "back-button")
        #expect(host.handleEscape())
        #expect(manager.focusedID == "source")
    }
}
