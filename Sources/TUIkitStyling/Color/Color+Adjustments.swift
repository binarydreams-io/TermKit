//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color+Adjustments.swift
//
//  Created by LAYERED.work
//  License: MIT

extension Color {
  /// Returns a lighter version of this color.
  ///
  /// The percentage is relative to the remaining lightness headroom.
  /// For example, a color with HSL lightness 60 lightened by 0.5 (50%)
  /// moves halfway toward 100: `60 + (100 − 60) × 0.5 = 80`.
  ///
  /// - Parameter percentage: The fraction to lighten (0–1, default 0.2 = 20%).
  /// - Returns: A lighter color with preserved hue and saturation.
  public func lighter(by percentage: Double = 0.2) -> Self {
    adjusted(by: percentage)
  }

  /// Returns a darker version of this color.
  ///
  /// The percentage is relative to the current lightness.
  /// For example, a color with HSL lightness 60 darkened by 0.5 (50%)
  /// moves halfway toward 0: `60 × (1 − 0.5) = 30`.
  ///
  /// - Parameter percentage: The fraction to darken (0–1, default 0.2 = 20%).
  /// - Returns: A darker color with preserved hue and saturation.
  public func darker(by percentage: Double = 0.2) -> Self {
    adjusted(by: -percentage)
  }

  /// Returns a color with adjusted opacity (simulated via color mixing).
  ///
  /// Since terminals don't support true transparency, this mixes
  /// the color with black to simulate opacity. Works with all color types
  /// by converting to RGB first.
  ///
  /// - Parameter opacity: The opacity (0-1).
  /// - Returns: A color simulating the given opacity, or self if semantic.
  public func opacity(_ opacity: Double) -> Self {
    guard let (red, green, blue) = rgbComponents else {
      return self
    }

    let newRed = UInt8(Double(red) * opacity)
    let newGreen = UInt8(Double(green) * opacity)
    let newBlue = UInt8(Double(blue) * opacity)

    return .rgb(newRed, newGreen, newBlue)
  }

  /// Linearly interpolates between two colors.
  ///
  /// Both colors are converted to RGB before interpolation. If either
  /// color is semantic (unresolved), the `from` color is returned unchanged.
  ///
  /// Used by the breathing focus indicator to smoothly fade between
  /// a dimmed and a full-brightness accent color.
  ///
  /// - Parameters:
  ///   - from: The start color (returned when `phase` is 0).
  ///   - to: The end color (returned when `phase` is 1).
  ///   - phase: The interpolation factor (0–1, clamped).
  /// - Returns: The interpolated RGB color.
  public static func lerp(_ from: Color, _ to: Color, phase: Double) -> Color {
    guard let fromRGB = from.rgbComponents,
          let toRGB = to.rgbComponents
    else {
      return from
    }

    let clamped = min(1, max(0, phase))
    let red = UInt8(Double(fromRGB.red) + (Double(toRGB.red) - Double(fromRGB.red)) * clamped)
    let green = UInt8(
      Double(fromRGB.green) + (Double(toRGB.green) - Double(fromRGB.green)) * clamped
    )
    let blue = UInt8(
      Double(fromRGB.blue) + (Double(toRGB.blue) - Double(fromRGB.blue)) * clamped
    )

    return .rgb(red, green, blue)
  }

  /// Converts RGB components to HSL (hue 0–360, saturation 0–100, lightness 0–100).
  ///
  /// - Parameters:
  ///   - red: Red component (0–255).
  ///   - green: Green component (0–255).
  ///   - blue: Blue component (0–255).
  /// - Returns: A tuple of (hue, saturation, lightness) in their standard ranges.
  public static func rgbToHSL(red: UInt8, green: UInt8, blue: UInt8) -> (hue: Double, saturation: Double, lightness: Double) {
    let normalizedRed = Double(red) / 255.0
    let normalizedGreen = Double(green) / 255.0
    let normalizedBlue = Double(blue) / 255.0

    let maxComponent = max(normalizedRed, normalizedGreen, normalizedBlue)
    let minComponent = min(normalizedRed, normalizedGreen, normalizedBlue)
    let delta = maxComponent - minComponent

    let lightness = (maxComponent + minComponent) / 2.0

    guard delta > 0 else {
      // Achromatic (gray)
      return (hue: 0, saturation: 0, lightness: lightness * 100)
    }

    let saturation: Double = if lightness < 0.5 {
      delta / (maxComponent + minComponent)
    } else {
      delta / (2.0 - maxComponent - minComponent)
    }

    let hue: Double
    switch maxComponent {
    case normalizedRed:
      let segment = (normalizedGreen - normalizedBlue) / delta
      hue = 60 * (segment < 0 ? segment + 6 : segment)
    case normalizedGreen:
      hue = 60 * ((normalizedBlue - normalizedRed) / delta + 2)
    default:
      hue = 60 * ((normalizedRed - normalizedGreen) / delta + 4)
    }

    return (hue: hue, saturation: saturation * 100, lightness: lightness * 100)
  }
}

extension Color {
  /// Adjusts a color's lightness by a relative percentage in HSL space.
  ///
  /// Positive values lighten (move toward 100), negative values darken
  /// (move toward 0). The adjustment is **relative** to the current position:
  ///
  /// - Lighten: `newLightness = lightness + (100 − lightness) × percentage`
  /// - Darken:  `newLightness = lightness × (1 − |percentage|)`
  ///
  /// This means 0.5 always moves halfway to the target extreme, regardless
  /// of the starting lightness. Hue and saturation are preserved.
  ///
  /// - Parameter percentage: The relative adjustment (−1 to 1).
  /// - Returns: The adjusted color as HSL, or self if semantic (unresolved).
  private func adjusted(by percentage: Double) -> Self {
    guard let (red, green, blue) = rgbComponents else {
      return self
    }

    let (hue, saturation, lightness) = Self.rgbToHSL(red: red, green: green, blue: blue)
    let clamped = min(1.0, max(-1.0, percentage))

    let newLightness: Double = if clamped >= 0 {
      // Lighten: move toward 100
      lightness + (100.0 - lightness) * clamped
    } else {
      // Darken: move toward 0
      lightness * (1.0 + clamped)
    }

    return .hsl(hue, saturation, min(100, max(0, newLightness)))
  }
}
