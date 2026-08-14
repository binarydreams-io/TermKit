import Foundation

/// A light or dark terminal color scheme.
public enum ColorScheme: Sendable, Hashable {
  /// A light color scheme.
  case light
  /// A dark color scheme.
  case dark
}

/// A semantic color role in a design theme.
public enum SemanticColorRole: String, CaseIterable, Sendable, Hashable {
  /// The primary content color.
  case primary
  /// The secondary content color.
  case secondary
  /// The accent color.
  case accent
  /// The error color.
  case error
  /// The warning color.
  case warning
  /// The success color.
  case success
  /// The informational color.
  case info
  /// The standard text color.
  case text
  /// The muted text color.
  case mutedText
  /// The base background color.
  case background
  /// The panel background color.
  case panel
  /// The interactive element color.
  case element
  /// The menu background color.
  case menu
  /// The regular border color.
  case borderRegular
  /// The active border color.
  case borderActive
  /// The subtle border color.
  case borderSubtle
  /// The added diff text color.
  case diffAddition
  /// The deleted diff text color.
  case diffDeletion
  /// The unchanged diff text color.
  case diffContext
  /// The added diff background color.
  case diffAdditionBackground
  /// The deleted diff background color.
  case diffDeletionBackground
  /// The Markdown heading color.
  case markdownHeading
  /// The Markdown link color.
  case markdownLink
  /// The Markdown code color.
  case markdownCode
  /// The syntax keyword color.
  case syntaxKeyword
  /// The syntax string color.
  case syntaxString
  /// The syntax number color.
  case syntaxNumber
  /// The syntax comment color.
  case syntaxComment
  /// The syntax type color.
  case syntaxType
  /// The selected content background color.
  case selectedBackground
  /// The selected text color.
  case selectedText
}

/// A concrete color or reference to another semantic role.
public enum ThemeColor: Sendable, Hashable {
  /// A concrete RGBA color.
  case rgba(RGBA)
  /// A reference to another semantic color role.
  case reference(SemanticColorRole)
}

/// The semantic colors for one color scheme.
public struct ThemeVariant: Sendable, Hashable {
  /// The colors keyed by semantic role.
  public var colors: [SemanticColorRole: ThemeColor]

  /// Creates a theme variant.
  public init(_ colors: [SemanticColorRole: ThemeColor] = [:]) {
    self.colors = colors
  }
}

/// An error produced while resolving a semantic theme.
public enum SemanticThemeError: Error, Sendable, Equatable {
  /// No color exists for a role and scheme.
  case missing(role: SemanticColorRole, scheme: ColorScheme)
  /// Semantic color references contain a cycle.
  case referenceCycle(scheme: ColorScheme, path: [SemanticColorRole])
}

/// The color capability available in a terminal.
public enum DesignColorCapability: Sendable, Hashable {
  /// Direct RGB color support.
  case trueColor
  /// The 256-color ANSI palette.
  case ansi256
  /// The 16-color ANSI palette.
  case ansi16
}

/// A semantic color resolved for a terminal capability.
public enum ResolvedTerminalColor: Sendable, Hashable {
  /// A direct RGBA color.
  case trueColor(RGBA)
  /// An ANSI 256-color index and its RGBA approximation.
  case ansi256(index: UInt8, color: RGBA)
  /// An ANSI 16-color index and its RGBA approximation.
  case ansi16(index: UInt8, color: RGBA)

  /// The resolved RGBA color.
  public var color: RGBA {
    switch self {
    case let .trueColor(color), let .ansi256(_, color), let .ansi16(_, color): color
    }
  }
}

/// A semantic theme resolved to concrete RGBA colors.
public struct ResolvedSemanticTheme: Sendable, Hashable {
  /// The resolved color scheme.
  public var scheme: ColorScheme
  /// The concrete colors keyed by semantic role.
  public var colors: [SemanticColorRole: RGBA]

  /// Creates a resolved semantic theme.
  public init(scheme: ColorScheme, colors: [SemanticColorRole: RGBA]) {
    self.scheme = scheme
    self.colors = colors
  }

  /// Returns the concrete color for a semantic role.
  /// - Complexity: O(1) on average.
  public subscript(_ role: SemanticColorRole) -> RGBA {
    precondition(colors[role] != nil, "The resolved theme does not contain \(role.rawValue).")
    return colors[role]!
  }

  /// Creates a semantic palette with names under the specified prefix.
  /// - Complexity: O(*n*), where *n* is the number of theme colors.
  public func palette(prefix: String = "tui") -> SemanticPalette {
    SemanticPalette(
      Dictionary(
        uniqueKeysWithValues: colors.map { role, color in
          (SemanticColor(rawValue: "\(prefix).\(role.rawValue)"), Color.rgba(color))
        }
      )
    )
  }
}

/// Light and dark variants of a semantic color theme.
public struct SemanticTheme: Sendable, Hashable {
  /// The light theme variant.
  public var light: ThemeVariant
  /// The dark theme variant.
  public var dark: ThemeVariant

  /// Creates a semantic theme.
  public init(light: ThemeVariant, dark: ThemeVariant) {
    self.light = light
    self.dark = dark
  }

  /// Resolves one semantic role for a color scheme.
  /// - Complexity: O(*n*), where *n* is the reference-chain length.
  public func resolve(
    _ role: SemanticColorRole,
    scheme: ColorScheme,
    fallback: SemanticTheme = .standard
  ) throws -> RGBA {
    if role == .selectedText, variant(for: scheme).colors[role] == nil {
      let selection = try resolve(.selectedBackground, scheme: scheme, fallback: fallback)
      let background = try resolve(.background, scheme: scheme, fallback: fallback)
      return Self.readableText(over: selection.composited(over: background))
    }

    var path: [SemanticColorRole] = []
    var visited: Set<SemanticColorRole> = []
    var current = role
    while true {
      guard visited.insert(current).inserted else {
        let start = path.firstIndex(of: current) ?? path.startIndex
        throw SemanticThemeError.referenceCycle(scheme: scheme, path: Array(path[start...]) + [current])
      }
      path.append(current)

      let value = variant(for: scheme).colors[current] ?? fallback.variant(for: scheme).colors[current]
      guard let value else { throw SemanticThemeError.missing(role: current, scheme: scheme) }
      switch value {
      case let .rgba(color): return color
      case let .reference(reference): current = reference
      }
    }
  }

  /// Resolves every semantic role for a color scheme.
  /// - Complexity: O(*r* × *n*), where *r* is the role count and *n* is the maximum reference-chain length.
  public func resolve(
    scheme: ColorScheme,
    fallback: SemanticTheme = .standard
  ) throws -> ResolvedSemanticTheme {
    var colors: [SemanticColorRole: RGBA] = [:]
    for role in SemanticColorRole.allCases {
      colors[role] = try resolve(role, scheme: scheme, fallback: fallback)
    }
    return ResolvedSemanticTheme(scheme: scheme, colors: colors)
  }

  /// Resolves a semantic role for a terminal color capability.
  /// - Complexity: O(*n* + *p*), where *n* is the reference-chain length and *p* is the palette size.
  public func resolve(
    _ role: SemanticColorRole,
    scheme: ColorScheme,
    capability: DesignColorCapability,
    fallback: SemanticTheme = .standard
  ) throws -> ResolvedTerminalColor {
    let color = try resolve(role, scheme: scheme, fallback: fallback)
    switch capability {
    case .trueColor:
      return .trueColor(color)
    case .ansi256:
      let match = Self.nearestColor(to: color, indexes: 16 ..< 256)
      return .ansi256(index: UInt8(match.index), color: match.color)
    case .ansi16:
      let match = Self.nearestColor(to: color, indexes: 0 ..< 16)
      return .ansi16(index: UInt8(match.index), color: match.color)
    }
  }

  /// Validates that all roles resolve for both color schemes.
  /// - Complexity: O(*r* × *n*), where *r* is the role count and *n* is the maximum reference-chain length.
  public func validate(fallback: SemanticTheme = .standard) throws {
    for scheme in [ColorScheme.light, .dark] {
      for role in SemanticColorRole.allCases {
        _ = try resolve(role, scheme: scheme, fallback: fallback)
      }
    }
  }

  /// Returns the WCAG contrast ratio between two colors.
  /// - Complexity: O(1).
  public static func contrastRatio(_ first: RGBA, _ second: RGBA) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// Returns black or white, whichever has greater contrast over the background.
  /// - Complexity: O(1).
  public static func readableText(over background: RGBA) -> RGBA {
    contrastRatio(.black, background) >= contrastRatio(.white, background) ? .black : .white
  }

  /// The standard TermKit semantic theme.
  public static let standard = SemanticTheme(
    light: ThemeVariant(Self.lightColors),
    dark: ThemeVariant(Self.darkColors)
  )

  private func variant(for scheme: ColorScheme) -> ThemeVariant {
    scheme == .light ? light : dark
  }

  private static func relativeLuminance(_ color: RGBA) -> Double {
    func linear(_ component: Double) -> Double {
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
  }

  private static func nearestColor(to target: RGBA, indexes: Range<Int>) -> (index: Int, color: RGBA) {
    var best = (index: indexes.lowerBound, color: paletteColor(indexes.lowerBound))
    var distance = Double.greatestFiniteMagnitude
    for index in indexes {
      let candidate = paletteColor(index)
      let candidateDistance = squaredDistance(target, candidate)
      if candidateDistance < distance {
        best = (index, candidate)
        distance = candidateDistance
      }
    }
    return best
  }

  private static func squaredDistance(_ lhs: RGBA, _ rhs: RGBA) -> Double {
    let red = lhs.red - rhs.red
    let green = lhs.green - rhs.green
    let blue = lhs.blue - rhs.blue
    return red * red + green * green + blue * blue
  }

  private static func paletteColor(_ index: Int) -> RGBA {
    let system: [(UInt8, UInt8, UInt8)] = [
      (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
      (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
      (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
      (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)
    ]
    if index < 16 {
      let value = system[index]
      return RGBA(redByte: value.0, greenByte: value.1, blueByte: value.2)
    }
    if index < 232 {
      let value = index - 16
      let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
      return RGBA(
        redByte: levels[value / 36],
        greenByte: levels[(value / 6) % 6],
        blueByte: levels[value % 6]
      )
    }
    let level = UInt8(8 + (index - 232) * 10)
    return RGBA(redByte: level, greenByte: level, blueByte: level)
  }

  private static let lightColors: [SemanticColorRole: ThemeColor] = [
    .primary: .rgba(RGBA(redByte: 32, greenByte: 42, blueByte: 54)),
    .secondary: .rgba(RGBA(redByte: 78, greenByte: 94, blueByte: 112)),
    .accent: .rgba(RGBA(redByte: 0, greenByte: 103, blueByte: 192)),
    .error: .rgba(RGBA(redByte: 183, greenByte: 28, blueByte: 28)),
    .warning: .rgba(RGBA(redByte: 145, greenByte: 92, blueByte: 0)),
    .success: .rgba(RGBA(redByte: 28, greenByte: 122, blueByte: 68)),
    .info: .reference(.accent),
    .text: .reference(.primary),
    .mutedText: .reference(.secondary),
    .background: .rgba(RGBA(redByte: 247, greenByte: 249, blueByte: 251)),
    .panel: .rgba(RGBA(redByte: 237, greenByte: 241, blueByte: 245)),
    .element: .rgba(RGBA(redByte: 223, greenByte: 229, blueByte: 235)),
    .menu: .reference(.panel),
    .borderRegular: .rgba(RGBA(redByte: 145, greenByte: 157, blueByte: 170)),
    .borderActive: .reference(.accent),
    .borderSubtle: .rgba(RGBA(redByte: 199, greenByte: 207, blueByte: 215)),
    .diffAddition: .rgba(RGBA(redByte: 20, greenByte: 105, blueByte: 55)),
    .diffDeletion: .rgba(RGBA(redByte: 170, greenByte: 30, blueByte: 45)),
    .diffContext: .reference(.mutedText),
    .diffAdditionBackground: .rgba(RGBA(redByte: 220, greenByte: 244, blueByte: 228)),
    .diffDeletionBackground: .rgba(RGBA(redByte: 255, greenByte: 226, blueByte: 229)),
    .markdownHeading: .reference(.primary),
    .markdownLink: .reference(.accent),
    .markdownCode: .rgba(RGBA(redByte: 112, greenByte: 56, blueByte: 135)),
    .syntaxKeyword: .rgba(RGBA(redByte: 137, greenByte: 42, blueByte: 163)),
    .syntaxString: .rgba(RGBA(redByte: 26, greenByte: 112, blueByte: 64)),
    .syntaxNumber: .rgba(RGBA(redByte: 159, greenByte: 67, blueByte: 0)),
    .syntaxComment: .reference(.mutedText),
    .syntaxType: .rgba(RGBA(redByte: 0, greenByte: 91, blueByte: 135)),
    .selectedBackground: .reference(.accent)
  ]

  private static let darkColors: [SemanticColorRole: ThemeColor] = [
    .primary: .rgba(RGBA(redByte: 226, greenByte: 232, blueByte: 240)),
    .secondary: .rgba(RGBA(redByte: 151, greenByte: 166, blueByte: 184)),
    .accent: .rgba(RGBA(redByte: 80, greenByte: 166, blueByte: 255)),
    .error: .rgba(RGBA(redByte: 255, greenByte: 105, blueByte: 118)),
    .warning: .rgba(RGBA(redByte: 240, greenByte: 184, blueByte: 80)),
    .success: .rgba(RGBA(redByte: 86, greenByte: 201, blueByte: 130)),
    .info: .reference(.accent),
    .text: .reference(.primary),
    .mutedText: .reference(.secondary),
    .background: .rgba(RGBA(redByte: 14, greenByte: 20, blueByte: 27)),
    .panel: .rgba(RGBA(redByte: 24, greenByte: 32, blueByte: 42)),
    .element: .rgba(RGBA(redByte: 37, greenByte: 47, blueByte: 59)),
    .menu: .reference(.panel),
    .borderRegular: .rgba(RGBA(redByte: 91, greenByte: 106, blueByte: 124)),
    .borderActive: .reference(.accent),
    .borderSubtle: .rgba(RGBA(redByte: 55, greenByte: 68, blueByte: 82)),
    .diffAddition: .rgba(RGBA(redByte: 91, greenByte: 214, blueByte: 137)),
    .diffDeletion: .rgba(RGBA(redByte: 255, greenByte: 119, blueByte: 130)),
    .diffContext: .reference(.mutedText),
    .diffAdditionBackground: .rgba(RGBA(redByte: 24, greenByte: 65, blueByte: 43)),
    .diffDeletionBackground: .rgba(RGBA(redByte: 79, greenByte: 36, blueByte: 43)),
    .markdownHeading: .reference(.primary),
    .markdownLink: .reference(.accent),
    .markdownCode: .rgba(RGBA(redByte: 213, greenByte: 145, blueByte: 238)),
    .syntaxKeyword: .rgba(RGBA(redByte: 220, greenByte: 139, blueByte: 255)),
    .syntaxString: .rgba(RGBA(redByte: 125, greenByte: 217, blueByte: 152)),
    .syntaxNumber: .rgba(RGBA(redByte: 255, greenByte: 174, blueByte: 103)),
    .syntaxComment: .reference(.mutedText),
    .syntaxType: .rgba(RGBA(redByte: 97, greenByte: 202, blueByte: 255)),
    .selectedBackground: .reference(.accent)
  ]
}
