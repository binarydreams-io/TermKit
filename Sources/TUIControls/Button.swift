import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public struct Button: SemanticRenderable, ControlActivatable, TUIViewGraph.View {
    public let id: SemanticID
    public var label: Text
    public var isEnabled: Bool
    public var isFocused: Bool
    public var action: @MainActor @Sendable () -> Void

    public init(
        _ title: String,
        id: SemanticID = "button",
        style: CellStyle = .default,
        isEnabled: Bool = true,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        label = Text(title, id: SemanticID(rawValue: "\(id.rawValue)-label"), style: style)
        self.isEnabled = isEnabled
        isFocused = false
        self.action = action
    }

    public init(
        id: SemanticID,
        label: Text,
        isEnabled: Bool = true,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.label = label
        self.isEnabled = isEnabled
        isFocused = false
        self.action = action
    }

    @MainActor
    @discardableResult
    public func activate() -> Bool {
        guard isEnabled else { return false }
        action()
        return true
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        label.sizeThatFits(proposal)
    }

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

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let labelNode = try label.paint(into: &surface, context: context, resources: &resources)
        var state: SemanticState = []
        if isEnabled == false { state.insert(.disabled) }
        if isFocused { state.insert(.focused) }
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
