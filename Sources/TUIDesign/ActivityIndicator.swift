import TUIAnimation
import TUIControls
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public struct TimelineSample: Sendable, Hashable {
    public var instant: TimeInstant
    public var animationsEnabled: Bool
    public var reduceMotion: Bool

    public init(instant: TimeInstant, animationsEnabled: Bool = true, reduceMotion: Bool = false) {
        self.instant = instant
        self.animationsEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
    }
}

public struct ActivityIndicator: SemanticRenderable, Hashable {
    public var id: SemanticID
    public var frames: [String]
    public var interval: TUIDuration
    public var staticText: String
    public var style: CellStyle
    public var sample: TimelineSample

    public init(
        id: SemanticID = "activity",
        frames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
        interval: TUIDuration = .milliseconds(80),
        staticText: String = "...",
        style: CellStyle = .default,
        sample: TimelineSample
    ) {
        precondition(frames.isEmpty == false, "An activity indicator requires at least one frame.")
        precondition(interval > .zero, "An activity interval must be positive.")
        self.id = id
        self.frames = frames
        self.interval = interval
        self.staticText = staticText
        self.style = style
        self.sample = sample
    }

    public var text: String {
        guard sample.animationsEnabled, sample.reduceMotion == false else { return staticText }
        let ticks = max(0, sample.instant.nanoseconds) / interval.nanoseconds
        return frames[Int(ticks % Int64(frames.count))]
    }

    public var schedule: TimelineSchedule? {
        sample.animationsEnabled && sample.reduceMotion == false
            ? .periodic(from: .zero, by: interval)
            : nil
    }

    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = TerminalWidth.width(of: text)
        return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
    }

    public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let frame = try SurfaceTextPainter.paint([StyledRun(text, style: style)], into: &surface, context: context, resources: &resources)
        return SemanticNode(id: id, role: .progressIndicator, label: "Activity", state: .busy, frame: frame)
    }
}

public struct ActivityIndicatorView: View {
    public var id: SemanticID
    public var frames: [String]
    public var interval: TUIDuration
    public var staticText: String
    public var style: CellStyle

    public init(
        id: SemanticID = "activity",
        frames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
        interval: TUIDuration = .milliseconds(80),
        staticText: String = "...",
        style: CellStyle = .default
    ) {
        precondition(frames.isEmpty == false, "An activity indicator requires at least one frame.")
        precondition(interval > .zero, "An activity interval must be positive.")
        self.id = id
        self.frames = frames
        self.interval = interval
        self.staticText = staticText
        self.style = style
    }

    public var graphBody: [NodeDescriptor] {
        TimelineView(.periodic(from: .zero, by: interval)) { context in
            ActivityIndicator(
                id: id,
                frames: frames,
                interval: interval,
                staticText: staticText,
                style: style,
                sample: TimelineSample(
                    instant: context.instant,
                    animationsEnabled: context.animationsEnabled,
                    reduceMotion: context.reduceMotion
                )
            )
        }.graphBody
    }
}

extension ActivityIndicator: View {
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }
}
