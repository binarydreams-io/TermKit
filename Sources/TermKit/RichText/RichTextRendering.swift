/// A view that renders styled text with a semantic theme.
public struct RichText: SemanticRenderable, View, Sendable, Hashable {
  /// The semantic identifier.
  public var id: SemanticID
  /// The styled text to render.
  public var text: StyledText
  /// The text wrapping policy.
  public var wrapPolicy: TextWrapPolicy
  /// The semantic color theme.
  public var theme: SemanticTheme
  /// The color scheme used to resolve the theme.
  public var scheme: ColorScheme

  /// Creates a rich-text view.
  public init(
    _ text: StyledText,
    id: SemanticID = "rich-text",
    wrapPolicy: TextWrapPolicy = .word,
    theme: SemanticTheme = .standard,
    scheme: ColorScheme = .dark
  ) {
    self.id = id
    self.text = text
    self.wrapPolicy = wrapPolicy
    self.theme = theme
    self.scheme = scheme
  }

  /// Returns the rendered text size constrained by a proposal.
  /// - Complexity: O(*n*), where *n* is the number of text graphemes.
  public nonisolated func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    let naturalWidth =
      text.plainText
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { TerminalWidth.width(of: String($0)) }
        .max() ?? 0
    guard naturalWidth > 0 else { return .zero }
    let width = max(1, min(naturalWidth, proposal.width ?? naturalWidth))
    let height = StyledTextCellRenderer().render(text, width: width, wrapPolicy: wrapPolicy).height
    return CellSize(width: width, height: min(height, proposal.height ?? height))
  }

  /// Paints the styled text and returns its semantic node.
  /// - Complexity: O(*w* × *h*), where the terms are the rendered grid dimensions.
  public nonisolated func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    guard context.clip.width > 0, context.clip.height > 0 else {
      return SemanticNode(id: id, role: .text, label: text.plainText)
    }
    let grid = StyledTextCellRenderer().render(text, width: context.clip.width, wrapPolicy: wrapPolicy)
    try SemanticCellPainter.paint(
      grid,
      into: &surface,
      context: context,
      theme: theme.resolve(scheme: scheme),
      resources: &resources
    )
    let renderBounds = CellRect(
      origin: context.origin,
      size: CellSize(width: grid.width, height: grid.height)
    )
    let visibleFrame = renderBounds.intersection(context.clip)?.intersection(surface.bounds)
    return SemanticNode(
      id: id,
      role: .text,
      label: text.plainText,
      frame: visibleFrame
    )
  }

  /// The primitive node descriptor for the rich-text view.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
  }
}

/// Operations for painting semantic cell grids.
public enum SemanticCellPainter {
  /// Paints a semantic cell grid with a resolved theme.
  /// - Complexity: O(*w* × *h*), where the terms are the grid dimensions.
  public static func paint(
    _ grid: SemanticCellGrid,
    into surface: inout Surface,
    context: PaintContext,
    theme: ResolvedSemanticTheme,
    resources: inout ControlRenderResources
  ) throws {
    for (y, row) in grid.rows.enumerated() {
      for (x, cell) in row.enumerated() {
        guard let cell, cell.isContinuation == false else { continue }
        let point = context.origin.offsetBy(dx: x, dy: y)
        let atom = CellRect(x: point.x, y: point.y, width: cell.displayWidth, height: 1)
        guard context.clip.contains(atom), surface.bounds.contains(atom) else { continue }
        let graphemeID = try resources.graphemes.intern(cell.grapheme)
        let styleID = try resources.internPaintStyle(style(for: cell, theme: theme))
        _ = try surface.write(
          graphemeID: graphemeID,
          at: point,
          styleID: styleID,
          displayWidth: UInt8(cell.displayWidth),
          clip: context.clip
        )
      }
    }
  }

  private static func style(for cell: SemanticCell, theme: ResolvedSemanticTheme) -> CellStyle {
    let selected = cell.attributes.contains(.selected)
    let foreground = selected ? theme[.selectedText] : theme[cell.foregroundRole ?? foregroundRole(for: cell.role)]
    let background =
      selected
        ? theme[.selectedBackground]
        : theme[cell.backgroundRole ?? backgroundRole(for: cell.role)]
    var attributes: TextAttributes = []
    if cell.attributes.contains(.bold) {
      attributes.insert(.bold)
    }
    if cell.attributes.contains(.italic) {
      attributes.insert(.italic)
    }
    if cell.attributes.contains(.underline) {
      attributes.insert(.underline)
    }
    if cell.attributes.contains(.strikethrough) {
      attributes.insert(.strikethrough)
    }
    if cell.attributes.contains(.dim) {
      attributes.insert(.dim)
    }
    return CellStyle(
      foreground: .rgba(foreground),
      background: .rgba(background),
      attributes: attributes
    )
  }

  private static func foregroundRole(for role: SemanticTextRole) -> SemanticColorRole {
    switch role {
    case .heading: .markdownHeading
    case .link: .markdownLink
    case .inlineCode, .code: .markdownCode
    case .keyword: .syntaxKeyword
    case .string: .syntaxString
    case .number: .syntaxNumber
    case .comment: .syntaxComment
    case .type: .syntaxType
    case .diffAdded: .diffAddition
    case .diffRemoved: .diffDeletion
    case .diffContext: .diffContext
    case .diffHunk: .accent
    case .muted, .lineNumber, .listMarker, .quoteMarker: .mutedText
    case .diagnostic: .error
    case .body, .tableHeader: .text
    }
  }

  private static func backgroundRole(for role: SemanticTextRole) -> SemanticColorRole {
    switch role {
    case .inlineCode, .code, .keyword, .string, .number, .comment, .type: .panel
    case .diffAdded: .diffAdditionBackground
    case .diffRemoved: .diffDeletionBackground
    default: .background
    }
  }
}

/// A diagnostic produced while rendering rich text.
public struct RichTextRenderDiagnostic: Sendable, Hashable {
  /// The diagnostic message.
  public let message: String

  /// Creates a render diagnostic.
  public init(_ message: String) {
    self.message = message
  }
}

/// A rendered cell with resolved style and packed-cell data.
public struct ThemedCell: Sendable, Hashable {
  /// The rendered grapheme.
  public let grapheme: String
  /// The semantic text role.
  public let role: SemanticTextRole
  /// The resolved cell style.
  public let style: CellStyle
  /// The associated link destination.
  public let link: String?
  /// A Boolean value that indicates a wide-grapheme continuation cell.
  public let isContinuation: Bool
  /// A Boolean value that indicates selected content.
  public let isSelected: Bool
  /// The packed terminal cell.
  public let packedCell: PackedCell

  /// Creates a themed cell.
  public init(
    grapheme: String,
    role: SemanticTextRole,
    style: CellStyle,
    link: String?,
    isContinuation: Bool,
    isSelected: Bool,
    packedCell: PackedCell
  ) {
    self.grapheme = grapheme
    self.role = role
    self.style = style
    self.link = link
    self.isContinuation = isContinuation
    self.isSelected = isSelected
    self.packedCell = packedCell
  }
}

/// A rectangular grid of themed cells.
public struct ThemedCellGrid: Sendable, Hashable {
  /// The number of columns in each row.
  public let width: Int
  /// The themed rows.
  public let rows: [[ThemedCell]]

  /// Creates a themed grid whose rows all have the specified width.
  /// - Complexity: O(*r*), where *r* is the number of rows.
  public init(width: Int, rows: [[ThemedCell]]) {
    precondition(width >= 0 && rows.allSatisfy { $0.count == width })
    self.width = width
    self.rows = rows
  }

  /// The number of rows.
  /// - Complexity: O(1).
  public var height: Int {
    rows.count
  }
}

/// The terminal data, semantics, and diagnostics produced by rich-text rendering.
public struct RichTextRenderResult: Sendable {
  /// The rendered terminal surface.
  public let surface: Surface
  /// The grapheme interner used by the surface.
  public let graphemes: GraphemeInterner
  /// The style interner used by the surface.
  public let styles: StyleInterner
  /// The resolved themed cells.
  public let cells: ThemedCellGrid
  /// The semantic root node.
  public let semantics: SemanticNode
  /// The render diagnostics.
  public let diagnostics: [RichTextRenderDiagnostic]

  /// Creates a rich-text render result.
  public init(
    surface: Surface,
    graphemes: GraphemeInterner,
    styles: StyleInterner,
    cells: ThemedCellGrid,
    semantics: SemanticNode,
    diagnostics: [RichTextRenderDiagnostic]
  ) {
    self.surface = surface
    self.graphemes = graphemes
    self.styles = styles
    self.cells = cells
    self.semantics = semantics
    self.diagnostics = diagnostics
  }
}

/// A renderer for styled text.
public struct RichTextRenderer: Sendable {
  /// The semantic color theme.
  public var theme: SemanticTheme
  /// The color scheme used to resolve the theme.
  public var scheme: ColorScheme

  /// Creates a rich-text renderer.
  public init(theme: SemanticTheme = .standard, scheme: ColorScheme = .dark) {
    self.theme = theme
    self.scheme = scheme
  }

  /// Renders styled text into terminal cells and semantics.
  /// - Complexity: O(*w* × *h*), where the terms are the rendered grid dimensions.
  public func render(
    _ text: StyledText,
    width: Int,
    wrapPolicy: TextWrapPolicy = .word,
    id: SemanticID = "styled-text"
  ) throws -> RichTextRenderResult {
    precondition(width > 0)
    let grid = StyledTextCellRenderer().render(text, width: width, wrapPolicy: wrapPolicy)
    let rows = grid.rows.map { row in
      row.map { cell in
        cell.map(CellSpec.init) ?? CellSpec.blank()
      }
    }
    return try RichTextPacker(theme: theme, scheme: scheme).pack(
      rows: rows,
      id: id,
      label: text.plainText,
      isSelectable: text.spans.contains { $0.attributes.contains(.selected) },
      diagnostics: []
    )
  }
}

/// A renderable presentation of a Markdown document.
public struct MarkdownPresentation: Sendable {
  /// The parsed Markdown document.
  public let document: MarkdownDocument

  /// Creates a presentation from a parsed document.
  public init(document: MarkdownDocument) {
    self.document = document
  }

  /// Parses source text and creates a Markdown presentation.
  /// - Complexity: O(*n*), where *n* is the source length.
  public init(_ source: String, parser: MarkdownParser = MarkdownParser()) {
    self.document = parser.parse(source)
  }

  /// Renders the Markdown document at the specified width.
  /// - Complexity: O(*n* + *w* × *h*), where *n* is source length and the other terms are output dimensions.
  public func render(
    width: Int,
    theme: SemanticTheme = .standard,
    scheme: ColorScheme = .dark,
    highlighter: any SyntaxHighlighter = SubtleSyntaxHighlighter()
  ) throws -> RichTextRenderResult {
    precondition(width > 0)
    let diagnostics = document.diagnostics.map { RichTextRenderDiagnostic($0.message) }
    var rows: [[CellSpec]] = []
    for (index, block) in document.blocks.enumerated() {
      if index > 0 {
        rows.append(Array(repeating: .blank(), count: width))
      }
      if document.diagnostics.contains(where: {
        $0.range.lowerBound < block.range.upperBound && block.range.lowerBound < $0.range.upperBound
      }) {
        let bytes = Array(document.source.utf8)
        let source = String(decoding: bytes[block.range.lowerBound ..< block.range.upperBound], as: UTF8.self)
        let grid = StyledTextCellRenderer().render(StyledText(source), width: width, wrapPolicy: .word)
        rows.append(contentsOf: grid.rows.map { $0.map { $0.map(CellSpec.init) ?? .blank() } })
      } else {
        rows.append(contentsOf: render(block, width: width, highlighter: highlighter))
      }
    }
    if rows.isEmpty {
      rows = [Array(repeating: .blank(), count: width)]
    }
    return try RichTextPacker(theme: theme, scheme: scheme).pack(
      rows: rows,
      id: "markdown",
      label: document.source,
      isSelectable: true,
      diagnostics: diagnostics
    )
  }

  private func render(
    _ block: MarkdownBlock,
    width: Int,
    highlighter: any SyntaxHighlighter
  ) -> [[CellSpec]] {
    switch block.kind {
    case let .heading(_, content):
      return textRows(content.applying(attributes: .bold), width: width)
    case let .paragraph(content):
      return textRows(content, width: width)
    case let .unorderedList(items):
      return items.flatMap { prefixedRows(marker: "• ", content: $0.content, width: width) }
    case let .orderedList(items):
      return items.flatMap { prefixedRows(marker: "\($0.ordinal ?? 1). ", content: $0.content, width: width) }
    case let .blockQuote(content):
      return prefixedRows(marker: "│ ", content: content, width: width, markerRole: .quoteMarker)
    case let .codeFence(fence):
      let highlighted = highlighter.highlight(fence.code, language: fence.language, changedRanges: [])
      return textRows(highlighted.text, width: width, wrapPolicy: .character, background: .panel)
    case .horizontalRule:
      return [Array(repeating: CellSpec(grapheme: "─", role: .muted), count: width)]
    case let .table(table):
      return tableRows(table, width: width)
    }
  }

  private func prefixedRows(
    marker: String,
    content: StyledText,
    width: Int,
    markerRole: SemanticTextRole = .listMarker
  ) -> [[CellSpec]] {
    let markerWidth = Swift.min(width, TerminalWidth.width(of: marker))
    let available = Swift.max(1, width - markerWidth)
    return content.wrapped(to: available, policy: .word).enumerated().map { index, line in
      let prefix = index == 0 ? StyledText(marker, role: markerRole) : StyledText(String(repeating: " ", count: markerWidth))
      return row(prefix.appending(line.text), width: width)
    }
  }

  private func tableRows(_ table: MarkdownTable, width: Int) -> [[CellSpec]] {
    let columns = table.headers.count
    guard columns > 0 else { return [] }
    let separators = columns - 1
    let columnWidth = Swift.max(1, (width - separators * 3) / columns)
    let allRows = [table.headers] + table.rows
    return allRows.map { values in
      var text = StyledText()
      for column in 0 ..< columns {
        if column > 0 {
          text = text.appending(StyledText(" │ ", role: .muted))
        }
        let value = values.indices.contains(column) ? values[column] : StyledText()
        let clipped = value.wrapped(to: columnWidth, policy: .character).first?.text ?? StyledText()
        let padding = Swift.max(0, columnWidth - clipped.cellWidth)
        text = text.appending(clipped).appending(StyledText(String(repeating: " ", count: padding)))
      }
      return row(text, width: width)
    }
  }

  private func textRows(
    _ text: StyledText,
    width: Int,
    wrapPolicy: TextWrapPolicy = .word,
    background: SemanticColorRole? = nil
  ) -> [[CellSpec]] {
    text.wrapped(to: width, policy: wrapPolicy).map { row($0.text, width: width, background: background) }
  }

  private func row(_ text: StyledText, width: Int, background: SemanticColorRole? = nil) -> [CellSpec] {
    let grid = StyledTextCellRenderer().render(text, width: width, wrapPolicy: .none)
    return (grid.rows.first ?? Array(repeating: nil, count: width)).map {
      var spec = $0.map(CellSpec.init) ?? .blank()
      spec.background = background
      return spec
    }
  }
}

/// A renderable code-block model.
public struct CodeBlock: Sendable {
  /// The code-block model.
  public let model: CodeBlockModel

  /// Creates a renderable code block.
  public init(model: CodeBlockModel) {
    self.model = model
  }

  /// Renders the code block at the specified width.
  /// - Complexity: O(*n* + *w* × *h*), where *n* is code length and the other terms are output dimensions.
  public func render(
    width: Int,
    theme: SemanticTheme = .standard,
    scheme: ColorScheme = .dark,
    highlighter: any SyntaxHighlighter = SubtleSyntaxHighlighter()
  ) throws -> RichTextRenderResult {
    precondition(width > 0)
    var diagnostics: [RichTextRenderDiagnostic] = []
    var renderedModel = model
    if let selection = model.selection {
      let bytes = Array(model.code.utf8)
      if isUTF8Boundary(selection.lowerBound, in: bytes) == false
        || isUTF8Boundary(selection.upperBound, in: bytes) == false
      {
        diagnostics.append(RichTextRenderDiagnostic("Selection does not align with UTF-8 boundaries"))
        renderedModel = CodeBlockModel(
          code: model.code,
          language: model.language,
          title: model.title,
          showsLineNumbers: model.showsLineNumbers,
          wrapPolicy: model.wrapPolicy,
          isCopyEnabled: model.isCopyEnabled,
          isSelectable: model.isSelectable
        )
      }
    }
    let layout = CodeBlockLayout().layout(renderedModel, width: width, highlighter: highlighter)
    var rows: [[CellSpec]] = []
    if let title = layout.title {
      rows.append(makeRow(title, width: width, background: .element))
    }
    let selectedText = applySelection(to: model.code, range: layout.selection)
    let selectedHighlight = highlighter.highlight(selectedText.plainText, language: model.language, changedRanges: []).text
    let selectedLines = mergeSelection(from: selectedText, into: selectedHighlight)
      .wrapped(to: Swift.max(1, selectedHighlight.cellWidth), policy: .none)
    var selectedRows: [StyledText] = []
    for line in selectedLines {
      selectedRows.append(contentsOf: line.text.wrapped(to: layout.contentWidth, policy: model.wrapPolicy).map(\.text))
    }

    for (index, layoutRow) in layout.rows.enumerated() {
      var cells: [CellSpec] = []
      if layout.gutterWidth > 0 {
        let number = layoutRow.lineNumber.map(String.init) ?? ""
        let gutter = String(repeating: " ", count: Swift.max(0, layout.gutterWidth - number.count - 1)) + number + "│"
        cells.append(contentsOf: specs(StyledText(gutter, role: .lineNumber), width: layout.gutterWidth, background: .element))
      }
      let content = selectedRows.indices.contains(index) ? selectedRows[index] : layoutRow.content
      cells.append(contentsOf: specs(content, width: layout.contentWidth, background: .panel))
      rows.append(Array(cells.prefix(width)) + Array(repeating: .blank(background: .panel), count: Swift.max(0, width - cells.count)))
    }
    return try RichTextPacker(theme: theme, scheme: scheme).pack(
      rows: rows,
      id: "code-block",
      label: model.code,
      isSelectable: model.isSelectable,
      isSelected: layout.selection?.isEmpty == false,
      diagnostics: diagnostics
    )
  }
}

extension DiffView {
  /// Renders the diff at the specified width.
  /// - Complexity: O(*n* + *w* × *h*), where *n* is diff length and the other terms are output dimensions.
  public func render(
    width: Int,
    theme: SemanticTheme = .standard,
    scheme: ColorScheme = .dark
  ) throws -> RichTextRenderResult {
    precondition(width > 0)
    let result = layout(width: width)
    let diagnostics = model.diff.diagnostics.map {
      RichTextRenderDiagnostic("Line \($0.line): \($0.message)")
    }
    var rows: [[CellSpec]] = []
    if model.diff.files.contains(where: \.isFallback), let source = model.source {
      let grid = StyledTextCellRenderer().render(StyledText(source), width: width, wrapPolicy: model.wrapPolicy)
      rows = grid.rows.map { $0.map { $0.map(CellSpec.init) ?? .blank() } }
      return try RichTextPacker(theme: theme, scheme: scheme).pack(
        rows: rows,
        id: "diff-view",
        label: source,
        isSelectable: model.isSelectable,
        diagnostics: diagnostics
      )
    }
    for layoutRow in result.rows {
      switch layoutRow {
      case let .fileHeader(oldPath, newPath):
        let label = [oldPath, newPath].compactMap(\.self).joined(separator: " → ")
        rows.append(makeRow(StyledText(label, role: .heading(3)).applying(attributes: .bold), width: width, background: .element))
      case let .hunkHeader(text):
        rows.append(makeRow(text, width: width, background: .panel))
      case let .unified(old, new, content, kind):
        let gutter = padded(old, width: 4) + padded(new, width: 4) + " "
        var cells = specs(StyledText(gutter, role: .lineNumber), width: Swift.min(9, width), background: background(for: kind))
        if width > 9 {
          cells += specs(content, width: width - 9, background: background(for: kind))
        }
        rows.append(Array(cells.prefix(width)))
      case let .sideBySide(left, right):
        let dividerWidth = Swift.min(3, width)
        let leftWidth = (width - dividerWidth) / 2
        let rightWidth = width - dividerWidth - leftWidth
        var cells = pane(left, width: leftWidth)
        cells += specs(StyledText(" │ ", role: .muted), width: dividerWidth, background: .panel)
        cells += pane(right, width: rightWidth)
        rows.append(cells)
      case let .diagnostic(text):
        rows.append(makeRow(text, width: width, background: .panel))
      }
    }
    if rows.isEmpty {
      rows = [Array(repeating: .blank(), count: width)]
    }
    return try RichTextPacker(theme: theme, scheme: scheme).pack(
      rows: rows,
      id: "diff-view",
      label: diffLabel,
      isSelectable: model.isSelectable,
      diagnostics: diagnostics
    )
  }

  private var diffLabel: String {
    model.diff.files.flatMap { file in file.hunks.flatMap { $0.lines.map(\.content) } }.joined(separator: "\n")
  }

  private func pane(_ line: DiffPaneLine?, width: Int) -> [CellSpec] {
    guard let line else { return Array(repeating: .blank(background: .panel), count: width) }
    let gutterWidth = Swift.min(5, width)
    var cells = specs(
      StyledText(padded(line.lineNumber, width: Swift.max(0, gutterWidth - 1)) + (gutterWidth > 0 ? " " : ""), role: .lineNumber),
      width: gutterWidth,
      background: background(for: line.kind)
    )
    if width > gutterWidth {
      cells += specs(line.content, width: width - gutterWidth, background: background(for: line.kind))
    }
    return cells
  }

  private func padded(_ value: Int?, width: Int) -> String {
    let text = value.map(String.init) ?? ""
    return String(repeating: " ", count: Swift.max(0, width - text.count)) + text
  }

  private func background(for kind: DiffLineKind) -> SemanticColorRole {
    switch kind {
    case .addition: .diffAdditionBackground
    case .removal: .diffDeletionBackground
    case .context, .noNewlineMarker: .panel
    }
  }
}

private struct CellSpec {
  var grapheme: String
  var displayWidth: Int
  var role: SemanticTextRole
  var attributes: StyledTextAttributes
  var link: String?
  var isContinuation: Bool
  var background: SemanticColorRole?

  init(_ cell: SemanticCell) {
    self.grapheme = cell.grapheme
    self.displayWidth = cell.displayWidth
    self.role = cell.role
    self.attributes = cell.attributes
    self.link = cell.link
    self.isContinuation = cell.isContinuation
    self.background = nil
  }

  init(
    grapheme: String,
    displayWidth: Int = 1,
    role: SemanticTextRole,
    attributes: StyledTextAttributes = [],
    link: String? = nil,
    isContinuation: Bool = false,
    background: SemanticColorRole? = nil
  ) {
    self.grapheme = grapheme
    self.displayWidth = displayWidth
    self.role = role
    self.attributes = attributes
    self.link = link
    self.isContinuation = isContinuation
    self.background = background
  }

  static func blank(background: SemanticColorRole? = nil) -> CellSpec {
    CellSpec(grapheme: " ", role: .body, background: background)
  }
}

private struct RichTextPacker {
  let theme: SemanticTheme
  let scheme: ColorScheme

  func pack(
    rows: [[CellSpec]],
    id: SemanticID,
    label: String,
    isSelectable: Bool,
    isSelected: Bool = false,
    diagnostics: [RichTextRenderDiagnostic]
  ) throws -> RichTextRenderResult {
    let width = rows.first?.count ?? 0
    precondition(rows.allSatisfy { $0.count == width })
    let resolved = try theme.resolve(scheme: scheme)
    var graphemes = GraphemeInterner()
    var styles = StyleInterner()
    var surface = Surface(size: CellSize(width: width, height: rows.count))
    var themedRows: [[ThemedCell]] = []

    for (y, row) in rows.enumerated() {
      var themed: [ThemedCell] = []
      for (x, spec) in row.enumerated() {
        let selected = spec.attributes.contains(.selected)
        let style = cellStyle(for: spec, selected: selected, theme: resolved)
        let styleID = try styles.intern(style)
        if spec.isContinuation {
          let packed = surface[CellPoint(x: x, y: y)]
          themed.append(
            ThemedCell(
              grapheme: spec.grapheme,
              role: spec.role,
              style: style,
              link: spec.link,
              isContinuation: true,
              isSelected: selected,
              packedCell: packed
            )
          )
        } else {
          let graphemeID = try graphemes.intern(spec.grapheme)
          _ = try surface.write(
            graphemeID: graphemeID,
            at: CellPoint(x: x, y: y),
            styleID: styleID,
            displayWidth: UInt8(spec.displayWidth)
          )
          let packed = surface[CellPoint(x: x, y: y)]
          themed.append(
            ThemedCell(
              grapheme: spec.grapheme,
              role: spec.role,
              style: style,
              link: spec.link,
              isContinuation: false,
              isSelected: selected,
              packedCell: packed
            )
          )
        }
      }
      themedRows.append(themed)
    }
    try surface.validateWideCells()
    var state: SemanticState = []
    if isSelected {
      state.insert(.selected)
    }
    let diagnosticNodes = diagnostics.enumerated().map { index, diagnostic in
      SemanticNode(id: SemanticID(rawValue: "\(id.rawValue)-diagnostic-\(index)"), role: .status, label: diagnostic.message)
    }
    let semantics = SemanticNode(
      id: id,
      role: isSelectable ? .textEditor : .text,
      label: label,
      state: state,
      frame: CellRect(x: 0, y: 0, width: width, height: rows.count),
      children: diagnosticNodes
    )
    return RichTextRenderResult(
      surface: surface,
      graphemes: graphemes,
      styles: styles,
      cells: ThemedCellGrid(width: width, rows: themedRows),
      semantics: semantics,
      diagnostics: diagnostics
    )
  }

  private func cellStyle(for spec: CellSpec, selected: Bool, theme: ResolvedSemanticTheme) -> CellStyle {
    let foreground = selected ? theme[.selectedText] : theme[foregroundRole(for: spec.role)]
    let background = selected ? theme[.selectedBackground] : theme[spec.background ?? backgroundRole(for: spec.role)]
    return CellStyle(
      foreground: .rgba(foreground),
      background: .rgba(background),
      attributes: textAttributes(spec.attributes)
    )
  }

  private func foregroundRole(for role: SemanticTextRole) -> SemanticColorRole {
    switch role {
    case .heading: .markdownHeading
    case .link: .markdownLink
    case .inlineCode, .code: .markdownCode
    case .keyword: .syntaxKeyword
    case .string: .syntaxString
    case .number: .syntaxNumber
    case .comment: .syntaxComment
    case .type: .syntaxType
    case .diffAdded: .diffAddition
    case .diffRemoved: .diffDeletion
    case .diffContext: .diffContext
    case .diffHunk: .accent
    case .muted, .lineNumber, .listMarker, .quoteMarker: .mutedText
    case .diagnostic: .error
    case .body, .tableHeader: .text
    }
  }

  private func backgroundRole(for role: SemanticTextRole) -> SemanticColorRole {
    switch role {
    case .inlineCode, .code, .keyword, .string, .number, .comment, .type: .panel
    case .diffAdded: .diffAdditionBackground
    case .diffRemoved: .diffDeletionBackground
    default: .background
    }
  }

  private func textAttributes(_ attributes: StyledTextAttributes) -> TextAttributes {
    var result: TextAttributes = []
    if attributes.contains(.bold) {
      result.insert(.bold)
    }
    if attributes.contains(.italic) {
      result.insert(.italic)
    }
    if attributes.contains(.underline) {
      result.insert(.underline)
    }
    if attributes.contains(.strikethrough) {
      result.insert(.strikethrough)
    }
    if attributes.contains(.dim) {
      result.insert(.dim)
    }
    return result
  }
}

private func makeRow(
  _ text: StyledText,
  width: Int,
  background: SemanticColorRole? = nil
) -> [CellSpec] {
  specs(text, width: width, background: background)
}

private func specs(
  _ text: StyledText,
  width: Int,
  background: SemanticColorRole? = nil
) -> [CellSpec] {
  guard width > 0 else { return [] }
  let grid = StyledTextCellRenderer().render(text, width: width, wrapPolicy: .none)
  return (grid.rows.first ?? Array(repeating: nil, count: width)).map {
    var spec = $0.map(CellSpec.init) ?? .blank()
    spec.background = background
    return spec
  }
}

private func applySelection(to text: String, range: TextRange?) -> StyledText {
  guard let range, range.isEmpty == false else { return StyledText(text, role: .code) }
  let bytes = Array(text.utf8)
  guard range.upperBound <= bytes.count,
        isUTF8Boundary(range.lowerBound, in: bytes),
        isUTF8Boundary(range.upperBound, in: bytes)
  else { return StyledText(text, role: .code) }
  return StyledText(spans: [
    StyledTextSpan(String(decoding: bytes[..<range.lowerBound], as: UTF8.self), role: .code),
    StyledTextSpan(
      String(decoding: bytes[range.lowerBound ..< range.upperBound], as: UTF8.self),
      role: .code,
      attributes: .selected
    ),
    StyledTextSpan(String(decoding: bytes[range.upperBound...], as: UTF8.self), role: .code)
  ])
}

private func mergeSelection(from selected: StyledText, into highlighted: StyledText) -> StyledText {
  let selectedBytes = selected.spans.flatMap { span in
    Array(repeating: span.attributes.contains(.selected), count: span.text.utf8.count)
  }
  var offset = 0
  var spans: [StyledTextSpan] = []
  for span in highlighted.spans {
    var current = ""
    var currentSelected: Bool?
    for character in span.text {
      let byteCount = String(character).utf8.count
      let isSelected = selectedBytes.indices.contains(offset) && selectedBytes[offset]
      if currentSelected != nil, currentSelected != isSelected {
        spans.append(
          StyledTextSpan(
            current,
            role: span.role,
            attributes: currentSelected == true ? span.attributes.union(.selected) : span.attributes,
            link: span.link
          )
        )
        current = ""
      }
      currentSelected = isSelected
      current.append(character)
      offset += byteCount
    }
    if current.isEmpty == false {
      spans.append(
        StyledTextSpan(
          current,
          role: span.role,
          attributes: currentSelected == true ? span.attributes.union(.selected) : span.attributes,
          link: span.link
        )
      )
    }
  }
  return StyledText(spans: spans)
}
