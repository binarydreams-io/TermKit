/// A key that defines a typed value in the paint environment.
public protocol PaintEnvironmentKey {
  /// The value type associated with the key.
  associatedtype Value: Sendable
  /// The value used when the environment does not contain the key.
  static var defaultValue: Value { get }
}

/// Type-safe values available during painting.
public struct PaintEnvironmentValues: Sendable, Hashable {
  private final class Resolver: Sendable {
    let resolve: @Sendable (ObjectIdentifier) -> (any Sendable)?

    init(_ resolve: @escaping @Sendable (ObjectIdentifier) -> (any Sendable)?) {
      self.resolve = resolve
    }
  }

  private let resolver: Resolver?

  /// Creates an environment that returns each key's default value.
  public init() {
    self.resolver = nil
  }

  /// Creates an environment backed by a type-identifier resolver.
  public init(resolver: @escaping @Sendable (_ identifier: ObjectIdentifier) -> (any Sendable)?) {
    self.resolver = Resolver(resolver)
  }

  /// Returns the value for an environment key.
  public subscript<Key: PaintEnvironmentKey>(key: Key.Type) -> Key.Value {
    resolver?.resolve(ObjectIdentifier(key)) as? Key.Value ?? Key.defaultValue
  }

  /// Returns whether two environments use the same resolver.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.resolver === rhs.resolver
  }

  /// Hashes the identity of the environment resolver.
  public func hash(into hasher: inout Hasher) {
    resolver.map(ObjectIdentifier.init).map { hasher.combine($0) }
  }
}

/// Position, clipping, opacity, depth, and environment state for painting.
public struct PaintContext: Sendable, Hashable {
  /// The absolute origin for local paint coordinates.
  public var origin: CellPoint
  /// The absolute clipping rectangle.
  public var clip: CellRect
  /// The normalized cumulative opacity.
  public var opacity: Double
  /// The paint order within the current stacking context.
  public var zIndex: Int
  /// The values available during painting.
  public var environment: PaintEnvironmentValues
  /// The complete layout size before clipping.
  public var frameSize: CellSize

  #if DEBUG
  private var clipScope = ClipScopeTracker()
  #endif

  /// Creates a paint context.
  public init(
    clip: CellRect,
    origin: CellPoint = .zero,
    opacity: Double = 1,
    zIndex: Int = 0,
    environment: PaintEnvironmentValues = PaintEnvironmentValues(),
    frameSize: CellSize? = nil
  ) {
    self.origin = origin
    self.clip = clip
    self.opacity = Swift.min(1, Swift.max(0, opacity))
    self.zIndex = zIndex
    self.environment = environment
    self.frameSize = frameSize ?? clip.size
  }

  /// Returns a context with an origin translated by a local offset.
  public func translated(by offset: CellPoint) -> PaintContext {
    var context = PaintContext(
      clip: clip,
      origin: origin.offsetBy(dx: offset.x, dy: offset.y),
      opacity: opacity,
      zIndex: zIndex,
      environment: environment,
      frameSize: frameSize
    )
    #if DEBUG
    context.clipScope = clipScope
    #endif
    return context
  }

  /// Returns a context clipped to a local rectangle, if the clip is nonempty.
  public func clipped(to localRect: CellRect) -> PaintContext? {
    let absoluteRect = localRect.offsetBy(dx: origin.x, dy: origin.y)
    guard let intersection = clip.intersection(absoluteRect) else { return nil }
    var context = PaintContext(
      clip: intersection,
      origin: origin,
      opacity: opacity,
      zIndex: zIndex,
      environment: environment,
      frameSize: frameSize
    )
    #if DEBUG
    context.clipScope = clipScope
    #endif
    return context
  }

  /// Returns a context with its opacity multiplied by a value.
  public func applyingOpacity(_ value: Double) -> PaintContext {
    multiplyingOpacity(value)
  }

  /// Returns a context with its opacity multiplied by a value.
  public func multiplyingOpacity(_ value: Double) -> PaintContext {
    var context = PaintContext(
      clip: clip,
      origin: origin,
      opacity: opacity * value,
      zIndex: zIndex,
      environment: environment,
      frameSize: frameSize
    )
    #if DEBUG
    context.clipScope = clipScope
    #endif
    return context
  }

  /// Returns a context with a different paint order.
  public func withZIndex(_ value: Int) -> PaintContext {
    var context = PaintContext(
      clip: clip,
      origin: origin,
      opacity: opacity,
      zIndex: value,
      environment: environment,
      frameSize: frameSize
    )
    #if DEBUG
    context.clipScope = clipScope
    #endif
    return context
  }

  /// Resolves a local point to an absolute point inside the clip.
  public func resolve(_ localPoint: CellPoint) -> CellPoint? {
    let point = origin.offsetBy(dx: localPoint.x, dy: localPoint.y)
    return clip.contains(point) ? point : nil
  }

  /// Returns whether two contexts contain equivalent public state.
  public static func == (lhs: PaintContext, rhs: PaintContext) -> Bool {
    lhs.origin == rhs.origin
      && lhs.clip == rhs.clip
      && lhs.opacity == rhs.opacity
      && lhs.zIndex == rhs.zIndex
      && lhs.environment == rhs.environment
      && lhs.frameSize == rhs.frameSize
  }

  /// Hashes the context's public state.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(origin)
    hasher.combine(clip)
    hasher.combine(opacity)
    hasher.combine(zIndex)
    hasher.combine(environment)
    hasher.combine(frameSize)
  }

  #if DEBUG
  func withClipScope<Result>(
    origin: CellPoint,
    clip: CellRect,
    _ body: (PaintContext) throws -> Result
  ) rethrows -> Result {
    let entryDepth = clipScope.increment()
    defer {
      assert(clipScope.decrement() == entryDepth, "Unbalanced paint clip scope.")
    }
    var context = PaintContext(
      clip: clip,
      origin: origin,
      opacity: opacity,
      zIndex: zIndex,
      environment: environment,
      frameSize: frameSize
    )
    context.clipScope = clipScope
    return try body(context)
  }

  var debugClipScopeDepth: Int {
    clipScope.depth
  }
  #endif
}

#if DEBUG
private final class ClipScopeTracker: Sendable {
  private let state = LockedState(0)

  var depth: Int {
    state.withLock { $0 }
  }

  func increment() -> Int {
    state.withLock {
      let previous = $0
      $0 += 1
      return previous
    }
  }

  func decrement() -> Int {
    state.withLock {
      $0 -= 1
      return $0
    }
  }
}
#endif
