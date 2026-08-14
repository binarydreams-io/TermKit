import Testing

@testable import TermKit

struct ModuleAmbiguityTests {
    @Test("Rich-text names are available through TermKit")
    func richTextNames() {
        let codeBlock = CodeBlockModel(code: "let value = 1")
        let diff = DiffView(model: DiffViewModel(unifiedDiff: "@@ -0,0 +0,0 @@"))

        #expect(codeBlock.code == "let value = 1")
        #expect(diff.layout(width: 80).mode == .unified)
    }
}
