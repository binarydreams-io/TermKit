import TUIFoundation

public enum DiffLayoutPolicy: Sendable, Hashable {
    case automatic
    case unified
    case sideBySide
}

public enum DiffLayoutMode: Sendable, Hashable {
    case unified
    case sideBySide
}

public struct DiffViewModel: Sendable, Hashable {
    public let diff: UnifiedDiff
    public let source: String?
    public let layoutPolicy: DiffLayoutPolicy
    public let wrapPolicy: TextWrapPolicy
    public let isSelectable: Bool

    public init(
        diff: UnifiedDiff,
        layoutPolicy: DiffLayoutPolicy = .automatic,
        wrapPolicy: TextWrapPolicy = .word,
        isSelectable: Bool = true
    ) {
        self.diff = diff
        source = nil
        self.layoutPolicy = layoutPolicy
        self.wrapPolicy = wrapPolicy
        self.isSelectable = isSelectable
    }

    public init(
        unifiedDiff source: String,
        layoutPolicy: DiffLayoutPolicy = .automatic,
        wrapPolicy: TextWrapPolicy = .word,
        isSelectable: Bool = true
    ) {
        diff = UnifiedDiffParser().parse(source)
        self.source = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        self.layoutPolicy = layoutPolicy
        self.wrapPolicy = wrapPolicy
        self.isSelectable = isSelectable
    }
}

public struct DiffPaneLine: Sendable, Hashable {
    public let lineNumber: Int?
    public let content: StyledText
    public let kind: DiffLineKind

    public init(lineNumber: Int?, content: StyledText, kind: DiffLineKind) {
        self.lineNumber = lineNumber
        self.content = content
        self.kind = kind
    }
}

public enum DiffLayoutRow: Sendable, Hashable {
    case fileHeader(oldPath: String?, newPath: String?)
    case hunkHeader(StyledText)
    case unified(oldLineNumber: Int?, newLineNumber: Int?, content: StyledText, kind: DiffLineKind)
    case sideBySide(left: DiffPaneLine?, right: DiffPaneLine?)
    case diagnostic(StyledText)
}

public struct DiffLayoutResult: Sendable, Hashable {
    public let mode: DiffLayoutMode
    public let size: CellSize
    public let rows: [DiffLayoutRow]
    public let isSelectable: Bool

    public init(mode: DiffLayoutMode, size: CellSize, rows: [DiffLayoutRow], isSelectable: Bool) {
        self.mode = mode
        self.size = size
        self.rows = rows
        self.isSelectable = isSelectable
    }
}

public struct DiffView: Sendable {
    public static let sideBySideThreshold = 120
    public let model: DiffViewModel

    public init(model: DiffViewModel) {
        self.model = model
    }

    public func layout(width: Int) -> DiffLayoutResult {
        precondition(width > 0)
        let mode: DiffLayoutMode
        switch model.layoutPolicy {
        case .automatic:
            mode = width > Self.sideBySideThreshold ? .sideBySide : .unified
        case .unified:
            mode = .unified
        case .sideBySide:
            mode = .sideBySide
        }

        var rows: [DiffLayoutRow] = []
        for file in model.diff.files {
            rows.append(.fileHeader(oldPath: file.oldPath, newPath: file.newPath))
            for hunk in file.hunks {
                let header =
                    "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
                    + (hunk.section.map { " \($0)" } ?? "")
                rows.append(.hunkHeader(StyledText(header, role: .diffHunk)))
                switch mode {
                case .unified:
                    rows.append(contentsOf: unifiedRows(for: hunk, width: width))
                case .sideBySide:
                    rows.append(contentsOf: sideBySideRows(for: hunk, width: width))
                }
            }
        }
        rows.append(
            contentsOf: model.diff.diagnostics.map {
                .diagnostic(StyledText("Line \($0.line): \($0.message)", role: .diagnostic))
            }
        )
        return DiffLayoutResult(
            mode: mode,
            size: CellSize(width: width, height: rows.count),
            rows: rows,
            isSelectable: model.isSelectable
        )
    }

    private func unifiedRows(for hunk: DiffHunk, width: Int) -> [DiffLayoutRow] {
        let contentWidth = Swift.max(1, width - 9)
        return hunk.lines.flatMap { line in
            styled(line).wrapped(to: contentWidth, policy: model.wrapPolicy).enumerated().map { index, segment in
                .unified(
                    oldLineNumber: index == 0 ? line.oldLineNumber : nil,
                    newLineNumber: index == 0 ? line.newLineNumber : nil,
                    content: segment.text,
                    kind: line.kind
                )
            }
        }
    }

    private func sideBySideRows(for hunk: DiffHunk, width: Int) -> [DiffLayoutRow] {
        let paneWidth = Swift.max(1, (width - 3) / 2 - 5)
        var rows: [DiffLayoutRow] = []
        var index = 0
        while index < hunk.lines.count {
            let line = hunk.lines[index]
            if line.kind == .removal {
                var removals: [DiffLine] = []
                var additions: [DiffLine] = []
                while index < hunk.lines.count && hunk.lines[index].kind == .removal {
                    removals.append(hunk.lines[index])
                    index += 1
                }
                while index < hunk.lines.count && hunk.lines[index].kind == .addition {
                    additions.append(hunk.lines[index])
                    index += 1
                }
                for pairIndex in 0..<Swift.max(removals.count, additions.count) {
                    rows.append(
                        contentsOf: pairedRows(
                            left: removals.indices.contains(pairIndex) ? removals[pairIndex] : nil,
                            right: additions.indices.contains(pairIndex) ? additions[pairIndex] : nil,
                            paneWidth: paneWidth
                        )
                    )
                }
                continue
            }
            if line.kind == .addition {
                rows.append(contentsOf: pairedRows(left: nil, right: line, paneWidth: paneWidth))
            } else if line.kind == .context {
                rows.append(contentsOf: pairedRows(left: line, right: line, paneWidth: paneWidth))
            } else {
                rows.append(contentsOf: pairedRows(left: line, right: nil, paneWidth: paneWidth))
            }
            index += 1
        }
        return rows
    }

    private func pairedRows(left: DiffLine?, right: DiffLine?, paneWidth: Int) -> [DiffLayoutRow] {
        let leftLines = left.map { styled($0).wrapped(to: paneWidth, policy: model.wrapPolicy) } ?? []
        let rightLines = right.map { styled($0).wrapped(to: paneWidth, policy: model.wrapPolicy) } ?? []
        return (0..<Swift.max(1, leftLines.count, rightLines.count)).map { index in
            let leftPane = left.map {
                DiffPaneLine(
                    lineNumber: index == 0 ? $0.oldLineNumber : nil,
                    content: leftLines.indices.contains(index) ? leftLines[index].text : StyledText(),
                    kind: $0.kind
                )
            }
            let rightPane = right.map {
                DiffPaneLine(
                    lineNumber: index == 0 ? $0.newLineNumber : nil,
                    content: rightLines.indices.contains(index) ? rightLines[index].text : StyledText(),
                    kind: $0.kind
                )
            }
            return .sideBySide(left: leftPane, right: rightPane)
        }
    }

    private func styled(_ line: DiffLine) -> StyledText {
        let role: SemanticTextRole
        switch line.kind {
        case .addition:
            role = .diffAdded
        case .removal:
            role = .diffRemoved
        case .context:
            role = .diffContext
        case .noNewlineMarker:
            role = .muted
        }
        return StyledText(line.content, role: role)
    }
}
