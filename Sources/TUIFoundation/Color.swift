#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public struct RGBA: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        precondition(red.isFinite && green.isFinite && blue.isFinite && alpha.isFinite, "RGBA components must be finite.")
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    public init(redByte: UInt8, greenByte: UInt8, blueByte: UInt8, alphaByte: UInt8 = 255) {
        self.init(
            red: Double(redByte) / 255,
            green: Double(greenByte) / 255,
            blue: Double(blueByte) / 255,
            alpha: Double(alphaByte) / 255
        )
    }

    public static let clear = RGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    public static let black = RGBA(red: 0.0, green: 0.0, blue: 0.0)
    public static let white = RGBA(red: 1.0, green: 1.0, blue: 1.0)

    public func interpolated(to other: RGBA, progress: Double) -> RGBA {
        let amount = Self.clamp(progress)
        return RGBA(
            red: Self.linearToSRGB(Self.mix(Self.sRGBToLinear(red), Self.sRGBToLinear(other.red), amount)),
            green: Self.linearToSRGB(Self.mix(Self.sRGBToLinear(green), Self.sRGBToLinear(other.green), amount)),
            blue: Self.linearToSRGB(Self.mix(Self.sRGBToLinear(blue), Self.sRGBToLinear(other.blue), amount)),
            alpha: Self.mix(alpha, other.alpha, amount)
        )
    }

    public func applyingOpacity(_ opacity: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha * Self.clamp(opacity))
    }

    public func composited(over background: RGBA) -> RGBA {
        let outputAlpha = alpha + background.alpha * (1 - alpha)
        guard outputAlpha > 0 else { return .clear }
        return RGBA(
            red: (red * alpha + background.red * background.alpha * (1 - alpha)) / outputAlpha,
            green: (green * alpha + background.green * background.alpha * (1 - alpha)) / outputAlpha,
            blue: (blue * alpha + background.blue * background.alpha * (1 - alpha)) / outputAlpha,
            alpha: outputAlpha
        )
    }

    public var redByte: UInt8 { Self.byte(red) }
    public var greenByte: UInt8 { Self.byte(green) }
    public var blueByte: UInt8 { Self.byte(blue) }
    public var alphaByte: UInt8 { Self.byte(alpha) }

    private static func clamp(_ value: Double) -> Double {
        Swift.min(1, Swift.max(0, value))
    }

    private static func mix(_ start: Double, _ end: Double, _ amount: Double) -> Double {
        start + (end - start) * amount
    }

    private static func sRGBToLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Double) -> Double {
        value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((clamp(value) * 255).rounded())
    }
}

public struct SemanticColor: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A semantic color name must not be empty.")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public enum Color: Sendable, Hashable {
    case rgba(RGBA)
    case semantic(SemanticColor)

    public static func semantic(_ name: String) -> Color {
        .semantic(SemanticColor(rawValue: name))
    }
}

public enum ColorResolutionError: Error, Sendable, Equatable {
    case missing(SemanticColor)
    case cycle([SemanticColor])
}

public struct SemanticPalette: Sendable, Hashable {
    public var values: [SemanticColor: Color]

    public init(_ values: [SemanticColor: Color] = [:]) {
        self.values = values
    }

    public func resolve(_ color: Color) throws -> RGBA {
        var path: [SemanticColor] = []
        var visited: Set<SemanticColor> = []
        var current = color

        while true {
            switch current {
            case .rgba(let rgba):
                return rgba
            case .semantic(let reference):
                guard visited.insert(reference).inserted else {
                    let cycleStart = path.firstIndex(of: reference) ?? path.startIndex
                    throw ColorResolutionError.cycle(Array(path[cycleStart...]) + [reference])
                }
                path.append(reference)
                guard let next = values[reference] else {
                    throw ColorResolutionError.missing(reference)
                }
                current = next
            }
        }
    }

    public func validate() throws {
        for reference in values.keys {
            _ = try resolve(.semantic(reference))
        }
    }
}
