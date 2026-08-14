@testable import TermKit
import Testing

struct SemanticThemeTests {
  @Test
  func `Resolver reports a typed reference cycle`() {
    let variant = ThemeVariant([
      .accent: .reference(.primary),
      .primary: .reference(.accent)
    ])
    let theme = SemanticTheme(light: variant, dark: variant)

    #expect(
      throws: SemanticThemeError.referenceCycle(
        scheme: .light,
        path: [.accent, .primary, .accent]
      )
    ) {
      try theme.resolve(.accent, scheme: .light)
    }
  }

  @Test
  func `Missing roles use standard fallback values`() throws {
    let customAccent = RGBA(redByte: 12, greenByte: 34, blueByte: 56)
    let theme = SemanticTheme(
      light: ThemeVariant([.accent: .rgba(customAccent)]),
      dark: ThemeVariant()
    )

    #expect(try theme.resolve(.accent, scheme: .light) == customAccent)
    #expect(try theme.resolve(.text, scheme: .light) == SemanticTheme.standard.resolve(.text, scheme: .light))
  }

  @Test
  func `Selected text is derived with readable contrast`() throws {
    let theme = SemanticTheme(
      light: ThemeVariant([.selectedBackground: .rgba(RGBA(redByte: 245, greenByte: 245, blueByte: 245))]),
      dark: ThemeVariant()
    )
    let background = try theme.resolve(.selectedBackground, scheme: .light)
    let foreground = try theme.resolve(.selectedText, scheme: .light)

    #expect(foreground == .black)
    #expect(SemanticTheme.contrastRatio(foreground, background) >= 4.5)
  }

  @Test
  func `Selected text contrast composites alpha over the theme background`() throws {
    let theme = SemanticTheme(
      light: ThemeVariant([
        .background: .rgba(.black),
        .selectedBackground: .rgba(RGBA(red: 1, green: 1, blue: 1, alpha: 0.25))
      ]),
      dark: ThemeVariant()
    )
    let selected = try theme.resolve(.selectedBackground, scheme: .light)
    let background = try theme.resolve(.background, scheme: .light)
    let effectiveBackground = selected.composited(over: background)
    let foreground = try theme.resolve(.selectedText, scheme: .light)

    #expect(foreground == .white)
    #expect(SemanticTheme.contrastRatio(foreground, effectiveBackground) >= 4.5)
  }

  @Test
  func `ANSI fallback returns a palette color`() throws {
    let resolved = try SemanticTheme.standard.resolve(.accent, scheme: .dark, capability: .ansi16)

    guard case let .ansi16(index, color) = resolved else {
      Issue.record("Expected ANSI-16 resolution")
      return
    }
    #expect(index < 16)
    #expect(color.alpha == 1)
  }
}
