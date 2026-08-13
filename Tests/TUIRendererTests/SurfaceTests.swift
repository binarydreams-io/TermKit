import Testing
@testable import TUIFoundation
@testable import TUIRenderer

struct SurfaceTests {
    @Test func wideGraphemeReservesContinuationCell() throws {
        var surface = Surface(size: CellSize(width: 4, height: 1))
        let identifier = GraphemeID(rawValue: 7)

        try surface.write(graphemeID: identifier, displayWidth: 2, at: CellPoint(x: 1, y: 0))

        #expect(surface[CellPoint(x: 1, y: 0)].displayWidth == 2)
        #expect(surface[CellPoint(x: 2, y: 0)].isContinuation)
        #expect(surface[CellPoint(x: 2, y: 0)].graphemeID == identifier)
        #expect(throws: Never.self) { try surface.validateWideCells() }
    }

    @Test func clippingRejectsPartiallyVisibleWideGrapheme() {
        var surface = Surface(size: CellSize(width: 3, height: 1))
        let point = CellPoint(x: 1, y: 0)

        #expect(throws: SurfaceError.clippedWideGrapheme(point)) {
            try surface.write(
                graphemeID: GraphemeID(rawValue: 1),
                displayWidth: 2,
                at: point,
                clip: CellRect(x: 0, y: 0, width: 2, height: 1)
            )
        }
        #expect(surface == Surface(size: CellSize(width: 3, height: 1)))
    }

    @Test func clearingContinuationClearsWholeWideAtom() throws {
        var surface = Surface(size: CellSize(width: 3, height: 1))
        try surface.write(graphemeID: GraphemeID(rawValue: 1), displayWidth: 2, at: .zero)

        surface.clear(CellRect(x: 1, y: 0, width: 1, height: 1))

        #expect(surface[.zero] == .blank())
        #expect(surface[CellPoint(x: 1, y: 0)] == .blank())
        #expect(throws: Never.self) { try surface.validateWideCells() }
    }

    @Test func replacingContinuationRemovesOldLeader() throws {
        var surface = Surface(size: CellSize(width: 3, height: 1))
        try surface.write(graphemeID: GraphemeID(rawValue: 1), displayWidth: 2, at: .zero)

        try surface.write(graphemeID: GraphemeID(rawValue: 2), at: CellPoint(x: 1, y: 0))

        #expect(surface[.zero] == .blank())
        #expect(surface[CellPoint(x: 1, y: 0)].graphemeID == GraphemeID(rawValue: 2))
        #expect(throws: Never.self) { try surface.validateWideCells() }
    }

    @Test func compositionSkipsClippedWideAtom() throws {
        var destination = Surface(size: CellSize(width: 3, height: 1))
        var source = Surface(size: CellSize(width: 2, height: 1), fill: .transparent)
        try source.write(graphemeID: GraphemeID(rawValue: 1), displayWidth: 2, at: .zero)

        try destination.compose(source, at: CellPoint(x: 1, y: 0), clip: CellRect(x: 0, y: 0, width: 2, height: 1))

        #expect(destination == Surface(size: CellSize(width: 3, height: 1)))
        #expect(throws: Never.self) { try destination.validateWideCells() }
    }

    @Test func surfaceRemapsInternedIdentifiers() throws {
        var graphemes = GraphemeInterner()
        let dropped = try graphemes.intern("x")
        let retained = try graphemes.intern("界")
        var surface = Surface(size: CellSize(width: 2, height: 1))
        try surface.write(graphemeID: retained, displayWidth: 2, at: .zero)

        let remap = try graphemes.rebuild(retaining: [retained])
        try surface.remapGraphemes(using: remap)

        #expect(remap.map(dropped) == nil)
        #expect(surface[.zero].graphemeID == remap.map(retained))
        #expect(throws: Never.self) { try surface.validateWideCells() }
    }
}
