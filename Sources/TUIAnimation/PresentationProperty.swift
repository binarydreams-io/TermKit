import TUIViewGraph

public struct PresentationProperty<Value: VectorArithmetic>: Sendable, Hashable {
    public let key: AnimationPropertyKey
    public let dirtyFlags: DirtyFlags

    public init(key: AnimationPropertyKey, dirtyFlags: DirtyFlags) {
        precondition(
            dirtyFlags == .paint || dirtyFlags == .layout,
            "A presentation property must invalidate paint or layout."
        )
        self.key = key
        self.dirtyFlags = dirtyFlags
    }
}

package func presentationValueIsFinite<Value: VectorArithmetic>(_ value: Value) -> Bool {
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

public enum PresentationProperties {
    public static let foregroundColor = PresentationProperty<LinearRGBA>(key: "foreground.color", dirtyFlags: .paint)
    public static let backgroundColor = PresentationProperty<LinearRGBA>(key: "background.color", dirtyFlags: .paint)
    public static let borderColor = PresentationProperty<LinearRGBA>(key: "border.color", dirtyFlags: .paint)
    public static let opacity = PresentationProperty<Double>(key: "opacity", dirtyFlags: .paint)
    public static let offset = PresentationProperty<CellVector>(key: "offset", dirtyFlags: .layout)
    public static let frameWidth = PresentationProperty<Double>(key: "frame.width", dirtyFlags: .layout)
    public static let frameHeight = PresentationProperty<Double>(key: "frame.height", dirtyFlags: .layout)
    public static let padding = PresentationProperty<FloatingEdgeInsets>(key: "padding", dirtyFlags: .layout)
    public static let spacing = PresentationProperty<Double>(key: "spacing", dirtyFlags: .layout)
    public static let clipInsets = PresentationProperty<FloatingEdgeInsets>(key: "clip.insets", dirtyFlags: .layout)
    public static let clipReveal = PresentationProperty<Double>(key: "clip.reveal", dirtyFlags: .layout)
    public static let selectionHighlight = PresentationProperty<LinearRGBA>(key: "selection.highlight", dirtyFlags: .paint)
    public static let focusHighlight = PresentationProperty<LinearRGBA>(key: "focus.highlight", dirtyFlags: .paint)
    public static let scrollPosition = PresentationProperty<CellVector>(key: "scroll.position", dirtyFlags: .layout)
    public static let transitionVisibility = PresentationProperty<Double>(key: "transition.visibility", dirtyFlags: .paint)
}

public extension PresentationProperty where Value == LinearRGBA {
    static var foregroundColor: Self { PresentationProperties.foregroundColor }
    static var backgroundColor: Self { PresentationProperties.backgroundColor }
    static var borderColor: Self { PresentationProperties.borderColor }
    static var selectionHighlight: Self { PresentationProperties.selectionHighlight }
    static var focusHighlight: Self { PresentationProperties.focusHighlight }
}

public extension PresentationProperty where Value == Double {
    static var opacity: Self { PresentationProperties.opacity }
    static var frameWidth: Self { PresentationProperties.frameWidth }
    static var frameHeight: Self { PresentationProperties.frameHeight }
    static var spacing: Self { PresentationProperties.spacing }
    static var clipReveal: Self { PresentationProperties.clipReveal }
    static var transitionVisibility: Self { PresentationProperties.transitionVisibility }
}

public extension PresentationProperty where Value == CellVector {
    static var offset: Self { PresentationProperties.offset }
    static var scrollPosition: Self { PresentationProperties.scrollPosition }
}

public extension PresentationProperty where Value == FloatingEdgeInsets {
    static var padding: Self { PresentationProperties.padding }
    static var clipInsets: Self { PresentationProperties.clipInsets }
}
