/// A deterministic one-line progress indicator.
public struct ProgressBar: View, SemanticRenderable, ControlSemanticActionHandler {
  /// The semantic identifier.
  public let id: SemanticID
  /// The accessibility label.
  public var label: String
  /// The filled-cell style.
  public var filledStyle: CellStyle
  /// The empty-cell style.
  public var emptyStyle: CellStyle

  private let readValue: @MainActor @Sendable () -> Double
  private let writeValue: (@MainActor @Sendable (Double) -> Void)?
  private let adjustmentStep: Double

  /// Creates a read-only progress bar.
  public init(
    value: Double,
    id: SemanticID = "progress",
    label: String = "Progress",
    filledStyle: CellStyle = .default,
    emptyStyle: CellStyle = .default
  ) {
    self.id = id
    self.label = label
    self.filledStyle = filledStyle
    self.emptyStyle = emptyStyle
    self.readValue = { value }
    self.writeValue = nil
    self.adjustmentStep = 0
  }

  /// Creates an adjustable progress bar.
  public init(
    value: Binding<Double>,
    id: SemanticID = "progress",
    label: String = "Progress",
    adjustmentStep: Double = 0.05,
    filledStyle: CellStyle = .default,
    emptyStyle: CellStyle = .default
  ) {
    precondition(adjustmentStep > 0, "The progress adjustment step must be positive.")
    self.id = id
    self.label = label
    self.filledStyle = filledStyle
    self.emptyStyle = emptyStyle
    self.readValue = { value.wrappedValue }
    self.writeValue = { value.wrappedValue = $0 }
    self.adjustmentStep = adjustmentStep
  }

  /// The primitive node descriptor.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .paint)]
  }

  /// Returns a one-line size that uses the proposed width.
  @MainActor
  public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    CellSize(width: proposal.width ?? 10, height: min(1, proposal.height ?? 1))
  }

  /// Paints the progress cells and returns their semantic node.
  @MainActor
  public func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let value = normalizedValue
    let width = context.frameSize.width
    let filledCount = Int((Double(width) * value).rounded(.down))
    for index in 0 ..< width {
      let point = context.origin.offsetBy(dx: index, dy: 0)
      guard context.clip.contains(point), surface.bounds.contains(point) else { continue }
      let isFilled = index < filledCount
      let graphemeID = try resources.graphemes.intern(isFilled ? "━" : "─")
      let styleID = try resources.styles.intern(isFilled ? filledStyle : emptyStyle)
      _ = try surface.write(graphemeID: graphemeID, at: point, styleID: styleID, clip: context.clip)
    }
    return SemanticNode(
      id: id,
      role: .progressIndicator,
      label: label,
      value: Self.percentDescription(value),
      actions: writeValue == nil ? [] : [.increment, .decrement],
      frame: CellRect(
        origin: context.origin,
        size: CellSize(width: width, height: min(1, context.frameSize.height))
      )
    )
  }

  /// Handles semantic increment and decrement actions.
  @MainActor
  public func handleSemanticAction(_ action: SemanticAction) -> Bool {
    guard let writeValue else { return false }
    switch action {
    case .increment:
      writeValue(min(1, normalizedValue + adjustmentStep))
    case .decrement:
      writeValue(max(0, normalizedValue - adjustmentStep))
    default:
      return false
    }
    return true
  }

  @MainActor
  private var normalizedValue: Double {
    let value = readValue()
    guard value.isNaN == false else { return 0 }
    return min(1, max(0, value))
  }

  private static func percentDescription(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}
