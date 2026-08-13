import Testing

@testable import TUIFoundation

struct TerminalWidthTests {
    @Test(
        "Terminal width handles extended grapheme clusters",
        arguments: [
            ("ASCII", 5),
            ("e\u{301}", 1),
            ("\u{301}", 0),
            ("界", 2),
            ("❤️", 2),
            ("👩‍💻", 2),
            ("🇺🇦", 2),
            ("1️⃣", 2),
        ]
    )
    func unicodeWidth(value: String, expected: Int) {
        #expect(TerminalWidth.width(of: value) == expected)
    }

    @Test("Terminal prefix uses a visible fallback for a wide grapheme in one remaining cell")
    func narrowPrefixFallback() {
        #expect(TerminalWidth.prefix(of: "A界B", fitting: 2) == "A�")
    }
}
