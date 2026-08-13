//  TUIkit - Terminal UI Kit for Swift
//  TerminalInputParser.swift
//
//  License: MIT

/// Buffers terminal bytes and emits complete input events.
package struct TerminalInputParser: Sendable {
  private static let escape: UInt8 = 0x1B, csi: UInt8 = 0x5B, ss3: UInt8 = 0x4F
  private static let pasteStart = Array("\u{1B}[200~".utf8), pasteEnd = Array("\u{1B}[201~".utf8)
  private static let maximumSequenceByteCount = 65536
  private var buffer: [UInt8] = []
  private var csiSearchOffset = 2, pasteEndSearchOffset = Self.pasteStart.count
  private var isDiscardingOversizedPaste = false
  private init(suppressingDefaultInitializer: Void) {}

  /// Adds bytes without discarding an incomplete event already in the buffer.
  package mutating func append(_ bytes: [UInt8]) {
    buffer.append(contentsOf: bytes)
    _ = isDiscardingOversizedPaste && discardOversizedPasteBytes()
  }

  /// Removes and returns the next complete event.
  package mutating func nextEvent() -> InputEvent? {
    while buffer.isEmpty == false {
      if isDiscardingOversizedPaste {
        guard discardOversizedPasteBytes() else { return nil }
        continue
      }
      if buffer[0] == Self.escape {
        guard let event = parseEscapeSequence() else { return nil }
        if let event {
          return event
        }
      } else {
        guard let event = parseKey() else { return nil }
        if let event {
          return .key(event)
        }
      }
    }
    return nil
  }

  /// Returns a single buffered Escape key after the input source becomes idle.
  package mutating func takeStandaloneEscape() -> InputEvent? {
    guard buffer == [Self.escape] else { return nil }
    buffer.removeAll(keepingCapacity: true)
    resetSearchOffsets()
    return .key(KeyEvent(key: .escape))
  }

  /// Whether the parser retains bytes that may produce another event.
  package var hasBufferedInput: Bool {
    buffer.isEmpty == false
  }

  /// Whether the only buffered byte is an ambiguous Escape key.
  package var hasStandaloneEscape: Bool {
    isDiscardingOversizedPaste == false && buffer == [Self.escape]
  }
}

extension TerminalInputParser {
  /// A parse step distinguishes incomplete input from ignored input.
  fileprivate typealias ParseStep = InputEvent??

  private mutating func parseEscapeSequence() -> ParseStep {
    guard buffer.count >= 2 else { return nil }
    switch buffer[1] {
    case Self.csi: return parseCSISequence()
    case Self.ss3:
      guard buffer.count >= 3 else { return nil }
      return consumeKey(byteCount: 3)
    default: return consumeKey(byteCount: 2)
    }
  }

  private mutating func parseCSISequence() -> ParseStep {
    guard buffer.count >= 3 else { return nil }
    let searchStart = min(max(2, csiSearchOffset), buffer.count)
    guard let finalIndex = buffer[searchStart...].firstIndex(where: { (0x40 ... 0x7E).contains($0) }) else {
      csiSearchOffset = buffer.count
      if buffer.count >= Self.maximumSequenceByteCount {
        discardOversizedCSISequence()
        return .some(nil)
      }
      return nil
    }
    guard finalIndex < Self.maximumSequenceByteCount else {
      discardPrefix(byteCount: finalIndex + 1)
      return .some(nil)
    }
    let sequence = Array(buffer[...finalIndex])
    if sequence == Self.pasteStart {
      return parseBracketedPaste()
    }
    consume(byteCount: finalIndex + 1)
    if let mouseEvent = parseMouseEvent(sequence) {
      return .some(.mouse(mouseEvent))
    }
    return .some(KeyEvent.parse(sequence).map(InputEvent.key))
  }

  private mutating func parseBracketedPaste() -> ParseStep {
    guard let endRange = findPasteEnd() else {
      let possibleMarkerByteCount = matchingPasteEndPrefixByteCount()
      let contentByteCount = buffer.count - Self.pasteStart.count - possibleMarkerByteCount
      if contentByteCount > Self.maximumSequenceByteCount {
        isDiscardingOversizedPaste = true
        discardOversizedPasteBytes()
        return .some(nil)
      }
      return nil
    }
    let contentByteCount = endRange.lowerBound - Self.pasteStart.count
    guard contentByteCount <= Self.maximumSequenceByteCount else {
      discardPrefix(byteCount: endRange.upperBound)
      return .some(nil)
    }
    let content = buffer[Self.pasteStart.count ..< endRange.lowerBound]
    let text = String(decoding: content, as: UTF8.self)
    consume(byteCount: endRange.upperBound)
    return .some(.key(KeyEvent(key: .paste(text))))
  }

  private mutating func parseKey() -> KeyEvent?? {
    guard let byteCount = utf8ByteCount(for: buffer[0]) else {
      consume(byteCount: 1)
      return .some(nil)
    }
    guard buffer.count >= byteCount else { return nil }
    let bytes = Array(buffer.prefix(byteCount))
    consume(byteCount: byteCount)
    return .some(KeyEvent.parse(bytes))
  }

  private mutating func consumeKey(byteCount: Int) -> ParseStep {
    let bytes = Array(buffer.prefix(byteCount))
    consume(byteCount: byteCount)
    return .some(KeyEvent.parse(bytes).map(InputEvent.key))
  }

  private mutating func consume(byteCount: Int) {
    buffer.removeFirst(byteCount)
    resetSearchOffsets()
  }

  private mutating func discardOversizedCSISequence() {
    if let nextEscapeIndex = buffer.dropFirst().firstIndex(of: Self.escape) {
      discardPrefix(byteCount: nextEscapeIndex)
    } else {
      buffer = []
      resetSearchOffsets()
    }
  }

  @discardableResult
  private mutating func discardOversizedPasteBytes() -> Bool {
    if let endRange = range(of: Self.pasteEnd, startingAt: 0) {
      discardPrefix(byteCount: endRange.upperBound)
      isDiscardingOversizedPaste = false
      return true
    }
    let suffixByteCount = matchingPasteEndPrefixByteCount()
    buffer = Array(buffer.suffix(suffixByteCount))
    pasteEndSearchOffset = 0
    return false
  }

  private mutating func discardPrefix(byteCount: Int) {
    buffer = Array(buffer.dropFirst(byteCount))
    resetSearchOffsets()
  }

  private mutating func resetSearchOffsets() {
    csiSearchOffset = 2
    pasteEndSearchOffset = Self.pasteStart.count
  }

  private mutating func findPasteEnd() -> Range<Int>? {
    let lastStart = buffer.count - Self.pasteEnd.count
    guard lastStart >= Self.pasteStart.count else { return nil }
    let searchStart = min(max(Self.pasteStart.count, pasteEndSearchOffset), lastStart)
    if let result = range(of: Self.pasteEnd, startingAt: searchStart) {
      return result
    }
    pasteEndSearchOffset = max(Self.pasteStart.count, lastStart + 1)
    return nil
  }

  private func matchingPasteEndPrefixByteCount() -> Int {
    let maximumLength = min(buffer.count, Self.pasteEnd.count - 1)
    guard maximumLength > 0 else { return 0 }
    for length in stride(from: maximumLength, through: 1, by: -1) where buffer.suffix(length).elementsEqual(Self.pasteEnd.prefix(length)) {
      return length
    }
    return 0
  }

  private func parseMouseEvent(_ sequence: [UInt8]) -> MouseEvent? {
    guard sequence.count >= 7, sequence.starts(with: [Self.escape, Self.csi, 0x3C]), let finalByte = sequence.last, finalByte == 0x4D || finalByte == 0x6D else { return nil }
    let parameterBytes = sequence[3 ..< (sequence.count - 1)]
    guard let parameters = String(bytes: parameterBytes, encoding: .ascii) else { return nil }
    let values = parameters.split(separator: ";", omittingEmptySubsequences: false)
    guard values.count == 3, let code = Int(values[0]), code >= 0, code <= 127, let sgrColumn = Int(values[1]), let sgrRow = Int(values[2]), sgrColumn > 0, sgrRow > 0, let action = mouseAction(code: code, finalByte: finalByte) else { return nil }
    return MouseEvent(action: action, column: sgrColumn - 1, row: sgrRow - 1, ctrl: code & 16 != 0, alt: code & 8 != 0, shift: code & 4 != 0)
  }

  private func mouseAction(code: Int, finalByte: UInt8) -> MouseEvent.Action? {
    let buttonCode = code & 3
    if code & 64 != 0 {
      let direction: MouseEvent.ScrollDirection = switch buttonCode {
      case 0: .up
      case 1: .down
      case 2: .left
      default: .right
      }
      return .scroll(direction)
    }
    guard let button = mouseButton(code: buttonCode) else { return code & 32 != 0 && finalByte == 0x4D ? .move : nil }
    return finalByte == 0x6D ? .release(button) : code & 32 != 0 ? .drag(button) : .press(button)
  }

  private func mouseButton(code: Int) -> MouseEvent.Button? {
    switch code {
    case 0: .left
    case 1: .middle
    case 2: .right
    default: nil
    }
  }

  private func utf8ByteCount(for byte: UInt8) -> Int? {
    switch byte {
    case 0x00 ... 0x7F: 1
    case 0xC2 ... 0xDF: 2
    case 0xE0 ... 0xEF: 3
    case 0xF0 ... 0xF4: 4
    default: nil
    }
  }

  private func range(of marker: [UInt8], startingAt start: Int) -> Range<Int>? {
    guard buffer.count >= start + marker.count else { return nil }
    for index in start ... (buffer.count - marker.count) where buffer[index ..< (index + marker.count)].elementsEqual(marker) {
      return index ..< (index + marker.count)
    }
    return nil
  }
}
