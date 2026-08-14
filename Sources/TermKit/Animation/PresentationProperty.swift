/// A typed animation property and its invalidation category.
public struct PresentationProperty<Value: VectorArithmetic>: Sendable, Hashable {
  /// The stable property key.
  public let key: AnimationPropertyKey
  /// The rendering stage invalidated by value changes.
  public let dirtyFlags: DirtyFlags

  /// Creates a typed presentation property.
  public init(key: AnimationPropertyKey, dirtyFlags: DirtyFlags) {
    precondition(
      dirtyFlags == .paint || dirtyFlags == .layout,
      "A presentation property must invalidate paint or layout."
    )
    self.key = key
    self.dirtyFlags = dirtyFlags
  }
}

func presentationValueIsFinite(_ value: some VectorArithmetic) -> Bool {
  switch value {
  case let value as Double:
    value.isFinite
  case let value as Float:
    value.isFinite
  case let value as LinearRGBA:
    value.red.isFinite && value.green.isFinite && value.blue.isFinite && value.alpha.isFinite
  case let value as CellVector:
    value.x.isFinite && value.y.isFinite
  case let value as CellDimensions:
    value.width.isFinite && value.height.isFinite
  case let value as FloatingEdgeInsets:
    value.top.isFinite && value.leading.isFinite && value.bottom.isFinite && value.trailing.isFinite
  default:
    true
  }
}

/// Standard presentation properties used by controls and views.
public enum PresentationProperties {
  /// The foreground color property.
  public static let foregroundColor = PresentationProperty<LinearRGBA>(key: "foreground.color", dirtyFlags: .paint)
  /// The background color property.
  public static let backgroundColor = PresentationProperty<LinearRGBA>(key: "background.color", dirtyFlags: .paint)
  /// The border color property.
  public static let borderColor = PresentationProperty<LinearRGBA>(key: "border.color", dirtyFlags: .paint)
  /// The opacity property.
  public static let opacity = PresentationProperty<Double>(key: "opacity", dirtyFlags: .paint)
  /// The cell offset property.
  public static let offset = PresentationProperty<CellVector>(key: "offset", dirtyFlags: .layout)
  /// The frame width property.
  public static let frameWidth = PresentationProperty<Double>(key: "frame.width", dirtyFlags: .layout)
  /// The frame height property.
  public static let frameHeight = PresentationProperty<Double>(key: "frame.height", dirtyFlags: .layout)
  /// The edge padding property.
  public static let padding = PresentationProperty<FloatingEdgeInsets>(key: "padding", dirtyFlags: .layout)
  /// The spacing property.
  public static let spacing = PresentationProperty<Double>(key: "spacing", dirtyFlags: .layout)
  /// The clip inset property.
  public static let clipInsets = PresentationProperty<FloatingEdgeInsets>(key: "clip.insets", dirtyFlags: .layout)
  /// The clip reveal property.
  public static let clipReveal = PresentationProperty<Double>(key: "clip.reveal", dirtyFlags: .layout)
  /// The selection highlight color property.
  public static let selectionHighlight = PresentationProperty<LinearRGBA>(key: "selection.highlight", dirtyFlags: .paint)
  /// The focus highlight color property.
  public static let focusHighlight = PresentationProperty<LinearRGBA>(key: "focus.highlight", dirtyFlags: .paint)
  /// The scroll position property.
  public static let scrollPosition = PresentationProperty<CellVector>(key: "scroll.position", dirtyFlags: .layout)
  /// The transition visibility property.
  public static let transitionVisibility = PresentationProperty<Double>(key: "transition.visibility", dirtyFlags: .paint)
}

extension PresentationProperty where Value == LinearRGBA {
  /// The standard foreground color property.
  public static var foregroundColor: Self {
    PresentationProperties.foregroundColor
  }

  /// The standard background color property.
  public static var backgroundColor: Self {
    PresentationProperties.backgroundColor
  }

  /// The standard border color property.
  public static var borderColor: Self {
    PresentationProperties.borderColor
  }

  /// The standard selection highlight property.
  public static var selectionHighlight: Self {
    PresentationProperties.selectionHighlight
  }

  /// The standard focus highlight property.
  public static var focusHighlight: Self {
    PresentationProperties.focusHighlight
  }
}

extension PresentationProperty where Value == Double {
  /// The standard opacity property.
  public static var opacity: Self {
    PresentationProperties.opacity
  }

  /// The standard frame width property.
  public static var frameWidth: Self {
    PresentationProperties.frameWidth
  }

  /// The standard frame height property.
  public static var frameHeight: Self {
    PresentationProperties.frameHeight
  }

  /// The standard spacing property.
  public static var spacing: Self {
    PresentationProperties.spacing
  }

  /// The standard clip reveal property.
  public static var clipReveal: Self {
    PresentationProperties.clipReveal
  }

  /// The standard transition visibility property.
  public static var transitionVisibility: Self {
    PresentationProperties.transitionVisibility
  }
}

extension PresentationProperty where Value == CellVector {
  /// The standard cell offset property.
  public static var offset: Self {
    PresentationProperties.offset
  }

  /// The standard scroll position property.
  public static var scrollPosition: Self {
    PresentationProperties.scrollPosition
  }
}

extension PresentationProperty where Value == FloatingEdgeInsets {
  /// The standard padding property.
  public static var padding: Self {
    PresentationProperties.padding
  }

  /// The standard clip inset property.
  public static var clipInsets: Self {
    PresentationProperties.clipInsets
  }
}
