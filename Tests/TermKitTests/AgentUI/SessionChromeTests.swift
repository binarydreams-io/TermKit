@testable import TermKit
import Testing

struct SessionChromeTests {
  @Test
  func `Sidebar switches from overlay to fixed column at its breakpoint`() {
    let policy = SessionSidebarResponsivePolicy(fixedColumnMinimumTerminalWidth: 100)

    #expect(policy.placement(forTerminalWidth: 99) == .trailingOverlay)
    #expect(policy.placement(forTerminalWidth: 100) == .fixedColumn)
  }

  @Test
  func `Narrow sidebar remains hidden until its overlay is presented`() {
    let section = SessionSidebarSection(kind: .files, title: "Files", items: ["Main.swift"])
    let hidden = SessionSidebar(sections: [section])
    let presented = SessionSidebar(sections: [section], isOverlayPresented: true)

    #expect(hidden.isVisible(forTerminalWidth: 80) == false)
    #expect(presented.isVisible(forTerminalWidth: 80))
    #expect(hidden.isVisible(forTerminalWidth: 120))
  }

  @Test
  func `Footer progressively hides low-priority fields`() {
    let footer = AgentStatusFooter(fields: [
      AgentStatusField(kind: .connection, text: "Online", priority: 100),
      AgentStatusField(kind: .model, text: "Model", priority: 80),
      AgentStatusField(kind: .duration, text: "2s", priority: 40),
      AgentStatusField(kind: .keyboardHints, text: "Esc cancel", priority: 10)
    ])

    #expect(footer.visibleFields(availableWidth: 30).map(\.kind) == [.connection, .model, .duration, .keyboardHints])
    #expect(footer.visibleFields(availableWidth: 17).map(\.kind) == [.connection, .model, .duration])
    #expect(footer.visibleFields(availableWidth: 12).map(\.kind) == [.connection, .model])
    #expect(footer.visibleFields(availableWidth: 6).map(\.kind) == [.connection])
  }
}
