@testable import TermKit
import Testing

@MainActor
struct TextSelectionRuntimeTests {
  @Test
  func `Drag extracts styled wide text and copies once on release`() throws {
    let session = FakeTerminalSession()
    session.capabilities.supportsOSC52 = true
    session.capabilities.allowsOSC52 = true
    var selectedText: String?
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text(
        runs: [
          StyledRun("A界 ", style: CellStyle(attributes: .bold)),
          StyledRun("B\nC D", style: CellStyle(foreground: .rgba(.white)))
        ],
        id: "content"
      ),
      presenter: presenter,
      terminalSize: CellSize(width: 8, height: 2),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration(),
      onSelectionEnd: {
        selectedText = $0
        return .automatic
      }
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    let payloadCount = session.presentedPayloads.count

    try runtime.process(.input(mouse(.press(.left), x: 2, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 3, y: 1)))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    try runtime.process(.input(mouse(.release(.left), x: 3, y: 1)))

    #expect(selectedText == "界 B\nC D")
    let clipboard = try OSC52Encoder.encode("界 B\nC D")
    #expect(session.presentedPayloads.dropFirst(payloadCount).filter { $0 == clipboard }.count == 1)
    try runtime.process(.input(mouse(.release(.left), x: 3, y: 1)))
    #expect(session.presentedPayloads.dropFirst(payloadCount).filter { $0 == clipboard }.count == 1)
    let surface = try #require(presenter.frontSurface)
    #expect(surface[CellPoint(x: 1, y: 0)].styleID == surface[CellPoint(x: 2, y: 0)].styleID)
    #expect(presenter.resources.styles.value(for: surface[CellPoint(x: 1, y: 0)].styleID)?.attributes.contains(.inverse) == true)
  }

  @Test(arguments: [false, true])
  func `Copy suppression keeps selection rendering`(suppressWithHook: Bool) throws {
    let session = FakeTerminalSession()
    session.capabilities.supportsOSC52 = true
    session.capabilities.allowsOSC52 = true
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text("select"),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration(
        copiesOnRelease: suppressWithHook,
        style: CellStyle(background: .rgba(.white))
      ),
      onSelectionEnd: { _ in suppressWithHook ? .suppress : .automatic }
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    let payloadCount = session.presentedPayloads.count

    try runtime.process(.input(mouse(.press(.left), x: 0, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 2, y: 0)))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    try runtime.process(.input(mouse(.release(.left), x: 2, y: 0)))

    #expect(session.presentedPayloads.count == payloadCount + 1)
    let surface = try #require(presenter.frontSurface)
    #expect(presenter.resources.styles.value(for: surface[.zero].styleID)?.background == .rgba(.white))
  }

  @Test
  func `Automatic copy clears the selection on release`() throws {
    let session = FakeTerminalSession()
    session.capabilities.supportsOSC52 = true
    session.capabilities.allowsOSC52 = true
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text("select"),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration()
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    let payloadCount = session.presentedPayloads.count

    try runtime.process(.input(mouse(.press(.left), x: 0, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 2, y: 0)))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    try runtime.process(.input(mouse(.release(.left), x: 2, y: 0)))
    let clipboard = try OSC52Encoder.encode("sel")
    #expect(session.presentedPayloads.dropFirst(payloadCount).filter { $0 == clipboard }.count == 1)

    _ = try runtime.renderIfDue(
      at: .zero.advanced(by: FrameScheduler.minimumFrameInterval + FrameScheduler.minimumFrameInterval)
    )
    let surface = try #require(presenter.frontSurface)
    #expect(presenter.resources.styles.value(for: surface[.zero].styleID)?.attributes.contains(.inverse) == false)
  }

  @Test
  func `A wandering drag that returns to its anchor stays a click`() throws {
    let session = FakeTerminalSession()
    session.capabilities.supportsOSC52 = true
    session.capabilities.allowsOSC52 = true
    var selectionEnded = false
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text("select"),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration(),
      onSelectionEnd: { _ in
        selectionEnded = true
        return .automatic
      }
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    let payloadCount = session.presentedPayloads.count

    try runtime.process(.input(mouse(.press(.left), x: 1, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 2, y: 0)))
    try runtime.process(.input(mouse(.release(.left), x: 1, y: 0)))

    #expect(selectionEnded == false)
    #expect(session.presentedPayloads.count == payloadCount)
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    let surface = try #require(presenter.frontSurface)
    #expect(presenter.resources.styles.value(for: surface[.zero].styleID)?.attributes.contains(.inverse) == false)
  }

  @Test
  func `Clipboard-less terminal does not copy and Escape clears selection`() throws {
    let session = FakeTerminalSession()
    session.capabilities.allowsOSC52 = true
    let presenter = FramePresenter(session: session)
    let runtime = Runtime(
      view: Text("select"),
      presenter: presenter,
      terminalSize: CellSize(width: 6, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration()
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)
    let payloadCount = session.presentedPayloads.count

    try runtime.process(.input(mouse(.press(.left), x: 0, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 2, y: 0)))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))
    try runtime.process(.input(mouse(.release(.left), x: 2, y: 0)))
    #expect(session.presentedPayloads.count == payloadCount + 1)

    try runtime.process(.input(.key(TerminalKeyEvent(key: .escape))))
    _ = try runtime.renderIfDue(
      at: .zero.advanced(by: FrameScheduler.minimumFrameInterval + FrameScheduler.minimumFrameInterval)
    )
    let surface = try #require(presenter.frontSurface)
    #expect(presenter.resources.styles.value(for: surface[.zero].styleID)?.attributes.contains(.inverse) == false)
  }

  @Test(arguments: [ColorScheme.light, ColorScheme.dark])
  func `Selection uses semantic theme colors`(scheme: ColorScheme) throws {
    let theme = try SemanticTheme.standard.resolve(scheme: scheme)
    let presenter = FramePresenter(session: FakeTerminalSession())
    let runtime = Runtime(
      view: Text("theme"),
      presenter: presenter,
      terminalSize: CellSize(width: 5, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration(
        theme: theme,
        copiesOnRelease: false
      )
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(.input(mouse(.press(.left), x: 0, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 2, y: 0)))
    _ = try runtime.renderIfDue(at: .zero.advanced(by: FrameScheduler.minimumFrameInterval))

    let surface = try #require(presenter.frontSurface)
    let style = try #require(presenter.resources.styles.value(for: surface[.zero].styleID))
    #expect(style.foreground == .rgba(theme[.selectedText]))
    #expect(style.background == .rgba(theme[.selectedBackground]))
  }

  @Test
  func `Selection extracts only text visible through clipping`() throws {
    var selectedText: String?
    let runtime = Runtime(
      view: Text("ABCDE").frame(width: 3),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 5, height: 1),
      timeSource: DeterministicTimeSource(),
      textSelectionConfiguration: TextSelectionConfiguration(copiesOnRelease: false),
      onSelectionEnd: {
        selectedText = $0
        return .automatic
      }
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(.input(mouse(.press(.left), x: 0, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 4, y: 0)))
    try runtime.process(.input(mouse(.release(.left), x: 4, y: 0)))

    #expect(selectedText == "ABC")
  }

  @Test
  func `Selection reads the topmost overlay surface`() throws {
    let host = ViewOverlayHost()
    host.present(OverlayPresentation(id: "overlay", content: AnyView(Text("TOP")), zIndex: 10))
    var selectedText: String?
    let runtime = Runtime(
      view: Text("abcde"),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 5, height: 1),
      timeSource: DeterministicTimeSource(),
      overlayHost: host,
      textSelectionConfiguration: TextSelectionConfiguration(copiesOnRelease: false),
      onSelectionEnd: {
        selectedText = $0
        return .automatic
      }
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(.input(mouse(.press(.left), x: 1, y: 0)))
    try runtime.process(.input(mouse(.drag(.left), x: 3, y: 0)))
    try runtime.process(.input(mouse(.release(.left), x: 3, y: 0)))

    #expect(selectedText == "TOP")
  }

  private func mouse(_ action: TerminalMouseAction, x: Int, y: Int) -> TerminalInputEvent {
    .mouse(
      TerminalMouseEvent(
        action: action,
        position: TerminalCellPoint(column: x, row: y)
      )
    )
  }
}
