//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color+Construction.swift
//
//  Created by LAYERED.work
//  License: MIT

extension Color {
  /// Resolves this color against a palette.
  ///
  /// Non-semantic colors are returned unchanged. Semantic colors
  /// are mapped to the corresponding palette property.
  ///
  /// - Parameter palette: The palette to resolve against.
  /// - Returns: A concrete (non-semantic) color.
  public func resolve(with palette: any Palette) -> Color {
    guard case let .semantic(token) = value else { return self }
    return token.resolve(with: palette)
  }

  /// Creates a color from the 256-color palette.
  ///
  /// - Parameter index: The palette index (0-255).
  /// - Returns: The corresponding color.
  public static func palette(_ index: UInt8) -> Self {
    Self(value: .palette256(index))
  }

  /// Creates a True Color RGB color.
  ///
  /// - Parameters:
  ///   - red: The red component (0-255).
  ///   - green: The green component (0-255).
  ///   - blue: The blue component (0-255).
  /// - Returns: The RGB color.
  public static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Self {
    Self(value: .rgb(red: red, green: green, blue: blue))
  }

  /// Creates a color from a hex value.
  ///
  /// - Parameter hex: The hex value (e.g., 0xFF5500).
  /// - Returns: The corresponding RGB color.
  public static func hex(_ hex: UInt32) -> Self {
    let red = UInt8((hex >> 16) & 0xFF)
    let green = UInt8((hex >> 8) & 0xFF)
    let blue = UInt8(hex & 0xFF)
    return .rgb(red, green, blue)
  }

  /// Creates a color from a hex string.
  ///
  /// Supports formats: "#RGB", "#RRGGBB", "RGB", "RRGGBB"
  ///
  /// - Parameter hex: The hex string (e.g., "#FF5500", "F50", "#abc").
  /// - Returns: The corresponding RGB color, or nil if invalid.
  public static func hex(_ hex: String) -> Self? {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove # prefix if present
    if hexString.hasPrefix("#") {
      hexString.removeFirst()
    }

    // Handle shorthand format (RGB -> RRGGBB)
    if hexString.count == 3 {
      let chars = Array(hexString)
      hexString = String([chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]])
    }

    // Must be 6 characters now
    guard hexString.count == 6 else { return nil }

    // Parse hex value
    guard let hexValue = UInt32(hexString, radix: 16) else { return nil }

    return .hex(hexValue)
  }

  /// Creates a color from HSL values.
  ///
  /// - Parameters:
  ///   - hue: The hue component (0-360).
  ///   - saturation: The saturation component (0-100).
  ///   - lightness: The lightness component (0-100).
  /// - Returns: The corresponding RGB color.
  public static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Self {
    let normalizedHue = hue / 360.0
    let normalizedSaturation = saturation / 100.0
    let normalizedLightness = lightness / 100.0

    if normalizedSaturation == 0 {
      // Achromatic (gray)
      let gray = UInt8(normalizedLightness * 255)
      return .rgb(gray, gray, gray)
    }

    let chromaFactor =
      normalizedLightness < 0.5
        ? normalizedLightness * (1 + normalizedSaturation)
        : normalizedLightness + normalizedSaturation - normalizedLightness * normalizedSaturation
    let luminanceFactor = 2 * normalizedLightness - chromaFactor

    func hueToRGB(_ luminance: Double, _ chroma: Double, _ hueComponent: Double) -> Double {
      var adjustedHue = hueComponent
      if adjustedHue < 0 {
        adjustedHue += 1
      }
      if adjustedHue > 1 {
        adjustedHue -= 1
      }
      if adjustedHue < 1 / 6 {
        return luminance + (chroma - luminance) * 6 * adjustedHue
      }
      if adjustedHue < 1 / 2 {
        return chroma
      }
      if adjustedHue < 2 / 3 {
        return luminance + (chroma - luminance) * (2 / 3 - adjustedHue) * 6
      }
      return luminance
    }

    let red = UInt8(hueToRGB(luminanceFactor, chromaFactor, normalizedHue + 1 / 3) * 255)
    let green = UInt8(hueToRGB(luminanceFactor, chromaFactor, normalizedHue) * 255)
    let blue = UInt8(hueToRGB(luminanceFactor, chromaFactor, normalizedHue - 1 / 3) * 255)

    return .rgb(red, green, blue)
  }
}
