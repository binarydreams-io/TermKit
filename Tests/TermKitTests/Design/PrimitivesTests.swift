@testable import TermKit
import Testing

struct PrimitivesTests {
  @Test
  @MainActor
  func `Surface leaf retains its primitive and includes padding in measurement`() throws {
    let surface = SurfaceView(
      text: "界",
      foreground: .white,
      background: .black,
      padding: EdgeInsets(horizontal: 2, vertical: 1)
    )
    let descriptor = try #require(surface.graphBody.first)

    #expect(descriptor.primitive(as: SurfaceView.self) == surface)
    #expect(descriptor.dirtyOnUpdate.contains(.layout))
    #expect(surface.sizeThatFits(.unspecified) == CellSize(width: 6, height: 3))
    #expect(surface.sizeThatFits(ProposedCellSize(width: 5)) == CellSize(width: 5, height: 3))
  }

  @Test
  func `Metadata hides low-priority fields before primary content`() {
    let line = MetadataLine(
      fields: [
        MetadataField("main", priority: 10),
        MetadataField("branch", priority: 5),
        MetadataField("12:45", priority: 0)
      ],
      style: .default
    )

    #expect(line.text(in: 21) == "main · branch · 12:45")
    #expect(line.text(in: 13) == "main · branch")
    #expect(line.text(in: 4) == "main")
    #expect(line.text(in: 3) == "mai")
  }

  @Test
  func `Metadata uses terminal cell width for progressive hiding and clipping`() {
    let line = MetadataLine(
      fields: [
        MetadataField("界", priority: 10),
        MetadataField("x", priority: 0)
      ],
      style: .default,
      separator: " "
    )

    #expect(line.text(in: 4) == "界 x")
    #expect(line.text(in: 2) == "界")
    #expect(line.text(in: 1) == "�")
  }

  @Test
  func `Reduced motion uses the static activity fallback and no schedule`() {
    let indicator = ActivityIndicator(
      sample: TimelineSample(instant: TimeInstant(nanoseconds: 250_000_000), reduceMotion: true),
      frames: ["a", "b"],
      interval: .milliseconds(100)
    )

    #expect(indicator.text == "...")
    #expect(indicator.schedule == nil)
  }

  @Test
  func `Timeline sample selects an activity frame without owning a timer`() {
    let indicator = ActivityIndicator(
      sample: TimelineSample(instant: TimeInstant(nanoseconds: 250_000_000)),
      frames: ["a", "b", "c"],
      interval: .milliseconds(100)
    )

    #expect(indicator.text == "c")
    #expect(indicator.schedule?.cadence == .milliseconds(100))
  }

  @Test
  @MainActor
  func `Activity view adapter uses the standard timeline`() throws {
    let descriptor = try #require(
      ActivityIndicatorView(frames: ["a", "b"], interval: .milliseconds(100))
        .graphBody.first
    )

    #expect(descriptor.primitive == nil)
    #expect(descriptor.dirtyOnUpdate == .paint)
  }

  @Test
  func `Dialog width is constrained by terminal margins`() {
    let dialog = DialogSurface(id: "preferences", title: "Preferences", content: "body", preferredWidth: .wide)

    #expect(dialog.frame(in: CellSize(width: 140, height: 40), contentHeight: 20).width == 116)
    #expect(dialog.frame(in: CellSize(width: 70, height: 40), contentHeight: 20).width == 66)
  }

  @Test
  func `Toast wrapping uses terminal cell width`() {
    let toast = Toast(id: "unicode", message: "A界B", createdAt: .zero)

    #expect(toast.wrappedLines(width: 2) == ["A", "界", "B"])
  }

  @Test
  @MainActor
  func `Toast fade is configurable and static expiry has a callback contract`() {
    let toast = Toast(
      id: "short",
      message: "Saved",
      createdAt: .zero,
      duration: .seconds(1),
      fade: .milliseconds(200)
    )

    #expect(toast.opacity(at: .zero.advanced(by: .milliseconds(900)), reduceMotion: false) == 0.5)
    #expect(toast.opacity(at: .zero.advanced(by: .milliseconds(900)), reduceMotion: true) == 1)
    #expect(toast.timeline { _ in }.graphBody.isEmpty == false)
  }

  @Test
  @MainActor
  func `Elevation changes the painted surface depth`() throws {
    var resources = ControlRenderResources()
    let bounds = CellRect(x: 0, y: 0, width: 4, height: 1)
    var flatSurface = Surface(size: bounds.size)
    var raisedSurface = Surface(size: bounds.size)
    _ = try SurfaceView(text: "A", foreground: .white, background: .black, elevation: .flat)
      .paint(into: &flatSurface, context: PaintContext(clip: bounds), resources: &resources)
    _ = try SurfaceView(text: "A", foreground: .white, background: .black, elevation: .raised)
      .paint(into: &raisedSurface, context: PaintContext(clip: bounds), resources: &resources)

    #expect(flatSurface[.zero].styleID != raisedSurface[.zero].styleID)
  }

  @Test
  @MainActor
  func `Dialog paints a backdrop and centered panel`() throws {
    var surface = Surface(size: CellSize(width: 70, height: 7))
    var resources = ControlRenderResources()
    let dialog = DialogSurface(id: "confirm", title: "Confirm", content: "Proceed?", preferredWidth: .compact)

    let node = try dialog.paint(
      into: &surface,
      context: PaintContext(clip: surface.bounds),
      resources: &resources
    )

    #expect(node.role == .dialog)
    #expect(surface[.zero].styleID != surface[CellPoint(x: 5, y: 2)].styleID)
    #expect(dialog.graphBody.first?.hitTest.modalScope == "confirm")
  }

  @Test
  @MainActor
  func `Toast paints its panel and semantic accent rail`() throws {
    var surface = Surface(size: CellSize(width: 20, height: 4))
    var resources = ControlRenderResources()
    let toast = Toast(id: "saved", message: "Saved", createdAt: .zero, kind: .success)

    let node = try toast.paint(
      into: &surface,
      context: PaintContext(clip: surface.bounds),
      resources: &resources
    )
    let frame = try #require(node.frame)

    #expect(node.role == .status)
    #expect(surface[frame.origin].styleID != surface[frame.origin.offsetBy(dx: 1)].styleID)
  }

  @Test
  @MainActor
  func `status pill resolves semantic tones and supports bare presentation`() throws {
    let theme = try SemanticTheme.standard.resolve(scheme: .dark)
    let pill = StatusPill(text: "Ready", tone: .success, theme: theme)
    let bare = StatusPill(text: "Ready", tone: .success, theme: theme, presentation: .bare)
    var resources = ControlRenderResources()
    var pillSurface = Surface(size: CellSize(width: 7, height: 1))
    var bareSurface = Surface(size: CellSize(width: 5, height: 1))

    _ = try pill.paint(
      into: &pillSurface,
      context: PaintContext(clip: pillSurface.bounds),
      resources: &resources
    )
    _ = try bare.paint(
      into: &bareSurface,
      context: PaintContext(clip: bareSurface.bounds),
      resources: &resources
    )

    #expect(pill.sizeThatFits(.unspecified) == CellSize(width: 7, height: 1))
    #expect(bare.sizeThatFits(.unspecified) == CellSize(width: 5, height: 1))
    #expect(pill.style.background == .rgba(theme[.success]))
    #expect(bare.style == CellStyle(foreground: .rgba(theme[.success])))
    #expect(renderedText(in: pillSurface, resources: resources) == " Ready ")
    #expect(renderedText(in: bareSurface, resources: resources) == "Ready")
  }

  @Test
  @MainActor
  func `status pill legacy initializer keeps padded rendering`() throws {
    let style = CellStyle(foreground: .rgba(.white), background: .rgba(.black), attributes: .bold)
    let pill = StatusPill(text: "Old", style: style, kind: .warning)
    var resources = ControlRenderResources()
    var surface = Surface(size: CellSize(width: 5, height: 1))

    let node = try pill.paint(
      into: &surface,
      context: PaintContext(clip: surface.bounds),
      resources: &resources
    )

    #expect(pill.presentation == .pill)
    #expect(pill.sizeThatFits(.unspecified) == CellSize(width: 5, height: 1))
    #expect(renderedText(in: surface, resources: resources) == " Old ")
    #expect(resources.styles.value(for: surface[.zero].styleID) == style)
    #expect(node.value == "warning")
  }

  @Test(arguments: [
    (StatusKind.neutral, SemanticColorRole.secondary, ColorScheme.light),
    (StatusKind.info, SemanticColorRole.info, ColorScheme.light),
    (StatusKind.success, SemanticColorRole.success, ColorScheme.light),
    (StatusKind.warning, SemanticColorRole.warning, ColorScheme.light),
    (StatusKind.error, SemanticColorRole.error, ColorScheme.light),
    (StatusKind.neutral, SemanticColorRole.secondary, ColorScheme.dark),
    (StatusKind.info, SemanticColorRole.info, ColorScheme.dark),
    (StatusKind.success, SemanticColorRole.success, ColorScheme.dark),
    (StatusKind.warning, SemanticColorRole.warning, ColorScheme.dark),
    (StatusKind.error, SemanticColorRole.error, ColorScheme.dark)
  ])
  func `status pill maps every tone to its semantic color`(
    tone: StatusPillTone,
    role: SemanticColorRole,
    scheme: ColorScheme
  ) throws {
    let theme = try SemanticTheme.standard.resolve(scheme: scheme)
    let pill = try StatusPill(text: "State", tone: tone, theme: SemanticTheme.standard, scheme: scheme)

    #expect(pill.tone == tone)
    #expect(pill.style.background == .rgba(theme[role]))
  }

  @Test
  func `status pill updates theme style after tone and presentation changes`() throws {
    let theme = try SemanticTheme.standard.resolve(scheme: .light)
    var pill = StatusPill(text: "State", tone: .success, theme: theme)

    pill.tone = .error
    #expect(pill.style.background == .rgba(theme[.error]))

    pill.presentation = .bare
    #expect(pill.style == CellStyle(foreground: .rgba(theme[.error])))
  }
}

private func renderedText(in surface: Surface, resources: ControlRenderResources) -> String {
  (0 ..< surface.size.width).compactMap { x -> String? in
    let cell = surface[CellPoint(x: x, y: 0)]
    guard cell.isContinuation == false else { return nil }
    return resources.graphemes.value(for: cell.graphemeID)
  }.joined()
}
