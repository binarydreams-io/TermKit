@testable import TermKit
import Testing

struct CellDiffTests {
  @Test func `replaying diff produces back surface`() throws {
    var front = Surface(size: CellSize(width: 6, height: 2))
    var back = front
    try front.write(graphemeID: GraphemeID(rawValue: 1), at: CellPoint(x: 1, y: 0), displayWidth: 2)
    try back.write(graphemeID: GraphemeID(rawValue: 2), at: CellPoint(x: 0, y: 0), styleID: StyleID(rawValue: 1))
    try back.write(
      graphemeID: GraphemeID(rawValue: 3),
      at: CellPoint(x: 3, y: 1),
      styleID: StyleID(rawValue: 2),
      displayWidth: 2
    )
    var damage = DamageTracker(bounds: back.bounds)
    damage.add(CellRect(x: 0, y: 0, width: 3, height: 1))
    damage.add(CellRect(x: 3, y: 1, width: 2, height: 1))

    let result = try CellDiffer().diff(front: front, back: back, damage: damage)
    var screen = SemanticScreen(surface: front)
    try screen.apply(result.operations)

    #expect(screen.surface == back)
    #expect(result.scannedCellCount == 5)
    #expect(result.changedCellCount == 5)
  }

  @Test func `diff rewrites short unchanged gap`() throws {
    let front = Surface(size: CellSize(width: 3, height: 1))
    var back = front
    try back.write(graphemeID: GraphemeID(rawValue: 1), at: .zero)
    try back.write(graphemeID: GraphemeID(rawValue: 2), at: CellPoint(x: 2, y: 0))

    let result = try CellDiffer(maximumRewrittenGap: 1).diff(front: front, back: back)
    let writes = result.operations.compactMap { operation -> GraphemeID? in
      guard case let .write(identifier, _, _) = operation else { return nil }
      return identifier
    }

    #expect(writes == [GraphemeID(rawValue: 1), .space, GraphemeID(rawValue: 2)])
    #expect(result.operations.filter {
      if case .moveCursor = $0 {
        true
      } else {
        false
      }
    }.count == 1)
  }

  @Test func `unchanged surface produces no operations`() throws {
    let surface = Surface(size: CellSize(width: 4, height: 2))

    let result = try CellDiffer().diff(front: surface, back: surface)

    #expect(result.operations.isEmpty)
    #expect(result.changedCellCount == 0)
  }
}
