@testable import TermKit
import Testing

struct GeometryTests {
  @Test func `rect intersection uses half open coordinates`() {
    let first = CellRect(x: 1, y: 2, width: 4, height: 3)
    let second = CellRect(x: 3, y: 1, width: 4, height: 3)

    #expect(first.intersection(second) == CellRect(x: 3, y: 2, width: 2, height: 2))
    #expect(first.contains(CellPoint(x: 4, y: 4)))
    #expect(first.contains(CellPoint(x: 5, y: 4)) == false)
  }

  @Test func `insets clamp dimensions at zero`() {
    let rect = CellRect(x: 2, y: 3, width: 4, height: 2)

    #expect(rect.inset(by: EdgeInsets(horizontal: 3, vertical: 2)) == CellRect(x: 5, y: 5, width: 0, height: 0))
  }

  @Test func `union includes both rects`() {
    let first = CellRect(x: 4, y: 5, width: 2, height: 3)
    let second = CellRect(x: 1, y: 6, width: 2, height: 4)

    #expect(first.union(second) == CellRect(x: 1, y: 5, width: 5, height: 5))
  }
}
