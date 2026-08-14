@testable import TermKit
import Testing

struct DamageAndPaintTests {
  private enum PaintValueKey: PaintEnvironmentKey {
    static let defaultValue = "default"
  }

  @Test func `damage tracker unions overlapping rects`() {
    var tracker = DamageTracker(bounds: CellRect(x: 0, y: 0, width: 10, height: 4))
    tracker.add(CellRect(x: 1, y: 1, width: 4, height: 2))
    tracker.add(CellRect(x: 3, y: 0, width: 4, height: 2))

    #expect(tracker.rectangles == [CellRect(x: 1, y: 0, width: 6, height: 3)])
    #expect(tracker.ranges(inRow: 1) == [1 ..< 7])
    #expect(tracker.damagedCellCount == 18)
  }

  @Test func `damage tracker clips to bounds`() {
    var tracker = DamageTracker(bounds: CellRect(x: 0, y: 0, width: 4, height: 2))
    tracker.add(CellRect(x: -2, y: 1, width: 5, height: 3))

    #expect(tracker.rectangles == [CellRect(x: 0, y: 1, width: 3, height: 1)])
  }

  @Test func `paint context combines origin clip opacity and Z index`() throws {
    let environment = PaintEnvironmentValues { identifier in
      identifier == ObjectIdentifier(PaintValueKey.self) ? "inherited" : nil
    }
    let root = PaintContext(
      clip: CellRect(x: 0, y: 0, width: 10, height: 5),
      environment: environment
    )
    let child = try #require(
      root.translated(by: CellPoint(x: 3, y: 1))
        .clipped(to: CellRect(x: 1, y: 1, width: 4, height: 3))
    ).multiplyingOpacity(0.5).withZIndex(7)

    #expect(child.origin == CellPoint(x: 3, y: 1))
    #expect(child.clip == CellRect(x: 4, y: 2, width: 4, height: 3))
    #expect(child.opacity == 0.5)
    #expect(child.zIndex == 7)
    #expect(child.resolve(CellPoint(x: 1, y: 1)) == CellPoint(x: 4, y: 2))
    #expect(child.resolve(.zero) == nil)
    #expect(child.environment[PaintValueKey.self] == "inherited")
  }

  #if DEBUG
  @Test func `nested clip scopes restore their shared depth`() {
    let root = PaintContext(clip: CellRect(x: 0, y: 0, width: 10, height: 5))

    root.withClipScope(origin: .zero, clip: root.clip) { child in
      #expect(child.debugClipScopeDepth == 1)
      child.withClipScope(origin: .zero, clip: child.clip) { nested in
        #expect(nested.debugClipScopeDepth == 2)
      }
      #expect(child.debugClipScopeDepth == 1)
    }

    #expect(root.debugClipScopeDepth == 0)
  }
  #endif
}
