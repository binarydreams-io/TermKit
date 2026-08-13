import TUIFoundation
import TUIDesign

public struct SemanticCell: Sendable, Hashable {
    public let grapheme: String
    public let displayWidth: Int
    public let role: SemanticTextRole
    public let attributes: StyledTextAttributes
    public let link: String?
    public let isContinuation: Bool
    public let foregroundRole: SemanticColorRole?
    public let backgroundRole: SemanticColorRole?

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

public struct SemanticCellGrid: Sendable, Hashable {
    public let width: Int
    public let rows: [[SemanticCell?]]

    public init(width: Int, rows: [[SemanticCell?]]) {
        precondition(width >= 0 && rows.allSatisfy { $0.count == width })
        self.width = width
        self.rows = rows
    }

    public var height: Int { rows.count }
}

public protocol StyledTextCellRendering: Sendable {
    func render(_ text: StyledText, width: Int, wrapPolicy: TextWrapPolicy) -> SemanticCellGrid
}

public struct StyledTextCellRenderer: StyledTextCellRendering, Sendable {
    public init() {}

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
