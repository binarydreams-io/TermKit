/// A terminal cell with semantic text metadata.
public struct SemanticCell: Sendable, Hashable {
    /// The grapheme stored in the cell.
    public let grapheme: String
    /// The terminal column width of the grapheme.
    public let displayWidth: Int
    /// The semantic role of the grapheme.
    public let role: SemanticTextRole
    /// The text attributes applied to the grapheme.
    public let attributes: StyledTextAttributes
    /// The link destination associated with the grapheme.
    public let link: String?
    /// A Boolean value that indicates whether the cell continues a wide grapheme.
    public let isContinuation: Bool
    /// The explicit semantic foreground color role.
    public let foregroundRole: SemanticColorRole?
    /// The explicit semantic background color role.
    public let backgroundRole: SemanticColorRole?

    /// Creates a semantic cell.
    public init(
        grapheme: String,
        displayWidth: Int,
        role: SemanticTextRole,
        attributes: StyledTextAttributes = [],
        link: String? = nil,
        isContinuation: Bool = false,
        foregroundRole: SemanticColorRole? = nil,
        backgroundRole: SemanticColorRole? = nil
    ) {
        precondition((0...2).contains(displayWidth))
        self.grapheme = grapheme
        self.displayWidth = displayWidth
        self.role = role
        self.attributes = attributes
        self.link = link
        self.isContinuation = isContinuation
        self.foregroundRole = foregroundRole
        self.backgroundRole = backgroundRole
    }
}

/// A rectangular grid of optional semantic cells.
public struct SemanticCellGrid: Sendable, Hashable {
    /// The number of columns in each row.
    public let width: Int
    /// The rows in the grid.
    public let rows: [[SemanticCell?]]

    /// Creates a grid whose rows all have the specified width.
    /// - Complexity: O(*r*), where *r* is the number of rows.
    public init(width: Int, rows: [[SemanticCell?]]) {
        precondition(width >= 0 && rows.allSatisfy { $0.count == width })
        self.width = width
        self.rows = rows
    }

    /// The number of rows in the grid.
    /// - Complexity: O(1).
    public var height: Int { rows.count }
}

/// A type that converts styled text into semantic terminal cells.
public protocol StyledTextCellRendering: Sendable {
    /// Renders styled text into a grid with the specified width and wrapping policy.
    /// - Complexity: O(*n*), where *n* is the number of graphemes in `text`.
    func render(_ text: StyledText, width: Int, wrapPolicy: TextWrapPolicy) -> SemanticCellGrid
}

/// The standard renderer for semantic terminal cells.
public struct StyledTextCellRenderer: StyledTextCellRendering, Sendable {
    /// Creates a styled-text cell renderer.
    public init() {}

    /// Renders styled text into a grid with the specified width and wrapping policy.
    /// - Complexity: O(*n*), where *n* is the number of graphemes in `text`.
    public func render(_ text: StyledText, width: Int, wrapPolicy: TextWrapPolicy = .word) -> SemanticCellGrid {
        precondition(width > 0)
        let lines = text.wrapped(to: width, policy: wrapPolicy)
        let rows = lines.map { line in
            var cells: [SemanticCell?] = []
            for span in line.text.spans {
                for grapheme in span.text {
                    let displayWidth = TerminalWidth.width(of: grapheme)
                    if displayWidth == 0 {
                        if let index = cells.lastIndex(where: { $0?.isContinuation == false }), let cell = cells[index] {
                            cells[index] = SemanticCell(
                                grapheme: cell.grapheme + String(grapheme),
                                displayWidth: cell.displayWidth,
                                role: cell.role,
                                attributes: cell.attributes,
                                link: cell.link,
                                foregroundRole: cell.foregroundRole,
                                backgroundRole: cell.backgroundRole
                            )
                        }
                        continue
                    }
                    let renderedGrapheme: String
                    let renderedWidth: Int
                    if displayWidth == 2, cells.count + displayWidth > width, cells.count < width {
                        renderedGrapheme = "�"
                        renderedWidth = 1
                    } else {
                        guard cells.count + displayWidth <= width else { continue }
                        renderedGrapheme = String(grapheme)
                        renderedWidth = displayWidth
                    }
                    cells.append(
                        SemanticCell(
                            grapheme: renderedGrapheme,
                            displayWidth: renderedWidth,
                            role: span.role,
                            attributes: span.attributes,
                            link: span.link
                        )
                    )
                    if renderedWidth == 2 {
                        cells.append(
                            SemanticCell(
                                grapheme: "",
                                displayWidth: 0,
                                role: span.role,
                                attributes: span.attributes,
                                link: span.link,
                                isContinuation: true
                            )
                        )
                    }
                }
            }
            if cells.count < width {
                cells.append(contentsOf: repeatElement(nil, count: width - cells.count))
            }
            return cells
        }
        return SemanticCellGrid(width: width, rows: rows)
    }
}
