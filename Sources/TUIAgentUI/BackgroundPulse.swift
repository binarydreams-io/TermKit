import Foundation
import TUIAnimation
import TUIControls
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public enum BackgroundPulseShape: String, Sendable, Hashable, CaseIterable {
    case radial
    case logoAdjacent
}

public struct BackgroundPulseConfiguration: Sendable, Hashable {
    public var shape: BackgroundPulseShape
    public var color: RGBA
    public var framesPerSecond: Int
    public var frameCount: Int
    public var isReducedMotionEnabled: Bool

    public init(
        shape: BackgroundPulseShape = .radial,
        color: RGBA,
        framesPerSecond: Int = 30,
        frameCount: Int = 60,
        isReducedMotionEnabled: Bool = false
    ) {
        precondition(framesPerSecond > 0 && framesPerSecond <= FrameScheduler.maximumFramesPerSecond)
        precondition(frameCount > 0)
        self.shape = shape
        self.color = color
        self.framesPerSecond = framesPerSecond
        self.frameCount = frameCount
        self.isReducedMotionEnabled = isReducedMotionEnabled
    }

    public var requiresAnimationFrames: Bool { isReducedMotionEnabled == false && frameCount > 1 }
    public var frameInterval: TUIDuration { .seconds(1 / Double(framesPerSecond)) }

    public func frameIndex(at elapsed: TUIDuration) -> Int {
        guard requiresAnimationFrames else { return 0 }
        let nonnegativeNanoseconds = max(0, elapsed.nanoseconds)
        let frame = nonnegativeNanoseconds / frameInterval.nanoseconds
        return Int(frame % Int64(frameCount))
    }
}

public struct BackgroundPulseFrameKey: Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var frameIndex: Int
    public var shape: BackgroundPulseShape
    public var color: RGBA
    public var frameCount: Int

    public init(
        width: Int,
        height: Int,
        frameIndex: Int,
        shape: BackgroundPulseShape,
        color: RGBA = .clear,
        frameCount: Int = 0
    ) {
        precondition(width >= 0 && height >= 0 && frameIndex >= 0)
        precondition(frameCount >= 0)
        self.width = width
        self.height = height
        self.frameIndex = frameIndex
        self.shape = shape
        self.color = color
        self.frameCount = frameCount
    }
}

/// Reusable pulse frames keyed by geometry and phase.
public struct BackgroundPulseFrameCache<Frame: Sendable>: Sendable {
    private var frames: [BackgroundPulseFrameKey: Frame]

    public init() {
        frames = [:]
    }

    public var count: Int { frames.count }

    public func frame(for key: BackgroundPulseFrameKey) -> Frame? {
        frames[key]
    }

    public mutating func insert(_ frame: Frame, for key: BackgroundPulseFrameKey) {
        frames[key] = frame
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        frames.removeAll(keepingCapacity: keepingCapacity)
    }
}

public struct BackgroundPulseCell: Sendable, Hashable {
    public var point: CellPoint
    public var color: RGBA

    public init(point: CellPoint, color: RGBA) {
        self.point = point
        self.color = color
    }
}

public struct BackgroundPulseFrame: Sendable, Hashable {
    public var size: CellSize
    public var cells: [BackgroundPulseCell]

    public init(size: CellSize, cells: [BackgroundPulseCell]) {
        self.size = size
        self.cells = cells
    }
}

private final class BackgroundPulseCacheStore<Frame: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: BackgroundPulseFrameCache<Frame>

    init(cache: BackgroundPulseFrameCache<Frame>) {
        self.cache = cache
    }

    func frame(for key: BackgroundPulseFrameKey, create: () -> Frame) -> Frame {
        lock.lock()
        defer { lock.unlock() }
        if let frame = cache.frame(for: key) { return frame }
        let frame = create()
        cache.insert(frame, for: key)
        return frame
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    var snapshot: BackgroundPulseFrameCache<Frame> {
        lock.lock()
        defer { lock.unlock() }
        return cache
    }

    func replace(with cache: BackgroundPulseFrameCache<Frame>) {
        lock.lock()
        defer { lock.unlock() }
        self.cache = cache
    }
}

/// An optional pulse presentation. Base themes and prompts do not depend on this type.
public struct BackgroundPulse<Frame: Sendable>: Sendable {
    public var configuration: BackgroundPulseConfiguration
    private let cacheStore: BackgroundPulseCacheStore<Frame>

    public var frameCache: BackgroundPulseFrameCache<Frame> {
        get { cacheStore.snapshot }
        nonmutating set { cacheStore.replace(with: newValue) }
    }

    public init(
        configuration: BackgroundPulseConfiguration,
        frameCache: BackgroundPulseFrameCache<Frame> = BackgroundPulseFrameCache()
    ) {
        self.configuration = configuration
        cacheStore = BackgroundPulseCacheStore(cache: frameCache)
    }
}

extension BackgroundPulse where Frame == BackgroundPulseFrame {
    public init(configuration: BackgroundPulseConfiguration) {
        self.init(configuration: configuration, frameCache: BackgroundPulseFrameCache())
    }

    var cachedFrameCount: Int { cacheStore.count }

    func frame(size: CellSize, frameIndex: Int) -> BackgroundPulseFrame {
        let index = configuration.requiresAnimationFrames ? frameIndex % configuration.frameCount : 0
        let key = BackgroundPulseFrameKey(
            width: size.width,
            height: size.height,
            frameIndex: index,
            shape: configuration.shape,
            color: configuration.color,
            frameCount: configuration.frameCount
        )
        return cacheStore.frame(for: key) {
            Self.makeFrame(size: size, frameIndex: index, configuration: configuration)
        }
    }

    func primitive(at instant: TimeInstant, reduceMotion: Bool = false) -> BackgroundPulseCanvas {
        let elapsed = TUIDuration.nanoseconds(max(0, instant.nanoseconds))
        let frameIndex = configuration.frameIndex(
            at: reduceMotion || configuration.isReducedMotionEnabled ? .zero : elapsed
        )
        return BackgroundPulseCanvas(pulse: self, frameIndex: frameIndex)
    }

    private static func makeFrame(
        size: CellSize,
        frameIndex: Int,
        configuration: BackgroundPulseConfiguration
    ) -> BackgroundPulseFrame {
        guard size.width > 0, size.height > 0 else {
            return BackgroundPulseFrame(size: size, cells: [])
        }

        let phase = Double(frameIndex) / Double(configuration.frameCount)
        let pulse = 0.5 - 0.5 * cos(phase * 2 * Double.pi)
        let extent = Double(max(1, min(size.width, size.height * 2)))
        let centerX = configuration.shape == .radial ? Double(size.width - 1) / 2 : Double(size.width - 1) / 4
        let centerY = Double(size.height - 1) / 2
        let radius = extent * (0.16 + 0.18 * pulse)
        let feather = max(1, extent * 0.22)
        var cells: [BackgroundPulseCell] = []
        cells.reserveCapacity(size.cellCount / 2)

        for y in 0..<size.height {
            for x in 0..<size.width {
                let dx = Double(x) - centerX
                let dy = (Double(y) - centerY) * 2
                let distance = hypot(dx, dy)
                let intensity = max(0, min(1, (radius + feather - distance) / feather))
                guard intensity > 0.04 else { continue }
                cells.append(BackgroundPulseCell(
                    point: CellPoint(x: x, y: y),
                    color: configuration.color.applyingOpacity(intensity)
                ))
            }
        }
        return BackgroundPulseFrame(size: size, cells: cells)
    }
}

extension BackgroundPulse: TUIViewGraph.View where Frame == BackgroundPulseFrame {
    @MainActor
    public var graphBody: [NodeDescriptor] {
        if configuration.isReducedMotionEnabled || configuration.requiresAnimationFrames == false {
            primitive(at: .zero, reduceMotion: true).graphBody
        } else {
            TimelineView(.animation(minimumInterval: configuration.frameInterval)) { context in
                primitive(
                    at: context.instant,
                    reduceMotion: context.reduceMotion || context.animationsEnabled == false
                )
            }.graphBody
        }
    }
}

struct BackgroundPulseCanvas: SemanticRenderable, TUIViewGraph.View, Sendable {
    let pulse: BackgroundPulse<BackgroundPulseFrame>
    let frameIndex: Int

    nonisolated func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: max(0, proposal.width ?? 80), height: max(0, proposal.height ?? 24))
    }

    nonisolated func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let size = CellSize(width: context.clip.width, height: context.clip.height)
        let frame = pulse.frame(size: size, frameIndex: frameIndex)
        let space = try resources.graphemes.intern(" ")
        for cell in frame.cells {
            let point = context.origin.offsetBy(dx: cell.point.x, dy: cell.point.y)
            guard context.clip.contains(point), surface.bounds.contains(point) else { continue }
            let color = cell.color.applyingOpacity(context.opacity)
            let style = try resources.internPaintStyle(CellStyle(background: .rgba(color)))
            _ = try surface.write(graphemeID: space, styleID: style, at: point, clip: context.clip)
        }
        return SemanticNode(
            id: "background-pulse",
            role: .progressIndicator,
            label: "Background pulse",
            frame: CellRect(origin: context.origin, size: size)
        )
    }

    @MainActor
    var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .paint)]
    }
}
