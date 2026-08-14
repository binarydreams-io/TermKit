@testable import TermKit
import Testing

@MainActor
struct OverlayRuntimeTests {
  @Test
  func `Runtime mounts a modal overlay and restores root focus`() throws {
    let host = ViewOverlayHost()
    var rootActivations = 0
    var overlayActivations = 0
    let presenter = FramePresenter(session: FakeTerminalSession())
    let runtime = Runtime(
      view: Button("Root", id: "root") { rootActivations += 1 },
      presenter: presenter,
      terminalSize: CellSize(width: 20, height: 3),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
    let focusedRoot = try #require(
      try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    )
    #expect(focusedRoot.semantics.node(withID: "root")?.state.contains(.focused) == true)

    host.present(
      OverlayPresentation(
        id: "modal",
        content: Button("Confirm", id: "confirm") { overlayActivations += 1 },
        isModal: true,
        zIndex: 100
      )
    )
    let overlayFrame = try #require(
      try runtime.renderIfDue(
        at: .zero.advanced(by: FrameScheduler.minimumFrameInterval + FrameScheduler.minimumFrameInterval)
      )
    )

    #expect(overlayFrame.semantics.node(withID: "root") != nil)
    #expect(overlayFrame.semantics.node(withID: "confirm")?.state.contains(.focused) == true)
    #expect(surfaceText(presenter).contains("Root"))
    #expect(surfaceText(presenter).contains("Confirm"))
    try runtime.process(.input(.key(TerminalKeyEvent(key: .enter))))
    #expect(overlayActivations == 1)
    #expect(rootActivations == 0)

    try runtime.process(.input(.key(TerminalKeyEvent(key: .escape))))
    let restored = try #require(
      try runtime.renderIfDue(
        at: .zero.advanced(by: FrameScheduler.minimumFrameInterval + FrameScheduler.minimumFrameInterval
          + FrameScheduler.minimumFrameInterval)
      )
    )
    #expect(host.overlays.isEmpty)
    #expect(restored.semantics.node(withID: "root")?.state.contains(.focused) == true)
  }

  @Test
  func `Toast expires through the deterministic runtime timeline`() throws {
    let host = ViewOverlayHost()
    host.present(
      Toast(
        id: "saved",
        message: "Saved",
        createdAt: .zero,
        duration: .milliseconds(100),
        fade: .milliseconds(20)
      )
    )
    let runtime = Runtime(
      view: Text("Root", id: "root"),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 20, height: 4),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )
    try runtime.start()

    let visible = try #require(try runtime.renderIfDue(at: .zero))
    #expect(visible.semantics.node(withID: "toast-saved") != nil)
    #expect(host.overlays.count == 1)

    _ = try runtime.renderIfDue(at: .zero.advanced(by: .milliseconds(100)))
    #expect(host.overlays.isEmpty)
  }

  @Test
  func `Nested modal dismissal restores focus inside the previous modal`() throws {
    let host = ViewOverlayHost()
    let runtime = Runtime(
      view: Button("Root", id: "root") {},
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 30, height: 3),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))

    host.present(
      OverlayPresentation(
        id: "first-modal",
        content: AnyView(
          HStack {
            Button("First", id: "first") {}
            Button("Second", id: "second") {}
          }
        ),
        isModal: true,
        zIndex: 10
      )
    )
    _ = try runtime.renderIfDue(at: instant(2))
    try runtime.process(.input(.key(TerminalKeyEvent(key: .tab))))
    let secondFocused = try #require(try runtime.renderIfDue(at: instant(3)))
    #expect(secondFocused.semantics.node(withID: "second")?.state.contains(.focused) == true)

    host.present(
      OverlayPresentation(
        id: "second-modal",
        content: Button("Top", id: "top") {},
        isModal: true,
        zIndex: 20
      )
    )
    let topFocused = try #require(try runtime.renderIfDue(at: instant(4)))
    #expect(topFocused.semantics.node(withID: "top")?.state.contains(.focused) == true)

    host.dismiss("second-modal")
    let restored = try #require(try runtime.renderIfDue(at: instant(5)))
    #expect(restored.semantics.node(withID: "second")?.state.contains(.focused) == true)
  }

  @Test
  func `Modal overlay honors its requested initial focus`() throws {
    let host = ViewOverlayHost()
    host.present(
      OverlayPresentation(
        id: "modal",
        content: AnyView(
          HStack {
            Button("First", id: "first") {}
            Button("Second", id: "second") {}
          }
        ),
        isModal: true
      ),
      initialFocus: "second"
    )
    let runtime = Runtime(
      view: Button("Root", id: "root") {},
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 20, height: 1),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )

    try runtime.start()
    let frame = try #require(try runtime.renderIfDue(at: .zero))

    #expect(frame.semantics.node(withID: "first")?.state.contains(.focused) == false)
    #expect(frame.semantics.node(withID: "second")?.state.contains(.focused) == true)
  }

  @Test
  func `Overlay invalidation from mount lifecycle schedules a structural frame`() throws {
    enum Root {}
    let host = ViewOverlayHost()
    let descriptor = NodeDescriptor(
      type: Root.self,
      lifecycle: NodeLifecycle(onMount: { _ in
        host.present(
          OverlayPresentation(id: "mounted", content: Text("Mounted", id: "mounted-text"))
        )
      })
    )
    let runtime = Runtime(
      view: DescriptorView(descriptor),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 20, height: 2),
      timeSource: DeterministicTimeSource(),
      overlayHost: host
    )
    try runtime.start()

    _ = try runtime.renderIfDue(at: .zero)
    let mounted = try #require(try runtime.renderIfDue(at: instant(1)))

    #expect(mounted.semantics.node(withID: "mounted-text") != nil)
  }

  private func instant(_ frame: Int64) -> TimeInstant {
    .zero.advanced(by: .nanoseconds(FrameScheduler.minimumFrameInterval.nanoseconds * frame))
  }

  private func surfaceText(_ presenter: FramePresenter) -> String {
    guard let surface = presenter.frontSurface else { return "" }
    return surface.cells.compactMap { cell in
      guard cell.isContinuation == false else { return nil }
      return presenter.resources.graphemes.value(for: cell.graphemeID)
    }.joined()
  }
}
