/// A stable identifier for a semantic node.
public struct SemanticID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
  /// The identifier's string value.
  public var rawValue: String

  /// Creates a semantic identifier from a nonempty string.
  public init(rawValue: String) {
    precondition(rawValue.isEmpty == false, "A semantic identifier must not be empty.")
    self.rawValue = rawValue
  }

  /// Creates a semantic identifier from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

/// The accessibility role of a semantic node.
public enum SemanticRole: String, Sendable, Hashable {
  /// Static text.
  case text
  /// An activatable button.
  case button
  /// An editable text field.
  case textEditor
  /// A list container.
  case list
  /// An item in a list.
  case listItem
  /// A scrollable container.
  case scrollView
  /// A dialog container.
  case dialog
  /// A menu container.
  case menu
  /// An item in a menu.
  case menuItem
  /// A generic group.
  case group
  /// Status information.
  case status
  /// A progress indicator.
  case progressIndicator
  /// A raster image.
  case image
}

/// State flags associated with a semantic node.
public struct SemanticState: OptionSet, Sendable, Hashable {
  /// The option-set bit field.
  public let rawValue: UInt16

  /// Creates semantic state from a bit field.
  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  /// The node is selected.
  public static let selected = SemanticState(rawValue: 1 << 0)
  /// The node is the current navigation item.
  public static let current = SemanticState(rawValue: 1 << 1)
  /// The node is disabled.
  public static let disabled = SemanticState(rawValue: 1 << 2)
  /// The node has focus.
  public static let focused = SemanticState(rawValue: 1 << 3)
  /// The node is expanded.
  public static let expanded = SemanticState(rawValue: 1 << 4)
  /// The node is busy.
  public static let busy = SemanticState(rawValue: 1 << 5)
  /// The node is checked.
  public static let checked = SemanticState(rawValue: 1 << 6)
  /// The pointer is over the node.
  public static let hovered = SemanticState(rawValue: 1 << 7)
  /// The node is modal.
  public static let modal = SemanticState(rawValue: 1 << 8)
}

/// An action supported by a semantic node.
public enum SemanticAction: String, Sendable, Hashable {
  /// Activates the node.
  case activate
  /// Moves focus to the node.
  case focus
  /// Dismisses the node.
  case dismiss
  /// Submits the node's value.
  case submit
  /// Increases the node's value.
  case increment
  /// Decreases the node's value.
  case decrement
  /// Sets the node's value.
  case setValue
  /// Scrolls the node forward.
  case scrollForward
  /// Scrolls the node backward.
  case scrollBackward
}

/// A node in the semantic representation of rendered controls.
public struct SemanticNode: Sendable, Hashable {
  /// The node identifier.
  public var id: SemanticID
  /// The node role.
  public var role: SemanticRole
  /// The human-readable label.
  public var label: String
  /// The optional human-readable value.
  public var value: String?
  /// The node state flags.
  public var state: SemanticState
  /// The actions supported by the node.
  public var actions: Set<SemanticAction>
  /// The rendered frame, if available.
  public var frame: CellRect?
  /// The child semantic nodes.
  public var children: [SemanticNode]

  /// Creates a semantic node.
  public init(
    id: SemanticID,
    role: SemanticRole,
    label: String = "",
    value: String? = nil,
    state: SemanticState = [],
    actions: Set<SemanticAction> = [],
    frame: CellRect? = nil,
    children: [SemanticNode] = []
  ) {
    self.id = id
    self.role = role
    self.label = label
    self.value = value
    self.state = state
    self.actions = actions
    self.frame = frame
    self.children = children
  }

  /// Finds a descendant or this node by identifier.
  /// - Complexity: O(n), where n is the subtree node count.
  public func node(withID id: SemanticID) -> SemanticNode? {
    if self.id == id {
      return self
    }
    for child in children {
      if let match = child.node(withID: id) {
        return match
      }
    }
    return nil
  }

  /// This node and its descendants in depth-first order.
  /// - Complexity: O(n), where n is the subtree node count.
  public var depthFirstNodes: [SemanticNode] {
    [self] + children.flatMap(\.depthFirstNodes)
  }
}

/// A forest of semantic nodes.
public struct SemanticTree: Sendable, Hashable {
  /// The root semantic nodes.
  public var roots: [SemanticNode]

  /// Creates a semantic tree.
  public init(roots: [SemanticNode] = []) {
    self.roots = roots
  }

  /// Finds a node by identifier.
  /// - Complexity: O(n), where n is the tree node count.
  public func node(withID id: SemanticID) -> SemanticNode? {
    roots.lazy.compactMap { $0.node(withID: id) }.first
  }

  /// Returns all nodes with a role.
  /// - Complexity: O(n), where n is the tree node count.
  public func nodes(withRole role: SemanticRole) -> [SemanticNode] {
    roots.flatMap(\.depthFirstNodes).filter { $0.role == role }
  }
}
