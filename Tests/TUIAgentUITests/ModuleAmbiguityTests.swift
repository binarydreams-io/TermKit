import TUIAgentUI
import TUIRichText
import Testing

struct ModuleAmbiguityTests {
    @Test("Rich-text names remain unambiguous when TUIAgentUI is also imported")
    func richTextNames() {
        let codeBlock = CodeBlockModel(code: "let value = 1")
        let diff = DiffView(model: DiffViewModel(unifiedDiff: "@@ -0,0 +0,0 @@"))

        #expect(codeBlock.code == "let value = 1")
        #expect(diff.layout(width: 80).mode == .unified)
    }
}
