import Foundation

public enum DiffLineKind: Sendable, Hashable {
    case context
    case addition
    case removal
    case noNewlineMarker
}

public struct DiffLine: Sendable, Hashable {
    public let kind: DiffLineKind
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(kind: DiffLineKind, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.kind = kind
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

public struct DiffHunk: Sendable, Hashable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let section: String?
    public let lines: [DiffLine]

    public init(
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        section: String? = nil,
        lines: [DiffLine]
    ) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }
}

public struct DiffFile: Sendable, Hashable {
    public let oldPath: String?
    public let newPath: String?
    public let hunks: [DiffHunk]
    public let isFallback: Bool

    public init(oldPath: String?, newPath: String?, hunks: [DiffHunk], isFallback: Bool = false) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
        self.isFallback = isFallback
    }
}

public struct DiffDiagnostic: Sendable, Hashable {
    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public struct UnifiedDiff: Sendable, Hashable {
    public let files: [DiffFile]
    public let diagnostics: [DiffDiagnostic]

    public init(files: [DiffFile], diagnostics: [DiffDiagnostic] = []) {
        self.files = files
        self.diagnostics = diagnostics
    }
}

public struct UnifiedDiffParser: Sendable {
    public init() {}

    public func parse(_ source: String, isComplete: Bool = true) -> UnifiedDiff {
        let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let sourceLines = normalizedSource.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lines = sourceLines.last?.isEmpty == true ? Array(sourceLines.dropLast()) : sourceLines
        guard lines.isEmpty == false else { return UnifiedDiff(files: []) }

        var files: [DiffFile] = []
        var diagnostics: [DiffDiagnostic] = []
        var currentFile: FileBuilder?
        var currentHunk: HunkBuilder?

        func finishHunk(allowIncomplete: Bool = false) {
            guard let hunk = currentHunk else { return }
            currentFile = currentFile ?? FileBuilder()
            currentFile?.hunks.append(hunk.build())
            if hunk.isFallback == false {
                let oldCount = hunk.lines.count { $0.kind == .context || $0.kind == .removal }
                let newCount = hunk.lines.count { $0.kind == .context || $0.kind == .addition }
                if oldCount != hunk.header.oldCount, allowIncomplete == false || oldCount > hunk.header.oldCount {
                    diagnostics.append(
                        DiffDiagnostic(
                            line: hunk.headerLine,
                            message: "Hunk old line count is \(oldCount); expected \(hunk.header.oldCount)"
                        )
                    )
                }
                if newCount != hunk.header.newCount, allowIncomplete == false || newCount > hunk.header.newCount {
                    diagnostics.append(
                        DiffDiagnostic(
                            line: hunk.headerLine,
                            message: "Hunk new line count is \(newCount); expected \(hunk.header.newCount)"
                        )
                    )
                }
            }
            currentHunk = nil
        }

        func finishFile() {
            finishHunk()
            guard let file = currentFile else { return }
            if file.oldPath != nil || file.newPath != nil || file.hunks.isEmpty == false {
                files.append(file.build())
            }
            currentFile = nil
        }

        for (lineIndex, line) in lines.enumerated() {
            let number = lineIndex + 1
            if line.hasPrefix("diff --git ") {
                finishFile()
                let paths = line.dropFirst("diff --git ".count).split(separator: " ", maxSplits: 1).map(String.init)
                currentFile = FileBuilder(
                    oldPath: paths.first.map(normalizeGitPath),
                    newPath: paths.count > 1 ? normalizeGitPath(paths[1]) : nil
                )
                continue
            }
            if line.hasPrefix("--- "), currentHunk == nil || currentHunk?.hasExpectedLineCounts == true {
                finishHunk()
                if currentFile?.hunks.isEmpty == false { finishFile() }
                currentFile = currentFile ?? FileBuilder()
                currentFile?.oldPath = parseHeaderPath(String(line.dropFirst(4)))
                continue
            }
            if currentHunk == nil, line.hasPrefix("+++ ") {
                finishHunk()
                currentFile = currentFile ?? FileBuilder()
                currentFile?.newPath = parseHeaderPath(String(line.dropFirst(4)))
                continue
            }
            if line.hasPrefix("@@") {
                finishHunk()
                currentFile = currentFile ?? FileBuilder()
                if let header = parseHunkHeader(line) {
                    currentHunk = HunkBuilder(header: header, headerLine: number)
                } else {
                    diagnostics.append(DiffDiagnostic(line: number, message: "Malformed hunk header"))
                    currentFile?.isFallback = true
                    currentHunk = HunkBuilder.fallback(startingAt: number, line: line)
                }
                continue
            }
            guard var hunk = currentHunk else { continue }
            if hunk.isFallback {
                hunk.lines.append(
                    DiffLine(
                        kind: .context,
                        content: line,
                        oldLineNumber: hunk.nextOld,
                        newLineNumber: hunk.nextNew
                    )
                )
                hunk.nextOld += 1
                hunk.nextNew += 1
            } else if line.hasPrefix("+") {
                hunk.lines.append(
                    DiffLine(kind: .addition, content: String(line.dropFirst()), oldLineNumber: nil, newLineNumber: hunk.nextNew)
                )
                hunk.nextNew += 1
            } else if line.hasPrefix("-") {
                hunk.lines.append(
                    DiffLine(kind: .removal, content: String(line.dropFirst()), oldLineNumber: hunk.nextOld, newLineNumber: nil)
                )
                hunk.nextOld += 1
            } else if line.hasPrefix(" ") {
                hunk.lines.append(
                    DiffLine(
                        kind: .context,
                        content: String(line.dropFirst()),
                        oldLineNumber: hunk.nextOld,
                        newLineNumber: hunk.nextNew
                    )
                )
                hunk.nextOld += 1
                hunk.nextNew += 1
            } else if line.hasPrefix("\\ No newline at end of file") {
                hunk.lines.append(DiffLine(kind: .noNewlineMarker, content: line, oldLineNumber: nil, newLineNumber: nil))
            } else {
                diagnostics.append(DiffDiagnostic(line: number, message: "Malformed hunk line; treated as context"))
                hunk.lines.append(
                    DiffLine(kind: .context, content: line, oldLineNumber: hunk.nextOld, newLineNumber: hunk.nextNew)
                )
                hunk.nextOld += 1
                hunk.nextNew += 1
            }
            currentHunk = hunk
        }
        if isComplete == false, currentHunk != nil {
            finishHunk(allowIncomplete: true)
        }
        if isComplete == false {
            if let file = currentFile,
                file.oldPath != nil || file.newPath != nil || file.hunks.isEmpty == false
            {
                files.append(file.build())
            }
            currentFile = nil
        } else {
            finishFile()
        }

        if files.isEmpty {
            let fallbackLines = lines.enumerated().map { index, line in
                DiffLine(kind: .context, content: line, oldLineNumber: index + 1, newLineNumber: index + 1)
            }
            diagnostics.append(DiffDiagnostic(line: 1, message: "Input is not a recognized unified diff"))
            files = [
                DiffFile(
                    oldPath: nil,
                    newPath: nil,
                    hunks: [DiffHunk(oldStart: 1, oldCount: lines.count, newStart: 1, newCount: lines.count, lines: fallbackLines)],
                    isFallback: true
                )
            ]
        }
        return UnifiedDiff(files: files, diagnostics: diagnostics)
    }

    private func parseHunkHeader(_ line: String) -> HunkHeader? {
        guard line.hasPrefix("@@ -"),
            let middle = line.range(of: " +"),
            let closing = line.range(of: " @@", range: middle.upperBound..<line.endIndex)
        else {
            return nil
        }
        let oldToken = String(line[line.index(line.startIndex, offsetBy: 4)..<middle.lowerBound])
        let newToken = String(line[middle.upperBound..<closing.lowerBound])
        guard let old = parseHunkRange(oldToken), let new = parseHunkRange(newToken) else { return nil }
        let sectionStart = closing.upperBound
        let section = sectionStart < line.endIndex ? String(line[sectionStart...]).trimmingCharacters(in: .whitespaces) : ""
        return HunkHeader(
            oldStart: old.start,
            oldCount: old.count,
            newStart: new.start,
            newCount: new.count,
            section: section.isEmpty ? nil : section
        )
    }

    private func parseHunkRange(_ token: String) -> (start: Int, count: Int)? {
        let parts = token.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]), start >= 0 else { return nil }
        if parts.count == 1 { return (start, 1) }
        guard parts.count == 2, let count = Int(parts[1]), count >= 0 else { return nil }
        return (start, count)
    }

    private func parseHeaderPath(_ value: String) -> String? {
        let path = value.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? value
        return path == "/dev/null" ? nil : normalizeGitPath(path)
    }

    private func normalizeGitPath(_ path: String) -> String {
        if path.hasPrefix("a/") || path.hasPrefix("b/") { return String(path.dropFirst(2)) }
        return path
    }
}

private struct HunkHeader {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let section: String?
}

private struct HunkBuilder {
    let header: HunkHeader
    let headerLine: Int
    let isFallback: Bool
    var nextOld: Int
    var nextNew: Int
    var lines: [DiffLine] = []

    var hasExpectedLineCounts: Bool {
        guard isFallback == false else { return false }
        let oldCount = lines.count { $0.kind == .context || $0.kind == .removal }
        let newCount = lines.count { $0.kind == .context || $0.kind == .addition }
        return oldCount == header.oldCount && newCount == header.newCount
    }

    init(header: HunkHeader, headerLine: Int) {
        self.header = header
        self.headerLine = headerLine
        isFallback = false
        nextOld = header.oldStart
        nextNew = header.newStart
    }

    private init(header: HunkHeader, headerLine: Int, isFallback: Bool, lines: [DiffLine]) {
        self.header = header
        self.headerLine = headerLine
        self.isFallback = isFallback
        nextOld = header.oldStart + lines.count
        nextNew = header.newStart + lines.count
        self.lines = lines
    }

    static func fallback(startingAt lineNumber: Int, line: String) -> HunkBuilder {
        let header = HunkHeader(
            oldStart: lineNumber,
            oldCount: 1,
            newStart: lineNumber,
            newCount: 1,
            section: nil
        )
        return HunkBuilder(
            header: header,
            headerLine: lineNumber,
            isFallback: true,
            lines: [
                DiffLine(
                    kind: .context,
                    content: line,
                    oldLineNumber: lineNumber,
                    newLineNumber: lineNumber
                )
            ]
        )
    }

    func build() -> DiffHunk {
        DiffHunk(
            oldStart: header.oldStart,
            oldCount: isFallback ? lines.count : header.oldCount,
            newStart: header.newStart,
            newCount: isFallback ? lines.count : header.newCount,
            section: header.section,
            lines: lines
        )
    }
}

private struct FileBuilder {
    var oldPath: String?
    var newPath: String?
    var hunks: [DiffHunk] = []
    var isFallback = false

    func build() -> DiffFile {
        DiffFile(oldPath: oldPath, newPath: newPath, hunks: hunks, isFallback: isFallback)
    }
}
