@testable import TermKit
import Testing

struct BackgroundPulseTests {
  @Test
  func `Pulse advances at 30 frames per second`() {
    let configuration = BackgroundPulseConfiguration(color: .white, frameCount: 60)

    #expect(configuration.frameInterval == .nanoseconds(33_333_333))
    #expect(configuration.frameIndex(at: .milliseconds(100)) == 3)
    #expect(configuration.requiresAnimationFrames)
  }

  @Test
  func `Reduced motion keeps a static pulse frame`() {
    let configuration = BackgroundPulseConfiguration(
      color: .white,
      frameCount: 60,
      isReducedMotionEnabled: true
    )

    #expect(configuration.requiresAnimationFrames == false)
    #expect(configuration.frameIndex(at: .seconds(10)) == 0)
  }

  @Test
  func `Pulse cache reuses frames by geometry and phase`() throws {
    var cache = BackgroundPulseFrameCache<String>()
    let key = BackgroundPulseFrameKey(width: 80, height: 24, frameIndex: 2, shape: .radial)

    cache.insert("cached-frame", for: key)

    #expect(cache.count == 1)
    #expect(try #require(cache.frame(for: key)) == "cached-frame")
  }

  @Test
  func `Pulse precomputes reusable two-dimensional color frames`() {
    let color = RGBA(redByte: 80, greenByte: 166, blueByte: 255)
    let radial = BackgroundPulse<BackgroundPulseFrame>(
      configuration: BackgroundPulseConfiguration(
        color: color,
        shape: .radial
      )
    )
    let logoAdjacent = BackgroundPulse<BackgroundPulseFrame>(
      configuration: BackgroundPulseConfiguration(
        color: color,
        shape: .logoAdjacent
      )
    )
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

  @Test
  func `Pulse canvas paints cached configured colors`() throws {
    let color = RGBA(redByte: 80, greenByte: 166, blueByte: 255)
    let pulse = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(color: color))
    let canvas = pulse.primitive(at: .zero)
    var surface = Surface(size: CellSize(width: 20, height: 8))
    var resources = ControlRenderResources()
    let context = PaintContext(clip: surface.bounds)

    _ = try canvas.paint(into: &surface, context: context, resources: &resources)
    _ = try canvas.paint(into: &surface, context: context, resources: &resources)

    #expect(pulse.cachedFrameCount == 1)
    #expect(
      surface.cells.contains { packedCell in
        guard let background = resources.styles.value(for: packedCell.styleID)?.background else { return false }
        return background == .rgba(color)
      }
    )
  }

  @Test
  @MainActor
  func `Pulse view requests 30 FPS through timeline frame demand`() throws {
    let pulse = BackgroundPulse<BackgroundPulseFrame>(configuration: BackgroundPulseConfiguration(color: .white))
    let graph = ViewGraph()
    try graph.commit(graph.prepare(pulse))

    let sampling = graph.sampleMountedAttributesDeferringCompletions(at: .zero)

    #expect(sampling.frameDemand == MountedFrameDemand(cadence: .nanoseconds(33_333_333)))
  }

  @Test
  @MainActor
  func `Reduced motion uses a static frame and requests no timeline frames`() throws {
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
