#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A color with normalized red, green, blue, and alpha components.
public struct RGBA: Sendable, Hashable {
    /// The normalized red component.
    public var red: Double
    /// The normalized green component.
    public var green: Double
    /// The normalized blue component.
    public var blue: Double
    /// The normalized alpha component.
    public var alpha: Double

    /// Creates a color and clamps each component to the range from zero through one.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        precondition(red.isFinite && green.isFinite && blue.isFinite && alpha.isFinite, "RGBA components must be finite.")
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Creates a color from 8-bit component values.
    public init(redByte: UInt8, greenByte: UInt8, blueByte: UInt8, alphaByte: UInt8 = 255) {
        self.init(
            red: Double(redByte) / 255,
            green: Double(greenByte) / 255,
            blue: Double(blueByte) / 255,
            alpha: Double(alphaByte) / 255
        )
    }

    /// A fully transparent black color.
    public static let clear = RGBA(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    /// An opaque black color.
    public static let black = RGBA(red: 0.0, green: 0.0, blue: 0.0)
    /// An opaque white color.
    public static let white = RGBA(red: 1.0, green: 1.0, blue: 1.0)

    /// Returns the linear-light interpolation to another color.
    public func interpolated(to other: RGBA, progress: Double) -> RGBA {
        let amount = Self.clamp(progress)
        return RGBA(
            red: Self.linearToSRGB(Self.mix(Self.sRGBToLinear(red), Self.sRGBToLinear(other.red), amount)),
            green: Self.linearToSRGB(Self.mix(Self.sRGBToLinear(green), Self.sRGBToLinear(other.green), amount)),
            blue: Self.linearToSRGB(Self.mix(Self.sRGBToLinear(blue), Self.sRGBToLinear(other.blue), amount)),
            alpha: Self.mix(alpha, other.alpha, amount)
        )
    }

    /// Returns a color with its alpha component multiplied by an opacity value.
    public func applyingOpacity(_ opacity: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha * Self.clamp(opacity))
    }

    /// Returns this color composited over a background color.
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

    /// The red component as an 8-bit value.
    public var redByte: UInt8 { Self.byte(red) }
    /// The green component as an 8-bit value.
    public var greenByte: UInt8 { Self.byte(green) }
    /// The blue component as an 8-bit value.
    public var blueByte: UInt8 { Self.byte(blue) }
    /// The alpha component as an 8-bit value.
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

/// A named color reference.
public struct SemanticColor: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    /// The color name.
    public var rawValue: String

    /// Creates a semantic color from a nonempty name.
    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A semantic color name must not be empty.")
        self.rawValue = rawValue
    }

    /// Creates a semantic color from a string literal.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// A concrete or semantic color value.
public enum Color: Sendable, Hashable {
    /// A concrete color.
    case rgba(RGBA)
    /// A semantic color reference.
    case semantic(SemanticColor)

    /// Creates a semantic color from a name.
    public static func makeSemantic(_ name: String) -> Color {
        .semantic(SemanticColor(rawValue: name))
    }
}

/// An error that occurs while resolving a semantic color.
public enum ColorResolutionError: Error, Sendable, Equatable {
    /// The palette does not define the semantic color.
    case missing(SemanticColor)
    /// Semantic color references form a cycle.
    case cycle([SemanticColor])
}

/// A mapping from semantic colors to concrete or semantic color values.
public struct SemanticPalette: Sendable, Hashable {
    /// The values associated with semantic colors.
    public var values: [SemanticColor: Color]

    /// Creates a palette from semantic color values.
    public init(_ values: [SemanticColor: Color] = [:]) {
        self.values = values
    }

    /// Resolves a color to its concrete value.
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

    /// Validates that every palette value resolves to a concrete color.
    public func validate() throws {
        for reference in values.keys {
            _ = try resolve(.semantic(reference))
        }
    }
}
