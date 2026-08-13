import TUIFoundation

public protocol PaintEnvironmentKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

public struct PaintEnvironmentValues: @unchecked Sendable, Hashable {
    private final class Resolver: @unchecked Sendable {
        let resolve: @Sendable (ObjectIdentifier) -> (any Sendable)?

        init(_ resolve: @escaping @Sendable (ObjectIdentifier) -> (any Sendable)?) {
            self.resolve = resolve
        }
    }

    private let resolver: Resolver?

    public init() {
        resolver = nil
    }

    public init(resolver: @escaping @Sendable (ObjectIdentifier) -> (any Sendable)?) {
        self.resolver = Resolver(resolver)
    }

    public subscript<Key: PaintEnvironmentKey>(key: Key.Type) -> Key.Value {
        resolver?.resolve(ObjectIdentifier(key)) as? Key.Value ?? Key.defaultValue
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.resolver === rhs.resolver
    }

    public func hash(into hasher: inout Hasher) {
        resolver.map(ObjectIdentifier.init).map { hasher.combine($0) }
    }
}

public struct PaintContext: Sendable, Hashable {
    public var origin: CellPoint
    public var clip: CellRect
    public var opacity: Double
    public var zIndex: Int
    public var environment: PaintEnvironmentValues

    #if DEBUG
    private var clipScope = ClipScopeTracker()
    #endif

    public init(
        origin: CellPoint = .zero,
        clip: CellRect,
        opacity: Double = 1,
        zIndex: Int = 0,
        environment: PaintEnvironmentValues = PaintEnvironmentValues()
    ) {
        self.origin = origin
        self.clip = clip
        self.opacity = Swift.min(1, Swift.max(0, opacity))
        self.zIndex = zIndex
        self.environment = environment
    }

    public func translated(by offset: CellPoint) -> PaintContext {
        var context = PaintContext(
            origin: origin.offsetBy(dx: offset.x, dy: offset.y),
            clip: clip,
            opacity: opacity,
            zIndex: zIndex,
            environment: environment
        )
        #if DEBUG
        context.clipScope = clipScope
        #endif
        return context
    }

    public func clipped(to localRect: CellRect) -> PaintContext? {
        let absoluteRect = localRect.offsetBy(dx: origin.x, dy: origin.y)
        guard let intersection = clip.intersection(absoluteRect) else { return nil }
        var context = PaintContext(
            origin: origin,
            clip: intersection,
            opacity: opacity,
            zIndex: zIndex,
            environment: environment
        )
        #if DEBUG
        context.clipScope = clipScope
        #endif
        return context
    }

    public func applyingOpacity(_ value: Double) -> PaintContext {
        multiplyingOpacity(value)
    }

    public func multiplyingOpacity(_ value: Double) -> PaintContext {
        var context = PaintContext(
            origin: origin,
            clip: clip,
            opacity: opacity * value,
            zIndex: zIndex,
            environment: environment
        )
        #if DEBUG
        context.clipScope = clipScope
        #endif
        return context
    }

    public func withZIndex(_ value: Int) -> PaintContext {
        var context = PaintContext(
            origin: origin,
            clip: clip,
            opacity: opacity,
            zIndex: value,
            environment: environment
        )
        #if DEBUG
        context.clipScope = clipScope
        #endif
        return context
    }

    public func resolve(_ localPoint: CellPoint) -> CellPoint? {
        let point = origin.offsetBy(dx: localPoint.x, dy: localPoint.y)
        return clip.contains(point) ? point : nil
    }

    public static func == (lhs: PaintContext, rhs: PaintContext) -> Bool {
        lhs.origin == rhs.origin
            && lhs.clip == rhs.clip
            && lhs.opacity == rhs.opacity
            && lhs.zIndex == rhs.zIndex
            && lhs.environment == rhs.environment
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin)
        hasher.combine(clip)
        hasher.combine(opacity)
        hasher.combine(zIndex)
        hasher.combine(environment)
    }

    #if DEBUG
    package func withClipScope<Result>(
        origin: CellPoint,
        clip: CellRect,
        _ body: (PaintContext) throws -> Result
    ) rethrows -> Result {
        let entryDepth = clipScope.depth
        clipScope.depth += 1
        defer {
            clipScope.depth -= 1
            assert(clipScope.depth == entryDepth, "Unbalanced paint clip scope.")
        }
        var context = PaintContext(
            origin: origin,
            clip: clip,
            opacity: opacity,
            zIndex: zIndex,
            environment: environment
        )
        context.clipScope = clipScope
        return try body(context)
    }

    package var debugClipScopeDepth: Int { clipScope.depth }
    #endif
}

#if DEBUG
private final class ClipScopeTracker: @unchecked Sendable {
    var depth = 0
}
#endif
