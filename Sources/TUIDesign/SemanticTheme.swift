import Foundation
import TUIFoundation

public enum ColorScheme: Sendable, Hashable {
    case light
    case dark
}

public enum SemanticColorRole: String, CaseIterable, Sendable, Hashable {
    case primary
    case secondary
    case accent
    case error
    case warning
    case success
    case info
    case text
    case mutedText
    case background
    case panel
    case element
    case menu
    case borderRegular
    case borderActive
    case borderSubtle
    case diffAddition
    case diffDeletion
    case diffContext
    case diffAdditionBackground
    case diffDeletionBackground
    case markdownHeading
    case markdownLink
    case markdownCode
    case syntaxKeyword
    case syntaxString
    case syntaxNumber
    case syntaxComment
    case syntaxType
    case selectedBackground
    case selectedText
}

public enum ThemeColor: Sendable, Hashable {
    case rgba(RGBA)
    case reference(SemanticColorRole)
}

public struct ThemeVariant: Sendable, Hashable {
    public var colors: [SemanticColorRole: ThemeColor]

    public init(_ colors: [SemanticColorRole: ThemeColor] = [:]) {
        self.colors = colors
    }
}

public enum SemanticThemeError: Error, Sendable, Equatable {
    case missing(role: SemanticColorRole, scheme: ColorScheme)
    case referenceCycle(scheme: ColorScheme, path: [SemanticColorRole])
}

public enum DesignColorCapability: Sendable, Hashable {
    case trueColor
    case ansi256
    case ansi16
}

public enum ResolvedTerminalColor: Sendable, Hashable {
    case trueColor(RGBA)
    case ansi256(index: UInt8, color: RGBA)
    case ansi16(index: UInt8, color: RGBA)

    public var color: RGBA {
        switch self {
        case .trueColor(let color), .ansi256(_, let color), .ansi16(_, let color): color
        }
    }
}

public struct ResolvedSemanticTheme: Sendable, Hashable {
    public var scheme: ColorScheme
    public var colors: [SemanticColorRole: RGBA]

    public init(scheme: ColorScheme, colors: [SemanticColorRole: RGBA]) {
        self.scheme = scheme
        self.colors = colors
    }

    public subscript(_ role: SemanticColorRole) -> RGBA {
        precondition(colors[role] != nil, "The resolved theme does not contain \(role.rawValue).")
        return colors[role]!
    }

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

public struct SemanticTheme: Sendable, Hashable {
    public var light: ThemeVariant
    public var dark: ThemeVariant

    public init(light: ThemeVariant, dark: ThemeVariant) {
        self.light = light
        self.dark = dark
    }

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
            case .rgba(let color): return color
            case .reference(let reference): current = reference
            }
        }
    }

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
            let match = Self.nearestColor(to: color, indexes: 16..<256)
            return .ansi256(index: UInt8(match.index), color: match.color)
        case .ansi16:
            let match = Self.nearestColor(to: color, indexes: 0..<16)
            return .ansi16(index: UInt8(match.index), color: match.color)
        }
    }

    public func validate(fallback: SemanticTheme = .standard) throws {
        for scheme in [ColorScheme.light, .dark] {
            for role in SemanticColorRole.allCases {
                _ = try resolve(role, scheme: scheme, fallback: fallback)
            }
        }
    }

    public static func contrastRatio(_ first: RGBA, _ second: RGBA) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func readableText(over background: RGBA) -> RGBA {
        contrastRatio(.black, background) >= contrastRatio(.white, background) ? .black : .white
    }

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
            (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
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
        .selectedBackground: .reference(.accent),
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
        .selectedBackground: .reference(.accent),
    ]
}
