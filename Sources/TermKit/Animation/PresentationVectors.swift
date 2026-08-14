#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A linear-light RGBA color used for animation.
public struct LinearRGBA: VectorArithmetic, Hashable {
  /// The linear red component.
  public var red: Double
  /// The linear green component.
  public var green: Double
  /// The linear blue component.
  public var blue: Double
  /// The alpha component.
  public var alpha: Double

  /// Creates a linear-light color.
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

  /// Creates a linear-light color from an sRGB color.
  public init(_ color: RGBA) {
    self.init(red: Self.toLinear(color.red), green: Self.toLinear(color.green), blue: Self.toLinear(color.blue), alpha: color.alpha)
  }

  /// The corresponding sRGB color.
  public var rgba: RGBA {
    RGBA(red: Self.toSRGB(red), green: Self.toSRGB(green), blue: Self.toSRGB(blue), alpha: alpha)
  }

  /// The transparent additive identity.
  public static let zero = LinearRGBA(red: 0, green: 0, blue: 0, alpha: 0)

  /// Adds corresponding color components.
  /// - Complexity: O(1).
  public static func + (lhs: Self, rhs: Self) -> Self {
    Self(
      uncheckedRed: lhs.red + rhs.red,
      green: lhs.green + rhs.green,
      blue: lhs.blue + rhs.blue,
      alpha: lhs.alpha + rhs.alpha
    )
  }

  /// Subtracts corresponding color components.
  /// - Complexity: O(1).
  public static func - (lhs: Self, rhs: Self) -> Self {
    Self(
      uncheckedRed: lhs.red - rhs.red,
      green: lhs.green - rhs.green,
      blue: lhs.blue - rhs.blue,
      alpha: lhs.alpha - rhs.alpha
    )
  }

  /// Multiplies each component by a scalar.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {
    red *= scalar
    green *= scalar
    blue *= scalar
    alpha *= scalar
  }

  /// The sum of squared color components.
  public var magnitudeSquared: Double {
    red * red + green * green + blue * blue + alpha * alpha
  }

  private static func toLinear(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  private static func toSRGB(_ value: Double) -> Double {
    value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
  }
}

/// A two-dimensional cell-space vector.
public struct CellVector: VectorArithmetic, Hashable {
  /// The horizontal component.
  public var x: Double
  /// The vertical component.
  public var y: Double

  /// Creates a cell vector.
  public init(x: Double = 0, y: Double = 0) {
    precondition(x.isFinite && y.isFinite, "CellVector components must be finite.")
    self.init(uncheckedX: x, y: y)
  }

  private init(uncheckedX x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  /// Creates a vector from an integer cell point.
  public init(_ point: CellPoint) {
    self.init(x: Double(point.x), y: Double(point.y))
  }

  /// The additive identity.
  public static let zero = CellVector()
  /// Adds corresponding components.
  /// - Complexity: O(1).
  public static func + (lhs: Self, rhs: Self) -> Self {
    Self(uncheckedX: lhs.x + rhs.x, y: lhs.y + rhs.y)
  }

  /// Subtracts corresponding components.
  /// - Complexity: O(1).
  public static func - (lhs: Self, rhs: Self) -> Self {
    Self(uncheckedX: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }

  /// Multiplies each component by a scalar.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {
    x *= scalar
    y *= scalar
  }

  /// The sum of squared components.
  public var magnitudeSquared: Double {
    x * x + y * y
  }
}

/// Floating-point width and height values used for animation.
public struct CellDimensions: VectorArithmetic, Hashable {
  /// The width component.
  public var width: Double
  /// The height component.
  public var height: Double

  /// Creates floating-point cell dimensions.
  public init(width: Double = 0, height: Double = 0) {
    precondition(width.isFinite && height.isFinite, "CellDimensions components must be finite.")
    self.init(uncheckedWidth: width, height: height)
  }

  private init(uncheckedWidth width: Double, height: Double) {
    self.width = width
    self.height = height
  }

  /// Creates dimensions from an integer cell size.
  public init(_ size: CellSize) {
    self.init(width: Double(size.width), height: Double(size.height))
  }

  /// The additive identity.
  public static let zero = CellDimensions()
  /// Adds corresponding components.
  /// - Complexity: O(1).
  public static func + (lhs: Self, rhs: Self) -> Self {
    Self(uncheckedWidth: lhs.width + rhs.width, height: lhs.height + rhs.height)
  }

  /// Subtracts corresponding components.
  /// - Complexity: O(1).
  public static func - (lhs: Self, rhs: Self) -> Self {
    Self(uncheckedWidth: lhs.width - rhs.width, height: lhs.height - rhs.height)
  }

  /// Multiplies each component by a scalar.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {
    width *= scalar
    height *= scalar
  }

  /// The sum of squared components.
  public var magnitudeSquared: Double {
    width * width + height * height
  }
}

/// Floating-point edge insets used for animation.
public struct FloatingEdgeInsets: VectorArithmetic, Hashable {
  /// The top inset.
  public var top: Double
  /// The leading inset.
  public var leading: Double
  /// The bottom inset.
  public var bottom: Double
  /// The trailing inset.
  public var trailing: Double

  /// Creates floating-point edge insets.
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

  /// Creates floating-point insets from integer edge insets.
  public init(_ insets: EdgeInsets) {
    self.init(
      top: Double(insets.top),
      leading: Double(insets.leading),
      bottom: Double(insets.bottom),
      trailing: Double(insets.trailing)
    )
  }

  /// The additive identity.
  public static let zero = FloatingEdgeInsets()
  /// Adds corresponding insets.
  /// - Complexity: O(1).
  public static func + (lhs: Self, rhs: Self) -> Self {
    Self(
      uncheckedTop: lhs.top + rhs.top,
      leading: lhs.leading + rhs.leading,
      bottom: lhs.bottom + rhs.bottom,
      trailing: lhs.trailing + rhs.trailing
    )
  }

  /// Subtracts corresponding insets.
  /// - Complexity: O(1).
  public static func - (lhs: Self, rhs: Self) -> Self {
    Self(
      uncheckedTop: lhs.top - rhs.top,
      leading: lhs.leading - rhs.leading,
      bottom: lhs.bottom - rhs.bottom,
      trailing: lhs.trailing - rhs.trailing
    )
  }

  /// Multiplies each inset by a scalar.
  /// - Complexity: O(1).
  public mutating func scale(by scalar: Double) {
    top *= scalar
    leading *= scalar
    bottom *= scalar
    trailing *= scalar
  }

  /// The sum of squared insets.
  public var magnitudeSquared: Double {
    top * top + leading * leading + bottom * bottom + trailing * trailing
  }
}
