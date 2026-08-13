import Testing
@testable import TUIFoundation

struct CellAndInternerTests {
    @Test func packedCellRoundTripsAllFields() {
        let cell = PackedCell(
            graphemeID: GraphemeID(rawValue: 0x12_3456),
            styleID: StyleID(rawValue: 0x65_4321),
            displayWidth: 2,
            flags: [.transparent, .explicitBlank]
        )

        #expect(MemoryLayout<PackedCell>.size == 8)
        #expect(cell.graphemeID == GraphemeID(rawValue: 0x12_3456))
        #expect(cell.styleID == StyleID(rawValue: 0x65_4321))
        #expect(cell.displayWidth == 2)
        #expect(cell.flags == [.transparent, .explicitBlank])
    }

    @Test func graphemeInternerAcceptsExtendedClustersAndKeepsStableIDs() throws {
        var interner = GraphemeInterner()
        let combining = "e\u{301}"

        let first = try interner.intern(combining)
        let second = try interner.intern(combining)

        #expect(first == second)
        #expect(interner.value(for: first) == combining)
    }

    @Test func graphemeInternerEnforcesHardLimit() throws {
        let limits = InternerLimits(
            rebuildEntryCount: 2,
            maximumEntryCount: 3,
            rebuildByteCount: 1_024,
            maximumByteCount: 2_048
        )
        var interner = GraphemeInterner(limits: limits)
        _ = try interner.intern("a")
        _ = try interner.intern("b")

        #expect(interner.stats.requiresRebuild)
        #expect(throws: InternerError.entryLimitExceeded(3)) {
            try interner.intern("c")
        }
    }

    @Test func rebuildReturnsLiveIdentifierMap() throws {
        var interner = GraphemeInterner()
        let dropped = try interner.intern("x")
        let retained = try interner.intern("y")

        let remap = try interner.rebuild(retaining: [retained])

        #expect(remap.map(.space) == .space)
        #expect(remap.map(dropped) == nil)
        let newIdentifier = try #require(remap.map(retained))
        #expect(interner.value(for: newIdentifier) == "y")
    }

    @Test func styleInternerDeduplicatesStyles() throws {
        var interner = StyleInterner()
        let style = CellStyle(foreground: .rgba(.white), attributes: .bold)

        let first = try interner.intern(style)
        let second = try interner.intern(style)
        #expect(first == second)
    }

    @Test func boundedBufferDropsOldestElements() {
        var buffer = BoundedBuffer<Int>(capacity: 2)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        #expect(buffer.elements == [2, 3])
        #expect(buffer.droppedCount == 1)
    }
}
