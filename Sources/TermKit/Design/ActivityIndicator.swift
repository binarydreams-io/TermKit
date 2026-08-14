/// A sampled instant and its animation environment.
public struct TimelineSample: Sendable, Hashable {
  /// The sampled timeline instant.
  public var instant: TimeInstant
  /// A Boolean value that indicates whether animations are enabled.
  public var areAnimationsEnabled: Bool
  /// A Boolean value that indicates whether reduced motion is requested.
  public var isReducedMotionEnabled: Bool

  /// Creates a timeline sample.
  public init(instant: TimeInstant, animationsEnabled: Bool = true, reduceMotion: Bool = false) {
    self.instant = instant
    self.areAnimationsEnabled = animationsEnabled
    self.isReducedMotionEnabled = reduceMotion
  }
}

/// A sampled, semantically labeled activity indicator.
public struct ActivityIndicator: SemanticRenderable, Hashable {
  /// The semantic identifier.
  public var id: SemanticID
  /// The animation frames.
  public var frames: [String]
  /// The duration of each frame.
  public var interval: TimeSpan
  /// The text shown when animation is unavailable.
  public var staticText: String
  /// The cell style.
  public var style: CellStyle
  /// The timeline sample used to select a frame.
  public var sample: TimelineSample

  /// Creates an activity indicator for a timeline sample.
  public init(
    sample: TimelineSample,
    id: SemanticID = "activity",
    frames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    interval: TimeSpan = .milliseconds(80),
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
    self.sample = sample
  }

  /// The frame or static text for the current sample.
  /// - Complexity: O(1).
  public var text: String {
    guard sample.areAnimationsEnabled, sample.isReducedMotionEnabled == false else { return staticText }
    let ticks = max(0, sample.instant.nanoseconds) / interval.nanoseconds
    return frames[Int(ticks % Int64(frames.count))]
  }

  /// The periodic schedule required for animation, or `nil` for static output.
  /// - Complexity: O(1).
  public var schedule: TimelineSchedule? {
    sample.areAnimationsEnabled && sample.isReducedMotionEnabled == false
      ? .periodic(from: .zero, by: interval)
      : nil
  }

  /// Returns the indicator size constrained by a proposal.
  /// - Complexity: O(*n*), where *n* is the frame's grapheme count.
  public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    let width = TerminalWidth.width(of: text)
    return CellSize(width: min(width, proposal.width ?? width), height: min(1, proposal.height ?? 1))
  }

  /// Paints the current frame and returns its semantic node.
  /// - Complexity: O(*n*), where *n* is the frame's grapheme count.
  public func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let frame = try SurfaceTextPainter.paint([StyledRun(text, style: style)], into: &surface, context: context, resources: &resources)
    return SemanticNode(id: id, role: .progressIndicator, label: "Activity", state: .busy, frame: frame)
  }
}

/// A timeline-driven activity indicator view.
public struct ActivityIndicatorView: View {
  /// The semantic identifier.
  public var id: SemanticID
  /// The animation frames.
  public var frames: [String]
  /// The duration of each frame.
  public var interval: TimeSpan
  /// The text shown when animation is unavailable.
  public var staticText: String
  /// The cell style.
  public var style: CellStyle

  /// Creates a timeline-driven activity indicator.
  public init(
    id: SemanticID = "activity",
    frames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    interval: TimeSpan = .milliseconds(80),
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

  /// The timeline node descriptors for the indicator.
  public var graphBody: [NodeDescriptor] {
    TimelineView(.periodic(from: .zero, by: interval)) { context in
      ActivityIndicator(
        sample: TimelineSample(
          instant: context.instant,
          animationsEnabled: context.areAnimationsEnabled,
          reduceMotion: context.isReducedMotionEnabled
        ),
        id: id,
        frames: frames,
        interval: interval,
        staticText: staticText,
        style: style
      )
    }.graphBody
  }
}

extension ActivityIndicator: View {
  /// The primitive node descriptor for the sampled indicator.
  public var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
  }
}
