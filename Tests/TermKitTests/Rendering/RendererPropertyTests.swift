import Foundation
import Testing

@testable import TermKit

struct RendererPropertyTests {
    @Test func seededUnicodeSurfacesPreserveWideCellInvariants() {
        runRendererPropertyCases(count: 256, baseSeed: 0xA11C_E5E1_5EED_0001) { random in
            var interner = GraphemeInterner()
            let graphemes = try rendererGraphemes(interner: &interner)
            let size = CellSize(width: random.int(in: 4...18), height: random.int(in: 1...8))
            let surface = try randomSurface(size: size, graphemes: graphemes, random: &random)

            try surface.validateWideCells()
            for cell in surface.cells where cell.isContinuation == false {
                let value = try rendererRequire(interner.value(for: cell.graphemeID), "Unknown grapheme ID in surface")
                try rendererRequire(
                    TerminalWidth.width(of: value) == Int(cell.displayWidth),
                    "Interned grapheme width does not match its cell width"
                )
            }
        }
    }

    @Test func arbitraryWriteClearAndComposeSequencesPreserveWideCellInvariants() {
        runRendererPropertyCases(count: 256, baseSeed: 0xA11C_E5E1_5EED_0002) { random in
            var interner = GraphemeInterner()
            let graphemes = try rendererGraphemes(interner: &interner)
            let size = CellSize(width: random.int(in: 1...18), height: random.int(in: 1...8))
            var surface = try randomSurface(size: size, graphemes: graphemes, random: &random)

            for _ in 0..<64 {
                switch random.int(in: 0...4) {
                case 0, 1:
                    let point = randomPoint(in: surface.size, random: &random)
                    let grapheme = randomGrapheme(fitting: surface.size.width - point.x, from: graphemes, random: &random)
                    let clip =
                        random.chance(1, outOf: 2)
                        ? containingClip(
                            point: point,
                            width: grapheme.width,
                            bounds: surface.bounds,
                            random: &random
                        )
                        : nil
                    _ = try surface.write(
                        graphemeID: grapheme.identifier,
                        at: point,
                        styleID: randomStyleID(random: &random),
                        displayWidth: UInt8(grapheme.width),
                        flags: randomCellFlags(random: &random),
                        clip: clip
                    )
                case 2:
                    surface.clear(randomRect(around: surface.bounds, random: &random))
                default:
                    let sourceSize = CellSize(width: random.int(in: 1...10), height: random.int(in: 1...5))
                    let source = try randomSurface(
                        size: sourceSize,
                        fill: .transparent,
                        graphemes: graphemes,
                        random: &random
                    )
                    let origin = CellPoint(
                        x: random.int(in: -sourceSize.width...surface.size.width),
                        y: random.int(in: -sourceSize.height...surface.size.height)
                    )
                    let clip = random.chance(2, outOf: 3) ? randomRect(around: surface.bounds, random: &random) : nil
                    try surface.compose(source, at: origin, clip: clip)
                }
                try surface.validateWideCells()
            }
        }
    }

    @Test func randomDamageDiffsReplayToNextSemanticSurface() {
        runRendererPropertyCases(count: 320, baseSeed: 0xA11C_E5E1_5EED_0003) { random in
            var interner = GraphemeInterner()
            let graphemes = try rendererGraphemes(interner: &interner)
            let size = CellSize(width: random.int(in: 1...20), height: random.int(in: 1...10))
            let previous = try randomSurface(size: size, graphemes: graphemes, random: &random)
            var next: Surface

            if random.chance(1, outOf: 3) {
                next = try randomSurface(size: size, graphemes: graphemes, random: &random)
            } else {
                next = previous
                for _ in 0..<random.int(in: 1...24) {
                    if random.chance(2, outOf: 3) {
                        let point = randomPoint(in: size, random: &random)
                        let grapheme = randomGrapheme(fitting: size.width - point.x, from: graphemes, random: &random)
                        try next.write(
                            graphemeID: grapheme.identifier,
                            at: point,
                            styleID: randomStyleID(random: &random),
                            displayWidth: UInt8(grapheme.width),
                            flags: randomCellFlags(random: &random)
                        )
                    } else {
                        next.clear(randomRect(around: next.bounds, random: &random))
                    }
                }
            }

            var damage = DamageTracker(bounds: next.bounds)
            for y in 0..<size.height {
                for x in 0..<size.width {
                    let point = CellPoint(x: x, y: y)
                    if previous[point] != next[point] {
                        damage.add(randomDamage(containing: point, in: next.bounds, random: &random))
                    }
                }
            }
            for _ in 0..<random.int(in: 0...8) {
                damage.add(randomRect(around: next.bounds, random: &random))
            }

            let result = try CellDiffer(maximumRewrittenGap: random.int(in: 0...4)).diff(
                front: previous,
                back: next,
                damage: damage
            )
            var replayed = SemanticScreen(surface: previous)
            try replayed.apply(result.operations)

            try replayed.surface.validateWideCells()
            try rendererRequire(replayed.surface == next, "Replayed diff does not equal the next semantic surface")
        }
    }

    @Test func randomResizeAndOverlappingLayerSequencesPreserveWideCellInvariants() {
        runRendererPropertyCases(count: 192, baseSeed: 0xA11C_E5E1_5EED_0004) { random in
            var interner = GraphemeInterner()
            let graphemes = try rendererGraphemes(interner: &interner)
            var surface = try randomSurface(
                size: CellSize(width: random.int(in: 1...20), height: random.int(in: 1...10)),
                graphemes: graphemes,
                random: &random
            )

            for _ in 0..<12 {
                let nextSize = CellSize(width: random.int(in: 1...20), height: random.int(in: 1...10))
                var resized = Surface(size: nextSize)
                try resized.compose(surface)

                for _ in 0..<random.int(in: 1...5) {
                    let layerSize = CellSize(width: random.int(in: 1...14), height: random.int(in: 1...7))
                    let layer = try randomSurface(
                        size: layerSize,
                        fill: .transparent,
                        graphemes: graphemes,
                        random: &random
                    )
                    let origin = CellPoint(
                        x: random.int(in: -layerSize.width...nextSize.width),
                        y: random.int(in: -layerSize.height...nextSize.height)
                    )
                    let clip = random.chance(1, outOf: 2) ? randomRect(around: resized.bounds, random: &random) : nil
                    try resized.compose(layer, at: origin, clip: clip)
                    try resized.validateWideCells()
                }
                surface = resized
            }
        }
    }
}

private struct RendererTestGrapheme {
    var value: String
    var identifier: GraphemeID
    var width: Int
}

private struct RendererPropertyFailure: Error, CustomStringConvertible {
    var description: String
}

private struct RendererTestRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        precondition(range.lowerBound <= range.upperBound)
        let count = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % count)
    }

    mutating func chance(_ numerator: Int, outOf denominator: Int) -> Bool {
        precondition(numerator >= 0 && numerator <= denominator && denominator > 0)
        return int(in: 1...denominator) <= numerator
    }
}

private func runRendererPropertyCases(
    count: Int,
    baseSeed: UInt64,
    sourceLocation: SourceLocation = #_sourceLocation,
    body: (inout RendererTestRandom) throws -> Void
) {
    let configuredSeed = ProcessInfo.processInfo.environment["TERMKIT_FUZZ_SEED"].flatMap { value -> UInt64? in
        let digits = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
        return UInt64(digits, radix: value.hasPrefix("0x") ? 16 : 10)
    }
    let seeds =
        configuredSeed.map { [$0] }
        ?? (0..<count).map {
            baseSeed &+ UInt64($0) &* 0x9E37_79B9_7F4A_7C15
        }
    for (caseIndex, seed) in seeds.enumerated() {
        var random = RendererTestRandom(seed: seed)
        do {
            try body(&random)
        } catch {
            let seedText = String(seed, radix: 16)
            let diagnostic =
                "Property case \(caseIndex) failed with seed 0x\(seedText): \(error). "
                + "Reproduce with TERMKIT_FUZZ_SEED=0x\(seedText) "
                + "swift test --filter RendererPropertyTests"
            Issue.record(
                Comment(rawValue: diagnostic),
                sourceLocation: sourceLocation
            )
            return
        }
    }
}

private func rendererRequire(_ condition: @autoclosure () -> Bool, _ description: String) throws {
    guard condition() else { throw RendererPropertyFailure(description: description) }
}

private func rendererRequire<T>(_ value: T?, _ description: String) throws -> T {
    guard let value else { throw RendererPropertyFailure(description: description) }
    return value
}

private func rendererGraphemes(interner: inout GraphemeInterner) throws -> [RendererTestGrapheme] {
    let values = [
        "a",
        "Z",
        "e\u{301}",
        "a\u{308}\u{304}",
        "\u{0915}\u{93f}",
        "\u{754c}",
        "\u{8a9e}",
        "\u{3042}",
        "\u{d55c}",
        "\u{1f642}",
        "\u{1f469}\u{200d}\u{1f4bb}",
        "\u{1f1fa}\u{1f1e6}",
        "1\u{fe0f}\u{20e3}",
        "\u{2764}\u{fe0f}",
    ]
    return try values.map { value in
        try rendererRequire(value.count == 1, "Unicode fixture is not one extended grapheme cluster")
        let width = TerminalWidth.width(of: value)
        try rendererRequire(width == 1 || width == 2, "Unicode fixture has an unsupported terminal width")
        return try RendererTestGrapheme(value: value, identifier: interner.intern(value), width: width)
    }
}

private func randomSurface(
    size: CellSize,
    fill: PackedCell = .makeBlank(),
    graphemes: [RendererTestGrapheme],
    random: inout RendererTestRandom
) throws -> Surface {
    var surface = Surface(size: size, fill: fill)
    for y in 0..<size.height {
        var x = 0
        while x < size.width {
            guard random.chance(3, outOf: 4) else {
                x += 1
                continue
            }
            let grapheme = randomGrapheme(fitting: size.width - x, from: graphemes, random: &random)
            try surface.write(
                graphemeID: grapheme.identifier,
                at: CellPoint(x: x, y: y),
                styleID: randomStyleID(random: &random),
                displayWidth: UInt8(grapheme.width),
                flags: randomCellFlags(random: &random)
            )
            x += grapheme.width
        }
    }
    return surface
}

private func randomGrapheme(
    fitting availableWidth: Int,
    from graphemes: [RendererTestGrapheme],
    random: inout RendererTestRandom
) -> RendererTestGrapheme {
    while true {
        let candidate = graphemes[random.int(in: 0...(graphemes.count - 1))]
        if candidate.width <= availableWidth { return candidate }
    }
}

private func randomStyleID(random: inout RendererTestRandom) -> StyleID {
    StyleID(rawValue: UInt32(random.int(in: 0...7)))
}

private func randomCellFlags(random: inout RendererTestRandom) -> CellFlags {
    switch random.int(in: 0...5) {
    case 1: [.explicitBlank]
    case 2: [.empty]
    case 3: [.empty, .explicitBlank]
    case 4: [.transparent]
    default: []
    }
}

private func randomPoint(in size: CellSize, random: inout RendererTestRandom) -> CellPoint {
    CellPoint(x: random.int(in: 0...(size.width - 1)), y: random.int(in: 0...(size.height - 1)))
}

private func containingClip(
    point: CellPoint,
    width: Int,
    bounds: CellRect,
    random: inout RendererTestRandom
) -> CellRect {
    let leading = random.int(in: 0...2)
    let trailing = random.int(in: 0...2)
    let top = random.int(in: 0...2)
    let bottom = random.int(in: 0...2)
    let clip = CellRect(
        x: point.x - leading,
        y: point.y - top,
        width: leading + width + trailing,
        height: top + 1 + bottom
    )
    precondition(bounds.contains(CellRect(x: point.x, y: point.y, width: width, height: 1)))
    return clip
}

private func randomRect(around bounds: CellRect, random: inout RendererTestRandom) -> CellRect {
    CellRect(
        x: random.int(in: (bounds.minX - 2)...(bounds.maxX + 1)),
        y: random.int(in: (bounds.minY - 2)...(bounds.maxY + 1)),
        width: random.int(in: 0...(bounds.width + 4)),
        height: random.int(in: 0...(bounds.height + 4))
    )
}

private func randomDamage(
    containing point: CellPoint,
    in bounds: CellRect,
    random: inout RendererTestRandom
) -> CellRect {
    let leading = random.int(in: 0...min(3, point.x - bounds.minX))
    let trailing = random.int(in: 0...min(3, bounds.maxX - point.x - 1))
    let top = random.int(in: 0...min(2, point.y - bounds.minY))
    let bottom = random.int(in: 0...min(2, bounds.maxY - point.y - 1))
    return CellRect(
        x: point.x - leading,
        y: point.y - top,
        width: leading + 1 + trailing,
        height: top + 1 + bottom
    )
}
