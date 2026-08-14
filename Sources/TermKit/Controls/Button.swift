/// A text-labeled control that invokes an action when activated.
public struct Button: SemanticRenderable, ControlActivatable, View {
  /// The semantic identifier.
  public let id: SemanticID
  /// The displayed text label.
  public var label: Text
  /// A value that indicates whether activation is allowed.
  public var isEnabled: Bool
  /// A value that indicates whether the button has focus.
  public var isFocused: Bool
  /// The action invoked by activation.
  public var action: @MainActor @Sendable () -> Void

  /// Creates a button from a title and style.
  public init(
    _ title: String,
    id: SemanticID = "button",
    style: CellStyle = .default,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.label = Text(title, id: SemanticID(rawValue: "\(id.rawValue)-label"), style: style)
    self.isEnabled = isEnabled
    self.isFocused = false
    self.action = action
  }

  /// Creates a button from a text label.
  public init(
    id: SemanticID,
    label: Text,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.label = label
    self.isEnabled = isEnabled
    self.isFocused = false
    self.action = action
  }

  /// Invokes the action when the button is enabled.
  /// - Complexity: O(1), excluding the action.
  @MainActor
  @discardableResult
  public func activate() -> Bool {
    guard isEnabled else { return false }
    action()
    return true
  }

  /// Returns the label's fitted size.
  /// - Complexity: O(n), where n is the label length.
  public nonisolated func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    label.sizeThatFits(proposal)
  }

  /// The node descriptor for the button.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [
      NodeDescriptor(
        type: Self.self,
        primitive: self,
        focus: FocusMetadata(isFocusable: isEnabled),
        hitTest: HitTestMetadata(isEnabled: isEnabled),
        dirtyOnUpdate: .layout
      )
    ]
  }

  /// Paints the button and returns its semantic node.
  /// - Complexity: O(n), where n is the label length.
  public nonisolated func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let labelNode = try label.paint(into: &surface, context: context, resources: &resources)
    var state: SemanticState = []
    if isEnabled == false {
      state.insert(.disabled)
    }
    if isFocused {
      state.insert(.focused)
    }
    return SemanticNode(
      id: id,
      role: .button,
      label: label.plainText,
      state: state,
      actions: isEnabled ? [.activate, .focus] : [],
      frame: labelNode.frame
    )
  }
}
