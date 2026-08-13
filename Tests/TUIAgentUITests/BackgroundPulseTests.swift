import TUIFoundation
import TUIAnimation
import TUIControls
import TUILayout
import TUIRenderer
import TUIViewGraph
import Testing

@testable import TUIAgentUI

struct BackgroundPulseTests {
    @Test("Pulse advances at 30 frames per second")
    func frameCadence() {
        let configuration = BackgroundPulseConfiguration(color: .white, frameCount: 60)

        #expect(configuration.frameInterval == .nanoseconds(33_333_333))
        #expect(configuration.frameIndex(at: .milliseconds(100)) == 3)
        #expect(configuration.requiresAnimationFrames)
    }

    @Test("Reduced motion keeps a static pulse frame")
    func reducedMotion() {
        let configuration = BackgroundPulseConfiguration(
            color: .white,
            frameCount: 60,
            isReducedMotionEnabled: true
        )

        #expect(configuration.requiresAnimationFrames == false)
        #expect(configuration.frameIndex(at: .seconds(10)) == 0)
    }

    @Test("Pulse cache reuses frames by geometry and phase")
    func frameCache() throws {
        var cache = BackgroundPulseFrameCache<String>()
        let key = BackgroundPulseFrameKey(width: 80, height: 24, frameIndex: 2, shape: .radial)

        cache.insert("cached-frame", for: key)

        #expect(cache.count == 1)
        #expect(try #require(cache.frame(for: key)) == "cached-frame")
    }

    @Test("Pulse precomputes reusable two-dimensional color frames")
    func generatedFrames() throws {
        let color = RGBA(redByte: 80, greenByte: 166, blueByte: 255)
        let radial = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(
            shape: .radial,
            color: color
        ))
        let logoAdjacent = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(
            shape: .logoAdjacent,
            color: color
        ))
        let size = CellSize(width: 40, height: 12)

        let first = radial.frame(size: size, frameIndex: 0)
        let reused = radial.frame(size: size, frameIndex: 0)
        let animated = radial.frame(size: size, frameIndex: 15)
        let adjacent = logoAdjacent.frame(size: size, frameIndex: 0)

        #expect(first == reused)
        #expect(radial.cachedFrameCount == 2)
        #expect(first.size == size)
        #expect(Set(first.cells.map(\.point.y)).count > 1)
        #expect(first.cells.allSatisfy { $0.color.alpha > 0 && $0.color.alpha <= color.alpha })
        #expect(animated != first)
        #expect(adjacent != first)
    }

    @Test("Pulse canvas paints cached configured colors")
    func canvasPaint() throws {
        let color = RGBA(redByte: 80, greenByte: 166, blueByte: 255)
        let pulse = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(color: color))
        let canvas = pulse.primitive(at: .zero)
        var surface = TUIRenderer.Surface(size: CellSize(width: 20, height: 8))
        var resources = ControlRenderResources()
        let context = PaintContext(clip: surface.bounds)

        _ = try canvas.paint(into: &surface, context: context, resources: &resources)
        _ = try canvas.paint(into: &surface, context: context, resources: &resources)

        #expect(pulse.cachedFrameCount == 1)
        #expect(surface.cells.contains { packedCell in
            guard let background = resources.styles.value(for: packedCell.styleID)?.background else { return false }
            return background == .rgba(color)
        })
    }

    @Test("Pulse view requests 30 FPS through timeline frame demand")
    @MainActor
    func timelineDemand() throws {
        let pulse = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(color: .white))
        let graph = ViewGraph()
        try graph.commit(graph.prepare(pulse))

        let sampling = graph.sampleMountedAttributesDeferringCompletions(at: .zero)

        #expect(sampling.frameDemand == MountedFrameDemand(cadence: .nanoseconds(33_333_333)))
    }

    @Test("Reduced motion uses a static frame and requests no timeline frames")
    @MainActor
    func reducedMotionView() throws {
        let pulse = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(color: .white))
        let graph = ViewGraph()
        try graph.commit(graph.prepare(pulse.reduceMotion(true)))

        let sampling = graph.sampleMountedAttributesDeferringCompletions(
            at: TimeInstant.zero.advanced(by: .seconds(1))
        )

        #expect(sampling.frameDemand == nil)
        #expect(pulse.primitive(at: TimeInstant(nanoseconds: 999_999_999), reduceMotion: true).frameIndex == 0)
    }
}
