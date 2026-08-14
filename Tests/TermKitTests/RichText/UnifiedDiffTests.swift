@testable import TermKit
import Testing

@Suite("Unified diff")
struct UnifiedDiffTests {
  @Test
  func `Parser creates files, hunks, line kinds, and old-new numbers`() throws {
    let source = """
    diff --git a/a.swift b/a.swift
    --- a/a.swift
    +++ b/a.swift
    @@ -10,3 +10,4 @@ func f()
     context
    -old
    +new
    +extra
     tail
    \\ No newline at end of file
    """

    let diff = UnifiedDiffParser().parse(source)
    let file = try #require(diff.files.first)
    let hunk = try #require(file.hunks.first)

    #expect(diff.diagnostics.isEmpty)
    #expect(file.oldPath == "a.swift")
    #expect(file.newPath == "a.swift")
    #expect(hunk.oldStart == 10)
    #expect(hunk.oldCount == 3)
    #expect(hunk.newStart == 10)
    #expect(hunk.newCount == 4)
    #expect(hunk.section == "func f()")
    #expect(hunk.lines.map(\.kind) == [.context, .removal, .addition, .addition, .context, .noNewlineMarker])
    #expect(hunk.lines.map(\.oldLineNumber) == [10, 11, nil, nil, 12, nil])
    #expect(hunk.lines.map(\.newLineNumber) == [10, nil, 11, 12, 13, nil])
  }

  @Test
  func `New and deleted file paths support dev-null headers`() throws {
    let source = """
    --- /dev/null
    +++ b/new.txt
    @@ -0,0 +1 @@
    +new
    """
    let file = try #require(UnifiedDiffParser().parse(source).files.first)

    #expect(file.oldPath == nil)
    #expect(file.newPath == "new.txt")
  }

  @Test
  func `Malformed input produces readable fallback content and diagnostics`() throws {
    let source = "@@ broken @@\n+orphan"
    let diff = UnifiedDiffParser().parse(source)
    let file = try #require(diff.files.first)
    let hunk = try #require(file.hunks.first)

    #expect(file.isFallback)
    #expect(diff.diagnostics.isEmpty == false)
    #expect(hunk.lines.map(\.content) == ["@@ broken @@", "+orphan"])
  }

  @Test
  func `Malformed hunk after file headers preserves paths and source lines`() throws {
    let source = "--- a/file.txt\n+++ b/file.txt\n@@ broken @@\n+orphan"
    let diff = UnifiedDiffParser().parse(source)
    let file = try #require(diff.files.first)
    let hunk = try #require(file.hunks.first)

    #expect(file.oldPath == "file.txt")
    #expect(file.newPath == "file.txt")
    #expect(file.isFallback)
    #expect(diff.diagnostics == [DiffDiagnostic(line: 3, message: "Malformed hunk header")])
    #expect(hunk.lines.map(\.content) == ["@@ broken @@", "+orphan"])
  }

  @Test
  func `CRLF and CR inputs normalize without leaking carriage returns`() throws {
    let source = "--- a/file.txt\r\n+++ b/file.txt\r@@ -1 +1 @@\r-old\r\n+new\r\n"
    let diff = UnifiedDiffParser().parse(source)
    let hunk = try #require(diff.files.first?.hunks.first)

    #expect(diff.diagnostics.isEmpty)
    #expect(hunk.lines.map(\.content) == ["old", "new"])
  }

  @Test
  func `File-header prefixes inside a hunk remain removal and addition lines`() throws {
    let source = "--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n--- old heading\n+++ new heading"
    let diff = UnifiedDiffParser().parse(source)
    let hunk = try #require(diff.files.first?.hunks.first)

    #expect(diff.files.count == 1)
    #expect(diff.diagnostics.isEmpty)
    #expect(hunk.lines.map(\.kind) == [.removal, .addition])
    #expect(hunk.lines.map(\.content) == ["-- old heading", "++ new heading"])
  }

  @Test
  func `Completed hunk counts allow the next file headers without a Git preamble`() {
    let source = """
    --- a/first.txt
    +++ b/first.txt
    @@ -1 +1 @@
    -old
    +new
    --- a/second.txt
    +++ b/second.txt
    @@ -1 +1 @@
     same
    """
    let diff = UnifiedDiffParser().parse(source)

    #expect(diff.diagnostics.isEmpty)
    #expect(diff.files.map(\.oldPath) == ["first.txt", "second.txt"])
    #expect(diff.files.map(\.newPath) == ["first.txt", "second.txt"])
  }

  @Test
  func `Completed hunks diagnose old and new count mismatches`() {
    let source = "--- a/file.txt\n+++ b/file.txt\n@@ -1,2 +1,3 @@\n-old\n+new"

    #expect(
      UnifiedDiffParser().parse(source).diagnostics == [
        DiffDiagnostic(line: 3, message: "Hunk old line count is 1; expected 2"),
        DiffDiagnostic(line: 3, message: "Hunk new line count is 1; expected 3")
      ]
    )
  }

  @Test
  func `Incomplete streaming hunks defer missing-count diagnostics`() {
    let source = "--- a/file.txt\n+++ b/file.txt\n@@ -1,2 +1,2 @@\n same"

    #expect(UnifiedDiffParser().parse(source, isComplete: false).diagnostics.isEmpty)
    #expect(
      UnifiedDiffParser().parse(source, isComplete: true).diagnostics == [
        DiffDiagnostic(line: 3, message: "Hunk old line count is 1; expected 2"),
        DiffDiagnostic(line: 3, message: "Hunk new line count is 1; expected 2")
      ]
    )
  }
}
