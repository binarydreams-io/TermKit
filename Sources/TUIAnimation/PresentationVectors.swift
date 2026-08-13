#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

import TUIFoundation

public struct LinearRGBA: VectorArithmetic, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        precondition(
            red.isFinite && green.isFinite && blue.isFinite && alpha.isFinite,
            "LinearRGBA components must be finite."
        )
        self.init(uncheckedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private init(uncheckedRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: RGBA) {
        self.init(red: Self.toLinear(color.red), green: Self.toLinear(color.green), blue: Self.toLinear(color.blue), alpha: color.alpha)
    }

    public var rgba: RGBA {
        RGBA(red: Self.toSRGB(red), green: Self.toSRGB(green), blue: Self.toSRGB(blue), alpha: alpha)
    }

    public static let zero = LinearRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            uncheckedRed: lhs.red + rhs.red,
            green: lhs.green + rhs.green,
            blue: lhs.blue + rhs.blue,
            alpha: lhs.alpha + rhs.alpha
        )
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            uncheckedRed: lhs.red - rhs.red,
            green: lhs.green - rhs.green,
            blue: lhs.blue - rhs.blue,
            alpha: lhs.alpha - rhs.alpha
        )
    }

    public mutating func scale(by scalar: Double) {
        red *= scalar
        green *= scalar
        blue *= scalar
        alpha *= scalar
    }

    public var magnitudeSquared: Double { red * red + green * green + blue * blue + alpha * alpha }

    private static func toLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func toSRGB(_ value: Double) -> Double {
        value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

public struct CellVector: VectorArithmetic, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        precondition(x.isFinite && y.isFinite, "CellVector components must be finite.")
        self.init(uncheckedX: x, y: y)
    }
    private init(uncheckedX x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ point: CellPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
    public static let zero = CellVector()
    public static func + (lhs: Self, rhs: Self) -> Self { Self(uncheckedX: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: Self, rhs: Self) -> Self { Self(uncheckedX: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public mutating func scale(by scalar: Double) { x *= scalar; y *= scalar }
    public var magnitudeSquared: Double { x * x + y * y }
}

public struct CellDimensions: VectorArithmetic, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double = 0, height: Double = 0) {
        precondition(width.isFinite && height.isFinite, "CellDimensions components must be finite.")
        self.init(uncheckedWidth: width, height: height)
    }
    private init(uncheckedWidth width: Double, height: Double) { self.width = width; self.height = height }
    public init(_ size: CellSize) { self.init(width: Double(size.width), height: Double(size.height)) }
    public static let zero = CellDimensions()
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(uncheckedWidth: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(uncheckedWidth: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
    public mutating func scale(by scalar: Double) { width *= scalar; height *= scalar }
    public var magnitudeSquared: Double { width * width + height * height }
}

public struct FloatingEdgeInsets: VectorArithmetic, Hashable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        precondition(
            top.isFinite && leading.isFinite && bottom.isFinite && trailing.isFinite,
            "FloatingEdgeInsets components must be finite."
        )
        self.init(uncheckedTop: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    private init(uncheckedTop top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ insets: EdgeInsets) {
        self.init(top: Double(insets.top), leading: Double(insets.leading), bottom: Double(insets.bottom), trailing: Double(insets.trailing))
    }

    public static let zero = FloatingEdgeInsets()
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            uncheckedTop: lhs.top + rhs.top,
            leading: lhs.leading + rhs.leading,
            bottom: lhs.bottom + rhs.bottom,
            trailing: lhs.trailing + rhs.trailing
        )
    }
    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            uncheckedTop: lhs.top - rhs.top,
            leading: lhs.leading - rhs.leading,
            bottom: lhs.bottom - rhs.bottom,
            trailing: lhs.trailing - rhs.trailing
        )
    }
    public mutating func scale(by scalar: Double) { top *= scalar; leading *= scalar; bottom *= scalar; trailing *= scalar }
    public var magnitudeSquared: Double { top * top + leading * leading + bottom * bottom + trailing * trailing }
}
