@testable import TermKit
import Testing

struct InternerPropertyTests {
  @Test func `bounded interner rebuilds preserve retained values and remap identifiers`() {
    runInternerPropertyCases(count: 192, baseSeed: 0x1A7EAE125EED0001) { random in
      try checkGraphemeInterner(random: &random)
      try checkStyleInterner(random: &random)
    }
  }
}

private struct InternerPropertyFailure: Error, CustomStringConvertible {
  var description: String
}

private struct InternerTestRandom {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
    value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
    return value ^ (value >> 31)
  }

  mutating func int(in range: ClosedRange<Int>) -> Int {
    precondition(range.lowerBound <= range.upperBound)
    let count = UInt64(range.upperBound - range.lowerBound + 1)
    return range.lowerBound + Int(next() % count)
  }

  mutating func chance(_ numerator: Int, outOf denominator: Int) -> Bool {
    precondition(numerator >= 0 && numerator <= denominator && denominator > 0)
    return int(in: 1 ... denominator) <= numerator
  }
}

private func runInternerPropertyCases(
  count: Int,
  baseSeed: UInt64,
  sourceLocation: SourceLocation = #_sourceLocation,
  body: (inout InternerTestRandom) throws -> Void
) {
  for caseIndex in 0 ..< count {
    let seed = baseSeed &+ UInt64(caseIndex) &* 0x9E3779B97F4A7C15
    var random = InternerTestRandom(seed: seed)
    do {
      try body(&random)
    } catch {
      Issue.record(
        "Property case \(caseIndex) failed with seed 0x\(String(seed, radix: 16)): \(error)",
        sourceLocation: sourceLocation
      )
      return
    }
  }
}

private func internerRequire(_ condition: @autoclosure () -> Bool, _ description: String) throws {
  guard condition() else { throw InternerPropertyFailure(description: description) }
}

private func internerRequire<T>(_ value: T?, _ description: String) throws -> T {
  guard let value else { throw InternerPropertyFailure(description: description) }
  return value
}

private func checkGraphemeInterner(random: inout InternerTestRandom) throws {
  let rebuildEntryCount = random.int(in: 8 ... 20)
  let rebuildByteCount = random.int(in: 24 ... 72)
  let limits = InternerLimits(
    rebuildEntryCount: rebuildEntryCount,
    maximumEntryCount: 64,
    rebuildByteCount: rebuildByteCount,
    maximumByteCount: 1024
  )
  var interner = GraphemeInterner(limits: limits)
  var entries: [(identifier: GraphemeID, value: String)] = []

  for value in internerGraphemeFixtures.shuffled(using: &random) {
    try entries.append((interner.intern(value), value))
    if interner.stats.requiresRebuild {
      break
    }
  }

  try internerRequire(interner.stats.requiresRebuild, "Grapheme interner did not reach its rebuild threshold")
  try internerRequire(interner.stats.entryCount <= limits.maximumEntryCount, "Grapheme entry count exceeded its bound")
  try internerRequire(interner.stats.estimatedByteCount <= limits.maximumByteCount, "Grapheme bytes exceeded their bound")

  let retainCount = random.int(in: 0 ... min(3, entries.count))
  let retained = Set(entries.shuffled(using: &random).prefix(retainCount).map(\.identifier))
  let oldStats = interner.stats
  let remap = try interner.rebuild(retaining: retained)

  try internerRequire(remap.map(.space) == .space, "Space did not retain its stable grapheme ID")
  for entry in entries {
    if retained.contains(entry.identifier) {
      let newIdentifier = try internerRequire(remap.map(entry.identifier), "Retained grapheme is missing from remap")
      try internerRequire(interner.value(for: newIdentifier) == entry.value, "Retained grapheme changed after rebuild")
      let stableIdentifier = try interner.intern(entry.value)
      try internerRequire(stableIdentifier == newIdentifier, "Retained grapheme ID is not stable")
    } else {
      try internerRequire(remap.map(entry.identifier) == nil, "Dropped grapheme remains in remap")
    }
  }
  try internerRequire(interner.stats.entryCount == retained.count + 1, "Grapheme rebuild retained the wrong entry count")
  try internerRequire(interner.stats.estimatedByteCount <= oldStats.estimatedByteCount, "Grapheme rebuild increased byte usage")
  try internerRequire(interner.stats.requiresRebuild == false, "Bounded grapheme rebuild still requires rebuilding")
}

private func checkStyleInterner(random: inout InternerTestRandom) throws {
  let rebuildEntryCount = random.int(in: 8 ... 20)
  let limits = InternerLimits(
    rebuildEntryCount: rebuildEntryCount,
    maximumEntryCount: 64,
    rebuildByteCount: 4096,
    maximumByteCount: 8192
  )
  var interner = StyleInterner(limits: limits)
  var entries: [(identifier: StyleID, value: CellStyle)] = []

  for index in 0 ..< 32 {
    let byte = UInt8((index * 37 + random.int(in: 0 ... 31)) % 256)
    let style = CellStyle(
      foreground: .rgba(RGBA(redByte: byte, greenByte: byte &+ 73, blueByte: byte &+ 149)),
      attributes: TextAttributes(rawValue: UInt16(1 << (index % 7)))
    )
    try entries.append((interner.intern(style), style))
    if interner.stats.requiresRebuild {
      break
    }
  }

  try internerRequire(interner.stats.requiresRebuild, "Style interner did not reach its rebuild threshold")
  try internerRequire(interner.stats.entryCount <= limits.maximumEntryCount, "Style entry count exceeded its bound")
  try internerRequire(interner.stats.estimatedByteCount <= limits.maximumByteCount, "Style bytes exceeded their bound")

  let retainCount = random.int(in: 0 ... min(3, entries.count))
  let retained = Set(entries.shuffled(using: &random).prefix(retainCount).map(\.identifier))
  let oldStats = interner.stats
  let remap = try interner.rebuild(retaining: retained)

  try internerRequire(remap.map(.default) == .default, "Default style did not retain its stable ID")
  for entry in entries {
    if retained.contains(entry.identifier) {
      let newIdentifier = try internerRequire(remap.map(entry.identifier), "Retained style is missing from remap")
      try internerRequire(interner.value(for: newIdentifier) == entry.value, "Retained style changed after rebuild")
      let stableIdentifier = try interner.intern(entry.value)
      try internerRequire(stableIdentifier == newIdentifier, "Retained style ID is not stable")
    } else {
      try internerRequire(remap.map(entry.identifier) == nil, "Dropped style remains in remap")
    }
  }
  try internerRequire(interner.stats.entryCount == retained.count + 1, "Style rebuild retained the wrong entry count")
  try internerRequire(interner.stats.estimatedByteCount <= oldStats.estimatedByteCount, "Style rebuild increased byte usage")
  try internerRequire(interner.stats.requiresRebuild == false, "Bounded style rebuild still requires rebuilding")
}

private let internerGraphemeFixtures = [
  "a", "b", "c", "d", "e", "f", "g", "h",
  "e\u{301}", "a\u{308}", "o\u{302}", "n\u{303}",
  "\u{754c}", "\u{8a9e}", "\u{3042}", "\u{3044}", "\u{d55c}", "\u{ae00}",
  "\u{1f600}", "\u{1f642}", "\u{1f680}", "\u{1f984}",
  "\u{1f469}\u{200d}\u{1f4bb}", "\u{1f468}\u{200d}\u{1f52c}",
  "\u{1f1fa}\u{1f1e6}", "\u{1f1ef}\u{1f1f5}",
  "1\u{fe0f}\u{20e3}", "2\u{fe0f}\u{20e3}",
  "\u{2764}\u{fe0f}", "\u{2600}\u{fe0f}"
]

extension Array {
  fileprivate func shuffled(using random: inout InternerTestRandom) -> [Element] {
    var result = self
    guard result.count > 1 else { return result }
    for index in stride(from: result.count - 1, through: 1, by: -1) {
      result.swapAt(index, random.int(in: 0 ... index))
    }
    return result
  }
}
