import Foundation

/// A Markdown parsing diagnostic at a UTF-8 byte range.
public struct MarkdownDiagnostic: Sendable, Hashable {
  /// The source range associated with the diagnostic.
  public let range: TextRange
  /// The diagnostic message.
  public let message: String

  /// Creates a Markdown diagnostic.
  public init(range: TextRange, message: String) {
    self.range = range
    self.message = message
  }
}

/// A parsed Markdown list item.
public struct MarkdownListItem: Sendable, Hashable {
  /// The ordered-list number, or `nil` for an unordered item.
  public let ordinal: Int?
  /// The styled item content.
  public let content: StyledText

  /// Creates a Markdown list item.
  public init(content: StyledText, ordinal: Int? = nil) {
    self.ordinal = ordinal
    self.content = content
  }
}

/// The horizontal alignment of a Markdown table column.
public enum MarkdownTableAlignment: Sendable, Hashable {
  /// Aligns content to the leading edge.
  case leading
  /// Centers content.
  case center
  /// Aligns content to the trailing edge.
  case trailing
}

/// A parsed Markdown table.
public struct MarkdownTable: Sendable, Hashable {
  /// The styled column headers.
  public let headers: [StyledText]
  /// The alignment of each column.
  public let alignments: [MarkdownTableAlignment]
  /// The styled body rows.
  public let rows: [[StyledText]]

  /// Creates a Markdown table.
  public init(headers: [StyledText], alignments: [MarkdownTableAlignment], rows: [[StyledText]]) {
    self.headers = headers
    self.alignments = alignments
    self.rows = rows
  }
}

/// A parsed fenced code block.
public struct MarkdownCodeFence: Sendable, Hashable {
  /// The code inside the fence.
  public let code: String
  /// The optional language information string.
  public let language: String?
  /// A Boolean value that indicates whether the closing fence was present.
  public let isClosed: Bool

  /// Creates a Markdown code fence.
  public init(code: String, isClosed: Bool, language: String? = nil) {
    self.code = code
    self.language = language
    self.isClosed = isClosed
  }
}

/// The content represented by a parsed Markdown block.
public enum MarkdownBlockKind: Sendable, Hashable {
  /// A heading with its level and styled content.
  case heading(level: Int, content: StyledText)
  /// A paragraph.
  case paragraph(StyledText)
  /// An unordered list.
  case unorderedList([MarkdownListItem])
  /// An ordered list.
  case orderedList([MarkdownListItem])
  /// A block quote.
  case blockQuote(StyledText)
  /// A fenced code block.
  case codeFence(MarkdownCodeFence)
  /// A horizontal rule.
  case horizontalRule
  /// A table.
  case table(MarkdownTable)
}

/// A Markdown block and its source range.
public struct MarkdownBlock: Sendable, Hashable {
  /// The block's UTF-8 source range.
  public let range: TextRange
  /// The parsed block content.
  public let kind: MarkdownBlockKind

  /// Creates a Markdown block.
  public init(range: TextRange, kind: MarkdownBlockKind) {
    self.range = range
    self.kind = kind
  }
}

/// A normalized Markdown source and its parsed blocks.
public struct MarkdownDocument: Sendable, Hashable {
  /// The source with normalized line endings.
  public let source: String
  /// The parsed blocks.
  public let blocks: [MarkdownBlock]
  /// The diagnostics produced during parsing.
  public let diagnostics: [MarkdownDiagnostic]

  /// Creates a Markdown document.
  public init(source: String, blocks: [MarkdownBlock], diagnostics: [MarkdownDiagnostic] = []) {
    self.source = source
    self.blocks = blocks
    self.diagnostics = diagnostics
  }
}

/// The result of an incremental Markdown parse.
public struct MarkdownParseResult: Sendable, Hashable {
  /// The updated document.
  public let document: MarkdownDocument
  /// The UTF-8 source range parsed during the update.
  public let reparsedRange: TextRange

  /// Creates an incremental parse result.
  public init(document: MarkdownDocument, reparsedRange: TextRange) {
    self.document = document
    self.reparsedRange = reparsedRange
  }
}

/// An error produced while applying an incremental Markdown edit.
public enum MarkdownEditError: Error, Sendable, Equatable {
  /// The edit range is outside the source or splits a UTF-8 scalar.
  case invalidUTF8Range(TextRange)
}

/// A parser for the supported Markdown block and inline syntax.
public struct MarkdownParser: Sendable {
  /// Creates a Markdown parser.
  public init() {}

  /// Parses a complete Markdown source.
  /// - Complexity: O(*n*), where *n* is the source length.
  public func parse(_ source: String) -> MarkdownDocument {
    let normalizedSource = normalizedLineEndings(in: source)
    let parsed = parseBlocks(normalizedSource, offset: 0)
    return MarkdownDocument(source: normalizedSource, blocks: parsed.blocks, diagnostics: parsed.diagnostics)
  }

  /// Replaces a UTF-8 range and reparses the affected tail of the document.
  /// - Complexity: O(*n*), where *n* is the updated source length.
  public func reparseTail(
    of previous: MarkdownDocument,
    replacing changedRange: TextRange,
    with replacement: String
  ) throws -> MarkdownParseResult {
    let bytes = Array(previous.source.utf8)
    guard changedRange.upperBound <= bytes.count,
          isUTF8Boundary(changedRange.lowerBound, in: bytes),
          isUTF8Boundary(changedRange.upperBound, in: bytes)
    else {
      throw MarkdownEditError.invalidUTF8Range(changedRange)
    }

    let newSource =
      String(decoding: bytes[..<changedRange.lowerBound], as: UTF8.self)
        + normalizedLineEndings(in: replacement)
        + String(decoding: bytes[changedRange.upperBound...], as: UTF8.self)
    let start = affectedTailStart(in: previous, changedRange: changedRange)
    let prefixBlocks = previous.blocks.filter { $0.range.upperBound <= start }
    let prefixDiagnostics = previous.diagnostics.filter { $0.range.upperBound <= start }
    let suffixBytes = Array(newSource.utf8)[start...]
    let parsed = parseBlocks(String(decoding: suffixBytes, as: UTF8.self), offset: start)
    let document = MarkdownDocument(
      source: newSource,
      blocks: prefixBlocks + parsed.blocks,
      diagnostics: prefixDiagnostics + parsed.diagnostics
    )
    return MarkdownParseResult(
      document: document,
      reparsedRange: TextRange(start, newSource.utf8.count)
    )
  }

  private func affectedTailStart(in document: MarkdownDocument, changedRange: TextRange) -> Int {
    let bytes = Array(document.source.utf8)
    var lineStart = Swift.min(changedRange.lowerBound, bytes.count)
    while lineStart > 0, bytes[lineStart - 1] != 0x0A {
      lineStart -= 1
    }

    if changedRange.lowerBound == bytes.count,
       bytes.suffix(2) != [0x0A, 0x0A],
       let last = document.blocks.last
    {
      return last.range.lowerBound
    }
    let candidate =
      document.blocks.last(where: {
        $0.range.lowerBound <= lineStart && $0.range.upperBound > lineStart
      })?.range.lowerBound ?? lineStart
    if let previous = document.blocks.last(where: { $0.range.upperBound <= candidate }),
       previous.range.upperBound == candidate
    {
      return previous.range.lowerBound
    }
    return candidate
  }

  private func normalizedLineEndings(in source: String) -> String {
    source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
  }

  private func parseBlocks(_ source: String, offset: Int) -> (blocks: [MarkdownBlock], diagnostics: [MarkdownDiagnostic]) {
    let lines = MarkdownLine.lines(in: source, offset: offset)
    var blocks: [MarkdownBlock] = []
    var diagnostics: [MarkdownDiagnostic] = []
    var index = 0

    while index < lines.count {
      let line = lines[index]
      if line.content.trimmingCharacters(in: .whitespaces).isEmpty {
        index += 1
        continue
      }

      if let fence = fenceOpening(line.content) {
        let start = line.range.lowerBound
        var codeLines: [String] = []
        var end = line.range.upperBound
        var isClosed = false
        index += 1
        while index < lines.count {
          let candidate = lines[index]
          if isFenceClosing(candidate.content, marker: fence.marker, count: fence.count) {
            end = candidate.range.upperBound
            isClosed = true
            index += 1
            break
          }
          codeLines.append(candidate.content)
          end = candidate.range.upperBound
          index += 1
        }
        if isClosed == false {
          diagnostics.append(
            MarkdownDiagnostic(range: TextRange(start, end), message: "Unclosed fenced code block")
          )
        }
        blocks.append(
          MarkdownBlock(
            range: TextRange(start, end),
            kind: .codeFence(
              MarkdownCodeFence(
                code: codeLines.joined(separator: "\n"),
                isClosed: isClosed,
                language: fence.info.isEmpty ? nil : fence.info
              )
            )
          )
        )
        continue
      }

      if let heading = heading(line.content) {
        blocks.append(
          MarkdownBlock(
            range: line.range,
            kind: .heading(
              level: heading.level,
              content: parseInline(heading.content, baseRole: .heading(heading.level))
            )
          )
        )
        index += 1
        continue
      }

      if isHorizontalRule(line.content) {
        blocks.append(MarkdownBlock(range: line.range, kind: .horizontalRule))
        index += 1
        continue
      }

      if let table = parseTable(lines, at: index) {
        blocks.append(table.block)
        index = table.nextIndex
        continue
      }

      if quoteContent(line.content) != nil {
        let start = line.range.lowerBound
        var end = line.range.upperBound
        var content: [String] = []
        while index < lines.count, let quote = quoteContent(lines[index].content) {
          content.append(quote)
          end = lines[index].range.upperBound
          index += 1
        }
        blocks.append(
          MarkdownBlock(
            range: TextRange(start, end),
            kind: .blockQuote(parseInline(content.joined(separator: "\n")))
          )
        )
        continue
      }

      if let item = listItem(line.content) {
        let ordered = item.ordinal != nil
        let start = line.range.lowerBound
        var end = line.range.upperBound
        var items: [MarkdownListItem] = []
        while index < lines.count, let next = listItem(lines[index].content), (next.ordinal != nil) == ordered {
          items.append(MarkdownListItem(content: parseInline(next.content), ordinal: next.ordinal))
          end = lines[index].range.upperBound
          index += 1
        }
        blocks.append(
          MarkdownBlock(
            range: TextRange(start, end),
            kind: ordered ? .orderedList(items) : .unorderedList(items)
          )
        )
        continue
      }

      let start = line.range.lowerBound
      var end = line.range.upperBound
      var content: [String] = [line.content]
      index += 1
      while index < lines.count,
            lines[index].content.trimmingCharacters(in: .whitespaces).isEmpty == false,
            startsBlock(lines, at: index) == false
      {
        content.append(lines[index].content)
        end = lines[index].range.upperBound
        index += 1
      }
      blocks.append(
        MarkdownBlock(
          range: TextRange(start, end),
          kind: .paragraph(parseInline(content.joined(separator: " ")))
        )
      )
    }
    return (blocks, diagnostics)
  }

  private func startsBlock(_ lines: [MarkdownLine], at index: Int) -> Bool {
    let content = lines[index].content
    return fenceOpening(content) != nil || heading(content) != nil || isHorizontalRule(content)
      || quoteContent(content) != nil || listItem(content) != nil || parseTable(lines, at: index) != nil
  }

  private func parseInline(_ source: String, baseRole: SemanticTextRole = .body) -> StyledText {
    var spans: [StyledTextSpan] = []
    var index = source.startIndex

    func appendLiteral(_ text: String) {
      spans.append(StyledTextSpan(text, role: baseRole))
    }

    while index < source.endIndex {
      let strongMarker = source[index...].hasPrefix("**") ? "**" : (source[index...].hasPrefix("__") ? "__" : nil)
      if let strongMarker,
         let contentStart = source.index(index, offsetBy: 2, limitedBy: source.endIndex)
      {
        if let close = source.range(of: strongMarker, range: contentStart ..< source.endIndex) {
          let nested = parseInline(String(source[contentStart ..< close.lowerBound]), baseRole: baseRole)
          spans.append(contentsOf: nested.applying(attributes: .bold).spans)
          index = close.upperBound
        } else {
          appendLiteral(strongMarker)
          index = contentStart
        }
        continue
      }
      if source[index] == "*" || source[index] == "_" {
        let marker = String(source[index])
        let contentStart = source.index(after: index)
        if let close = source.range(of: marker, range: contentStart ..< source.endIndex), close.lowerBound > contentStart {
          let nested = parseInline(String(source[contentStart ..< close.lowerBound]), baseRole: baseRole)
          spans.append(contentsOf: nested.applying(attributes: .italic).spans)
          index = close.upperBound
          continue
        }
      }
      if source[index] == "`" {
        let contentStart = source.index(after: index)
        if let close = source[contentStart...].firstIndex(of: "`") {
          spans.append(StyledTextSpan(String(source[contentStart ..< close]), role: .inlineCode))
          index = source.index(after: close)
          continue
        }
      }
      if source[index] == "[",
         let labelEnd = source[index...].firstIndex(of: "]"),
         source.index(after: labelEnd) < source.endIndex,
         source[source.index(after: labelEnd)] == "("
      {
        let destinationStart = source.index(labelEnd, offsetBy: 2)
        if let destinationEnd = source[destinationStart...].firstIndex(of: ")"), destinationEnd > destinationStart {
          let labelStart = source.index(after: index)
          let label = parseInline(String(source[labelStart ..< labelEnd]), baseRole: .link)
          spans.append(
            contentsOf: label.applying(
              role: .link,
              attributes: .underline,
              link: String(source[destinationStart ..< destinationEnd])
            ).spans
          )
          index = source.index(after: destinationEnd)
          continue
        }
      }

      appendLiteral(String(source[index]))
      index = source.index(after: index)
    }
    return StyledText(spans: spans)
  }

  private func heading(_ line: String) -> (level: Int, content: String)? {
    let trimmed = line.drop(while: { $0 == " " })
    guard line.count - trimmed.count <= 3 else { return nil }
    let level = trimmed.prefix(while: { $0 == "#" }).count
    guard (1 ... 6).contains(level) else { return nil }
    let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: level)
    guard markerEnd < trimmed.endIndex, trimmed[markerEnd] == " " else { return nil }
    return (level, String(trimmed[trimmed.index(after: markerEnd)...]))
  }

  private func fenceOpening(_ line: String) -> (marker: Character, count: Int, info: String)? {
    let trimmed = line.drop(while: { $0 == " " })
    guard line.count - trimmed.count <= 3, let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
    let count = trimmed.prefix(while: { $0 == marker }).count
    guard count >= 3 else { return nil }
    let end = trimmed.index(trimmed.startIndex, offsetBy: count)
    return (marker, count, trimmed[end...].trimmingCharacters(in: .whitespaces))
  }

  private func isFenceClosing(_ line: String, marker: Character, count: Int) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.count >= count && trimmed.allSatisfy { $0 == marker }
  }

  private func isHorizontalRule(_ line: String) -> Bool {
    let compact = line.filter { $0 != " " && $0 != "\t" }
    guard compact.count >= 3, let marker = compact.first, marker == "-" || marker == "*" || marker == "_" else {
      return false
    }
    return compact.allSatisfy { $0 == marker }
  }

  private func quoteContent(_ line: String) -> String? {
    let trimmed = line.drop(while: { $0 == " " })
    guard line.count - trimmed.count <= 3, trimmed.first == ">" else { return nil }
    var content = trimmed.dropFirst()
    if content.first == " " {
      content = content.dropFirst()
    }
    return String(content)
  }

  private func listItem(_ line: String) -> (ordinal: Int?, content: String)? {
    let trimmed = line.drop(while: { $0 == " " })
    guard line.count - trimmed.count <= 3 else { return nil }
    if let marker = trimmed.first, marker == "-" || marker == "*" || marker == "+" {
      let after = trimmed.index(after: trimmed.startIndex)
      guard after < trimmed.endIndex, trimmed[after] == " " else { return nil }
      return (nil, String(trimmed[trimmed.index(after: after)...]))
    }
    let digits = trimmed.prefix(while: { $0.isNumber })
    guard digits.isEmpty == false, let ordinal = Int(digits) else { return nil }
    let dot = trimmed.index(trimmed.startIndex, offsetBy: digits.count)
    guard dot < trimmed.endIndex, trimmed[dot] == "." else { return nil }
    let space = trimmed.index(after: dot)
    guard space < trimmed.endIndex, trimmed[space] == " " else { return nil }
    return (ordinal, String(trimmed[trimmed.index(after: space)...]))
  }

  private func parseTable(_ lines: [MarkdownLine], at index: Int) -> (block: MarkdownBlock, nextIndex: Int)? {
    guard index + 1 < lines.count else { return nil }
    let headers = tableCells(lines[index].content)
    let separators = tableCells(lines[index + 1].content)
    guard headers.count >= 2, headers.count == separators.count else { return nil }
    let alignments = separators.compactMap(tableAlignment)
    guard alignments.count == separators.count else { return nil }

    var rows: [[StyledText]] = []
    var next = index + 2
    var end = lines[index + 1].range.upperBound
    while next < lines.count {
      let cells = tableCells(lines[next].content)
      guard cells.count == headers.count else { break }
      rows.append(cells.map { parseInline($0) })
      end = lines[next].range.upperBound
      next += 1
    }
    return (
      MarkdownBlock(
        range: TextRange(lines[index].range.lowerBound, end),
        kind: .table(
          MarkdownTable(
            headers: headers.map { parseInline($0, baseRole: .tableHeader) },
            alignments: alignments,
            rows: rows
          )
        )
      ),
      next
    )
  }

  private func tableCells(_ line: String) -> [String] {
    guard line.contains("|") else { return [] }
    var content = line.trimmingCharacters(in: .whitespaces)
    if content.first == "|" {
      content.removeFirst()
    }
    if content.last == "|" {
      content.removeLast()
    }
    return content.split(separator: "|", omittingEmptySubsequences: false).map {
      $0.trimmingCharacters(in: .whitespaces)
    }
  }

  private func tableAlignment(_ separator: String) -> MarkdownTableAlignment? {
    var value = separator
    let leading = value.first == ":"
    let trailing = value.last == ":"
    if leading {
      value.removeFirst()
    }
    if trailing, value.isEmpty == false {
      value.removeLast()
    }
    guard value.count >= 3, value.allSatisfy({ $0 == "-" }) else { return nil }
    if leading && trailing {
      return .center
    }
    return trailing ? .trailing : .leading
  }
}

/// An incremental Markdown parser for append and tail-replacement updates.
public struct StreamingMarkdownParser: Sendable {
  /// The current parsed document.
  public private(set) var document: MarkdownDocument
  private let parser: MarkdownParser

  /// Creates a streaming parser from initial source text.
  /// - Complexity: O(*n*), where *n* is the source length.
  public init(source: String = "", parser: MarkdownParser = MarkdownParser()) {
    self.parser = parser
    self.document = parser.parse(source)
  }

  /// Appends text and reparses the affected document tail.
  /// - Complexity: O(*n*), where *n* is the updated tail length.
  @discardableResult
  public mutating func append(_ fragment: String) throws -> MarkdownParseResult {
    let end = document.source.utf8.count
    let result = try parser.reparseTail(of: document, replacing: TextRange(end, end), with: fragment)
    document = result.document
    return result
  }

  /// Replaces the source tail at a UTF-8 byte offset.
  /// - Complexity: O(*n*), where *n* is the updated tail length.
  @discardableResult
  public mutating func replaceTail(fromUTF8Offset offset: Int, with replacement: String) throws -> MarkdownParseResult {
    let result = try parser.reparseTail(
      of: document,
      replacing: TextRange(offset, document.source.utf8.count),
      with: replacement
    )
    document = result.document
    return result
  }
}

private struct MarkdownLine {
  let content: String
  let range: TextRange

  static func lines(in source: String, offset: Int) -> [MarkdownLine] {
    guard source.isEmpty == false else { return [] }
    let parts = source.split(separator: "\n", omittingEmptySubsequences: false)
    var result: [MarkdownLine] = []
    var position = offset
    for (index, part) in parts.enumerated() {
      let content = String(part)
      let hasNewline = index < parts.count - 1
      let byteCount = part.utf8.count + (hasNewline ? 1 : 0)
      result.append(MarkdownLine(content: content, range: TextRange(position, position + byteCount)))
      position += byteCount
    }
    return result
  }
}
