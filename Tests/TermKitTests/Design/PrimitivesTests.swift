import Testing

@testable import TermKit

struct PrimitivesTests {
    @Test("Surface leaf retains its primitive and includes padding in measurement")
    @MainActor
    func surfaceLeafDescriptorAndSizing() throws {
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

    @Test("Metadata hides low-priority fields before primary content")
    func metadataProgressiveHiding() {
        let line = MetadataLine(
            fields: [
                MetadataField("main", priority: 10),
                MetadataField("branch", priority: 5),
                MetadataField("12:45", priority: 0),
            ],
            style: .default
        )

        #expect(line.text(in: 21) == "main · branch · 12:45")
        #expect(line.text(in: 13) == "main · branch")
        #expect(line.text(in: 4) == "main")
        #expect(line.text(in: 3) == "mai")
    }

    @Test("Metadata uses terminal cell width for progressive hiding and clipping")
    func metadataUnicodeWidth() {
        let line = MetadataLine(
            fields: [
                MetadataField("界", priority: 10),
                MetadataField("x", priority: 0),
            ],
            style: .default,
            separator: " "
        )

        #expect(line.text(in: 4) == "界 x")
        #expect(line.text(in: 2) == "界")
        #expect(line.text(in: 1) == "�")
    }

    @Test("Reduced motion uses the static activity fallback and no schedule")
    func reducedMotionActivity() {
        let indicator = ActivityIndicator(
            sample: TimelineSample(instant: TimeInstant(nanoseconds: 250_000_000), reduceMotion: true),
            frames: ["a", "b"],
            interval: .milliseconds(100)
        )

        #expect(indicator.text == "...")
        #expect(indicator.schedule == nil)
    }

    @Test("Timeline sample selects an activity frame without owning a timer")
    func activityTimelineSample() {
        let indicator = ActivityIndicator(
            sample: TimelineSample(instant: TimeInstant(nanoseconds: 250_000_000)),
            frames: ["a", "b", "c"],
            interval: .milliseconds(100)
        )

        #expect(indicator.text == "c")
        #expect(indicator.schedule?.cadence == .milliseconds(100))
    }

    @Test("Activity view adapter uses the standard timeline")
    @MainActor
    func activityViewAdapter() throws {
        let descriptor = try #require(
            ActivityIndicatorView(frames: ["a", "b"], interval: .milliseconds(100))
                .graphBody.first
        )

        #expect(descriptor.primitive == nil)
        #expect(descriptor.dirtyOnUpdate == .paint)
    }

    @Test("Dialog width is constrained by terminal margins")
    func dialogWidths() {
        let dialog = DialogSurface(id: "preferences", title: "Preferences", content: "body", preferredWidth: .wide)

        #expect(dialog.frame(in: CellSize(width: 140, height: 40), contentHeight: 20).width == 116)
        #expect(dialog.frame(in: CellSize(width: 70, height: 40), contentHeight: 20).width == 66)
    }

    @Test("Toast wrapping uses terminal cell width")
    func toastUnicodeWrapping() {
        let toast = Toast(id: "unicode", message: "A界B", createdAt: .zero)

        #expect(toast.wrappedLines(width: 2) == ["A", "界", "B"])
    }

    @Test("Toast fade is configurable and static expiry has a callback contract")
    @MainActor
    func toastTimelineContract() {
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

    @Test("Elevation changes the painted surface depth")
    @MainActor
    func surfaceElevationPaint() throws {
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

    @Test("Dialog paints a backdrop and centered panel")
    @MainActor
    func dialogPaint() throws {
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

    @Test("Toast paints its panel and semantic accent rail")
    @MainActor
    func toastPaint() throws {
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
}
