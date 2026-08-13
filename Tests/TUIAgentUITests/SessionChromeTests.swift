import Testing

@testable import TUIAgentUI

struct SessionChromeTests {
    @Test("Sidebar switches from overlay to fixed column at its breakpoint")
    func sidebarPlacement() {
        let policy = SessionSidebarResponsivePolicy(fixedColumnMinimumTerminalWidth: 100)

        #expect(policy.placement(forTerminalWidth: 99) == .trailingOverlay)
        #expect(policy.placement(forTerminalWidth: 100) == .fixedColumn)
    }

    @Test("Narrow sidebar remains hidden until its overlay is presented")
    func sidebarVisibility() {
        let section = SessionSidebarSection(kind: .files, title: "Files", items: ["Main.swift"])
        let hidden = SessionSidebar(sections: [section])
        let presented = SessionSidebar(sections: [section], isOverlayPresented: true)

        #expect(hidden.isVisible(forTerminalWidth: 80) == false)
        #expect(presented.isVisible(forTerminalWidth: 80))
        #expect(hidden.isVisible(forTerminalWidth: 120))
    }

    @Test("Footer progressively hides low-priority fields")
    func footerHiding() {
        let footer = AgentStatusFooter(fields: [
            AgentStatusField(kind: .connection, text: "Online", priority: 100),
            AgentStatusField(kind: .model, text: "Model", priority: 80),
            AgentStatusField(kind: .duration, text: "2s", priority: 40),
            AgentStatusField(kind: .keyboardHints, text: "Esc cancel", priority: 10),
        ])

        #expect(footer.visibleFields(availableWidth: 30).map(\.kind) == [.connection, .model, .duration, .keyboardHints])
        #expect(footer.visibleFields(availableWidth: 17).map(\.kind) == [.connection, .model, .duration])
        #expect(footer.visibleFields(availableWidth: 12).map(\.kind) == [.connection, .model])
        #expect(footer.visibleFields(availableWidth: 6).map(\.kind) == [.connection])
    }
}
