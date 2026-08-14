/// Incrementally parses terminal input without performing I/O.
public struct TerminalInputParser: Sendable {
  private static let escape: UInt8 = 0x1B
  private static let pasteStart = Array("\u{1B}[200~".utf8)
  private static let pasteEnd = Array("\u{1B}[201~".utf8)

  private enum State: Sendable {
    case normal
    case paste
    case discardingPaste
  }

  private enum KeyParseResult {
    case incomplete
    case key(TerminalKeyEvent, byteCount: Int)
    case invalid([UInt8], byteCount: Int)
  }

  private let configuration: TerminalInputParserConfiguration
  private var buffer: [UInt8] = []
  private var offset = 0
  private var state: State = .normal

  /// Creates a terminal input parser.
  public init(configuration: TerminalInputParserConfiguration = TerminalInputParserConfiguration()) {
    self.configuration = configuration
    buffer.reserveCapacity(min(configuration.maximumSequenceByteCount, 4096))
  }

  /// Adds bytes and returns all complete events and recoverable errors.
  ///
  /// - Complexity: O(n), where n is the buffered input size.
  public mutating func append(_ bytes: [UInt8]) -> TerminalInputParserOutput {
    compactBeforeAppend()
    buffer.append(contentsOf: bytes)
    return processAvailableInput()
  }

  /// Emits an Escape key when Escape is the only buffered byte.
  ///
  /// Call this method when the runtime's Escape-key deadline expires.
  public mutating func resolveAmbiguousEscape() -> TerminalInputParserOutput {
    guard case .normal = state, buffer.count - offset == 1, buffer[offset] == Self.escape else {
      return TerminalInputParserOutput()
    }
    offset += 1
    compactConsumedBytes()
    return TerminalInputParserOutput(events: [.key(TerminalKeyEvent(key: .escape))])
  }

  /// Finishes the stream and reports any incomplete sequence.
  ///
  /// - Complexity: O(n), where n is the buffered input size.
  public mutating func finish() -> TerminalInputParserOutput {
    var output = processAvailableInput()
    let remaining = Array(buffer.dropFirst(offset))
    switch state {
    case .normal where remaining == [Self.escape]:
      output.events.append(.key(TerminalKeyEvent(key: .escape)))
    case .normal where remaining.isEmpty:
      break
    case .normal:
      output.errors.append(.incompleteSequence(remaining))
    case .paste, .discardingPaste:
      output.errors.append(.incompleteSequence(remaining))
    }
    buffer.removeAll(keepingCapacity: true)
    offset = 0
    state = .normal
    return output
  }

  /// Whether the parser has incomplete input.
  public var hasBufferedInput: Bool {
    offset < buffer.count || state != .normal
  }

  private mutating func processAvailableInput() -> TerminalInputParserOutput {
    var output = TerminalInputParserOutput()
    var madeProgress = true
    while madeProgress {
      madeProgress = false
      switch state {
      case .normal:
        while offset < buffer.count {
          let previousOffset = offset
          parseNormalInput(into: &output)
          guard offset != previousOffset || state != .normal else { break }
          madeProgress = true
          guard case .normal = state else { break }
        }
      case .paste:
        madeProgress = parsePaste(into: &output)
      case .discardingPaste:
        madeProgress = discardPasteRemainder()
      }
    }
    compactConsumedBytes()
    return output
  }

  private mutating func parseNormalInput(into output: inout TerminalInputParserOutput) {
    if buffer[offset] != Self.escape {
      consumeKey(at: offset, additionalModifiers: [], into: &output)
      return
    }

    guard offset + 1 < buffer.count else { return }
    switch buffer[offset + 1] {
    case 0x5B:
      parseCSI(into: &output)
    case 0x4F:
      parseSS3(into: &output)
    case Self.escape:
      offset += 2
      output.events.append(.key(TerminalKeyEvent(key: .escape, modifiers: .alt)))
    default:
      offset += 1
      consumeKey(at: offset, additionalModifiers: .alt, into: &output)
    }
  }

  private mutating func consumeKey(
    at index: Int,
    additionalModifiers: TerminalKeyModifiers,
    into output: inout TerminalInputParserOutput
  ) {
    switch parseKey(at: index) {
    case .incomplete:
      return
    case let .key(event, byteCount):
      offset = index + byteCount
      var event = event
      event.modifiers.formUnion(additionalModifiers)
      output.events.append(.key(event))
    case let .invalid(bytes, byteCount):
      offset = index + byteCount
      output.errors.append(.invalidUTF8(bytes))
    }
  }

  private mutating func parseCSI(into output: inout TerminalInputParserOutput) {
    let sequenceStart = offset
    var finalIndex = sequenceStart + 2
    while finalIndex < buffer.count, (0x40 ... 0x7E).contains(buffer[finalIndex]) == false {
      finalIndex += 1
      if finalIndex - sequenceStart > configuration.maximumSequenceByteCount {
        discardOversizedSequence(into: &output)
        return
      }
    }
    guard finalIndex < buffer.count else {
      if buffer.count - sequenceStart > configuration.maximumSequenceByteCount {
        discardOversizedSequence(into: &output)
      }
      return
    }

    let byteCount = finalIndex - sequenceStart + 1
    guard byteCount <= configuration.maximumSequenceByteCount else {
      offset = finalIndex + 1
      output.errors.append(.sequenceTooLong(limit: configuration.maximumSequenceByteCount))
      return
    }

    let sequence = Array(buffer[sequenceStart ... finalIndex])
    offset = finalIndex + 1
    if sequence == Self.pasteStart {
      state = .paste
      return
    }
    if let event = parseCSISequence(sequence) {
      output.events.append(event)
    } else if sequence.starts(with: [Self.escape, 0x5B, 0x3C]) {
      output.errors.append(.invalidMouseSequence(sequence))
    } else if sequence.last == 0x75, configuration.enablesKittyKeyboard {
      output.errors.append(.invalidKittyKeyboardSequence(sequence))
    } else {
      output.errors.append(.unknownEscapeSequence(sequence))
    }
  }

  private mutating func parseSS3(into output: inout TerminalInputParserOutput) {
    guard offset + 2 < buffer.count else { return }
    let sequence = Array(buffer[offset ... (offset + 2)])
    offset += 3
    let key: TerminalKey? =
      switch sequence[2] {
      case 0x41: .up
      case 0x42: .down
      case 0x43: .right
      case 0x44: .left
      case 0x48: .home
      case 0x46: .end
      case 0x50: .function(1)
      case 0x51: .function(2)
      case 0x52: .function(3)
      case 0x53: .function(4)
      default: nil
      }
    if let key {
      output.events.append(.key(TerminalKeyEvent(key: key)))
    } else {
      output.errors.append(.unknownEscapeSequence(sequence))
    }
  }

  private mutating func parsePaste(into output: inout TerminalInputParserOutput) -> Bool {
    if let end = range(of: Self.pasteEnd, startingAt: offset) {
      let payload = buffer[offset ..< end.lowerBound]
      guard payload.count <= configuration.maximumPasteByteCount else {
        offset = end.upperBound
        state = .normal
        output.errors.append(.pasteTooLarge(limit: configuration.maximumPasteByteCount))
        return true
      }
      offset = end.upperBound
      state = .normal
      output.events.append(.paste(String(decoding: payload, as: UTF8.self)))
      return true
    }

    let markerPrefixCount = matchingSuffixPrefixCount(for: Self.pasteEnd, startingAt: offset)
    let completePayloadCount = buffer.count - offset - markerPrefixCount
    guard completePayloadCount > configuration.maximumPasteByteCount else { return false }

    output.errors.append(.pasteTooLarge(limit: configuration.maximumPasteByteCount))
    state = .discardingPaste
    buffer = Array(buffer.suffix(markerPrefixCount))
    offset = 0
    return true
  }

  private mutating func discardPasteRemainder() -> Bool {
    if let end = range(of: Self.pasteEnd, startingAt: offset) {
      offset = end.upperBound
      state = .normal
      return true
    }
    let markerPrefixCount = matchingSuffixPrefixCount(for: Self.pasteEnd, startingAt: offset)
    buffer = Array(buffer.suffix(markerPrefixCount))
    offset = 0
    return false
  }

  private mutating func discardOversizedSequence(into output: inout TerminalInputParserOutput) {
    output.errors.append(.sequenceTooLong(limit: configuration.maximumSequenceByteCount))
    if let nextEscape = buffer[(offset + 1)...].firstIndex(of: Self.escape) {
      offset = nextEscape
    } else {
      offset = buffer.count
    }
  }
}

extension TerminalInputParser {
  private func parseCSISequence(_ sequence: [UInt8]) -> TerminalInputEvent? {
    guard let finalByte = sequence.last else { return nil }
    let body = sequence[2 ..< (sequence.count - 1)]

    if finalByte == 0x4D || finalByte == 0x6D, body.first == 0x3C {
      return parseMouse(sequence, body: body.dropFirst(), finalByte: finalByte).map(TerminalInputEvent.mouse)
    }
    if finalByte == 0x49, body.isEmpty {
      return .focus(.gained)
    }
    if finalByte == 0x4F, body.isEmpty {
      return .focus(.lost)
    }
    if finalByte == 0x75, configuration.enablesKittyKeyboard {
      return parseKittyKey(body).map(TerminalInputEvent.key)
    }

    let parameters = parseIntegerParameters(body)
    let modifiers = xtermModifiers(from: parameters.count > 1 ? parameters[1] : nil)
    let key: TerminalKey? =
      switch finalByte {
      case 0x41: .up
      case 0x42: .down
      case 0x43: .right
      case 0x44: .left
      case 0x48: .home
      case 0x46: .end
      case 0x5A: .tab
      case 0x7E: tildeKey(parameters.first)
      default: nil
      }
    return key.map { .key(TerminalKeyEvent(key: $0, modifiers: finalByte == 0x5A ? [.shift] : modifiers)) }
  }

  private func parseMouse(
    _ sequence: [UInt8],
    body: ArraySlice<UInt8>,
    finalByte: UInt8
  ) -> TerminalMouseEvent? {
    let values = parseIntegerParameters(body)
    guard values.count == 3,
          let code = values[0], code >= 0, code <= 255,
          let column = values[1], column > 0,
          let row = values[2], row > 0
    else { return nil }

    var modifiers: TerminalKeyModifiers = []
    if code & 4 != 0 {
      modifiers.insert(.shift)
    }
    if code & 8 != 0 {
      modifiers.insert(.alt)
    }
    if code & 16 != 0 {
      modifiers.insert(.control)
    }
    guard let action = mouseAction(code: code, finalByte: finalByte) else { return nil }
    _ = sequence
    return TerminalMouseEvent(
      action: action,
      position: TerminalCellPoint(column: column - 1, row: row - 1),
      modifiers: modifiers
    )
  }

  private func mouseAction(code: Int, finalByte: UInt8) -> TerminalMouseAction? {
    let buttonCode = code & 3
    if code & 64 != 0 {
      let direction: TerminalScrollDirection =
        switch buttonCode {
        case 0: .up
        case 1: .down
        case 2: .left
        default: .right
        }
      return .scroll(direction)
    }
    if finalByte == 0x6D {
      return .release(mouseButton(code: buttonCode))
    }
    if code & 32 != 0 {
      return mouseButton(code: buttonCode).map(TerminalMouseAction.drag) ?? .move
    }
    return mouseButton(code: buttonCode).map(TerminalMouseAction.press)
  }

  private func mouseButton(code: Int) -> TerminalMouseButton? {
    switch code {
    case 0: .left
    case 1: .middle
    case 2: .right
    default: nil
    }
  }

  private func parseKittyKey(_ body: ArraySlice<UInt8>) -> TerminalKeyEvent? {
    let fields = split(body, separator: 0x3B)
    guard let firstField = fields.first, let codePoint = integer(before: 0x3A, in: firstField) else { return nil }

    let modifierField = fields.count > 1 ? fields[1] : []
    let modifierParts = split(modifierField, separator: 0x3A)
    let modifiers = kittyModifiers(from: modifierParts.first.flatMap(parseInteger))
    let action: TerminalKeyAction =
      switch modifierParts.count > 1 ? parseInteger(modifierParts[1]) : 1 {
      case 2: .repeat
      case 3: .release
      default: .press
      }
    guard let key = kittyKey(codePoint: codePoint) else { return nil }
    return TerminalKeyEvent(key: key, modifiers: modifiers, action: action)
  }

  private func kittyKey(codePoint: Int) -> TerminalKey? {
    switch codePoint {
    case 13: .enter
    case 27, 57344: .escape
    case 9, 57346: .tab
    case 8, 127, 57347: .backspace
    case 57345: .enter
    case 57348: .insert
    case 57349: .delete
    case 57350: .left
    case 57351: .right
    case 57352: .up
    case 57353: .down
    case 57354: .pageUp
    case 57355: .pageDown
    case 57356: .home
    case 57357: .end
    case 57364 ... 57398: .function(codePoint - 57363)
    default:
      UnicodeScalar(codePoint).map { .text(String(Character($0))) }
    }
  }

  private func tildeKey(_ parameter: Int??) -> TerminalKey? {
    guard case let .some(.some(parameter)) = parameter else { return nil }
    return switch parameter {
    case 1, 7: .home
    case 2: .insert
    case 3: .delete
    case 4, 8: .end
    case 5: .pageUp
    case 6: .pageDown
    case 11 ... 15: .function(parameter - 10)
    case 17 ... 21: .function(parameter - 11)
    case 23, 24: .function(parameter - 12)
    default: nil
    }
  }

  private func xtermModifiers(from encoded: Int?) -> TerminalKeyModifiers {
    guard let encoded, encoded > 0 else { return [] }
    return modifiers(fromBitField: encoded - 1)
  }

  private func kittyModifiers(from encoded: Int?) -> TerminalKeyModifiers {
    guard let encoded, encoded > 0 else { return [] }
    return modifiers(fromBitField: encoded - 1)
  }

  private func modifiers(fromBitField value: Int) -> TerminalKeyModifiers {
    var result: TerminalKeyModifiers = []
    if value & 1 != 0 {
      result.insert(.shift)
    }
    if value & 2 != 0 {
      result.insert(.alt)
    }
    if value & 4 != 0 {
      result.insert(.control)
    }
    if value & 8 != 0 {
      result.insert(.super)
    }
    if value & 16 != 0 {
      result.insert(.hyper)
    }
    if value & 32 != 0 {
      result.insert(.meta)
    }
    if value & 64 != 0 {
      result.insert(.capsLock)
    }
    if value & 128 != 0 {
      result.insert(.numLock)
    }
    return result
  }
}

extension TerminalInputParser {
  private func parseKey(at index: Int) -> KeyParseResult {
    let first = buffer[index]
    switch first {
    case 0x00:
      return .key(TerminalKeyEvent(key: .text(" "), modifiers: .control), byteCount: 1)
    case 0x09:
      return .key(TerminalKeyEvent(key: .tab), byteCount: 1)
    case 0x0A, 0x0D:
      return .key(TerminalKeyEvent(key: .enter), byteCount: 1)
    case 0x01 ... 0x08, 0x0B, 0x0C, 0x0E ... 0x1A:
      let character = Character(UnicodeScalar(first + 0x60))
      return .key(TerminalKeyEvent(key: .text(String(character)), modifiers: .control), byteCount: 1)
    case 0x1C ... 0x1F:
      let character = Character(UnicodeScalar(first + 0x40))
      return .key(TerminalKeyEvent(key: .text(String(character)), modifiers: .control), byteCount: 1)
    case 0x7F:
      return .key(TerminalKeyEvent(key: .backspace), byteCount: 1)
    case 0x20 ... 0x7E:
      return .key(TerminalKeyEvent(key: .text(String(Character(UnicodeScalar(first))))), byteCount: 1)
    default:
      break
    }

    guard let byteCount = utf8ByteCount(for: first) else {
      return .invalid([first], byteCount: 1)
    }
    guard index + byteCount <= buffer.count else {
      return hasValidUTF8Prefix(at: index, expectedByteCount: byteCount) ? .incomplete : .invalid([first], byteCount: 1)
    }
    let bytes = Array(buffer[index ..< (index + byteCount)])
    guard isValidUTF8Scalar(bytes) else { return .invalid([first], byteCount: 1) }
    return .key(TerminalKeyEvent(key: .text(String(decoding: bytes, as: UTF8.self))), byteCount: byteCount)
  }

  private func utf8ByteCount(for first: UInt8) -> Int? {
    switch first {
    case 0xC2 ... 0xDF: 2
    case 0xE0 ... 0xEF: 3
    case 0xF0 ... 0xF4: 4
    default: nil
    }
  }

  private func hasValidUTF8Prefix(at index: Int, expectedByteCount: Int) -> Bool {
    let available = min(expectedByteCount, buffer.count - index)
    guard available > 1 else { return true }
    let prefix = Array(buffer[index ..< (index + available)])
    return isValidUTF8Prefix(prefix, expectedByteCount: expectedByteCount)
  }

  private func isValidUTF8Prefix(_ bytes: [UInt8], expectedByteCount: Int) -> Bool {
    guard bytes.count <= expectedByteCount else { return false }
    for byte in bytes.dropFirst() where (0x80 ... 0xBF).contains(byte) == false {
      return false
    }
    guard bytes.count > 1 else { return true }
    switch bytes[0] {
    case 0xE0: return bytes[1] >= 0xA0
    case 0xED: return bytes[1] <= 0x9F
    case 0xF0: return bytes[1] >= 0x90
    case 0xF4: return bytes[1] <= 0x8F
    default: return true
    }
  }

  private func isValidUTF8Scalar(_ bytes: [UInt8]) -> Bool {
    isValidUTF8Prefix(bytes, expectedByteCount: bytes.count)
  }

  private func parseIntegerParameters(_ bytes: ArraySlice<UInt8>) -> [Int?] {
    split(bytes, separator: 0x3B).map(parseInteger)
  }

  private func parseInteger(_ bytes: ArraySlice<UInt8>) -> Int? {
    guard bytes.isEmpty == false else { return nil }
    return Int(String(decoding: bytes, as: UTF8.self))
  }

  private func integer(before separator: UInt8, in bytes: ArraySlice<UInt8>) -> Int? {
    parseInteger(bytes.prefix { $0 != separator })
  }

  private func split(_ bytes: ArraySlice<UInt8>, separator: UInt8) -> [ArraySlice<UInt8>] {
    var result: [ArraySlice<UInt8>] = []
    var start = bytes.startIndex
    for index in bytes.indices where bytes[index] == separator {
      result.append(bytes[start ..< index])
      start = bytes.index(after: index)
    }
    result.append(bytes[start ..< bytes.endIndex])
    return result
  }

  private func range(of marker: [UInt8], startingAt start: Int) -> Range<Int>? {
    guard buffer.count >= start + marker.count else { return nil }
    for index in start ... (buffer.count - marker.count)
      where buffer[index ..< (index + marker.count)].elementsEqual(marker)
    {
      return index ..< (index + marker.count)
    }
    return nil
  }

  private func matchingSuffixPrefixCount(for marker: [UInt8], startingAt start: Int) -> Int {
    let maximumCount = min(buffer.count - start, marker.count - 1)
    guard maximumCount > 0 else { return 0 }
    for count in stride(from: maximumCount, through: 1, by: -1)
      where buffer.suffix(count).elementsEqual(marker.prefix(count))
    {
      return count
    }
    return 0
  }

  private mutating func compactBeforeAppend() {
    guard case .normal = state, offset > 0 else { return }
    buffer = Array(buffer.dropFirst(offset))
    offset = 0
  }

  private mutating func compactConsumedBytes() {
    guard case .normal = state else { return }
    if offset == buffer.count {
      buffer.removeAll(keepingCapacity: true)
      offset = 0
    } else if offset > 4096, offset > buffer.count / 2 {
      buffer = Array(buffer.dropFirst(offset))
      offset = 0
    }
  }
}
