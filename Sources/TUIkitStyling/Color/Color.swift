//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A color for use in TUIkit views.
///
/// `Color` represents standard ANSI colors as well as
/// extended 256-color palette and True Color (24-bit RGB).
///
/// # Standard Colors
///
/// ```swift
/// Text("Red").foregroundStyle(.red)
/// Text("Green").foregroundStyle(.green)
/// Text("Blue").foregroundStyle(.blue)
/// ```
///
/// # RGB Colors
///
/// ```swift
/// Text("Custom").foregroundStyle(.rgb(255, 128, 0))
/// ```
public struct Color: Sendable, Equatable {
  /// The internal color value.
  public let value: ColorValue

  /// Internal enum for different color types.
  public enum ColorValue: Sendable, Equatable {
    case standard(ANSIColor)
    case bright(ANSIColor)
    case palette256(UInt8)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
    case semantic(SemanticColor)
  }

  // MARK: - Standard ANSI Colors

  /// Black (ANSI 30/40)
  public static let black = Self(value: .standard(.black))

  /// Red (ANSI 31/41)
  public static let red = Self(value: .standard(.red))

  /// Green (ANSI 32/42)
  public static let green = Self(value: .standard(.green))

  /// Yellow (ANSI 33/43)
  public static let yellow = Self(value: .standard(.yellow))

  /// Blue (ANSI 34/44)
  public static let blue = Self(value: .standard(.blue))

  /// Magenta (ANSI 35/45)
  public static let magenta = Self(value: .standard(.magenta))

  /// Cyan (ANSI 36/46)
  public static let cyan = Self(value: .standard(.cyan))

  /// White (ANSI 37/47)
  public static let white = Self(value: .standard(.white))

  /// Default color (terminal default)
  public static let `default` = Self(value: .standard(.default))

  // MARK: - Bright ANSI Colors

  /// Bright black (gray)
  public static let brightBlack = Self(value: .bright(.black))

  /// Bright red
  public static let brightRed = Self(value: .bright(.red))

  /// Bright green
  public static let brightGreen = Self(value: .bright(.green))

  /// Bright yellow
  public static let brightYellow = Self(value: .bright(.yellow))

  /// Bright blue
  public static let brightBlue = Self(value: .bright(.blue))

  /// Bright magenta
  public static let brightMagenta = Self(value: .bright(.magenta))

  /// Bright cyan
  public static let brightCyan = Self(value: .bright(.cyan))

  /// Bright white
  public static let brightWhite = Self(value: .bright(.white))

  // MARK: - Semantic Colors

  /// Primary color (default: blue)
  public static let primary = Self.blue

  /// Secondary color (default: gray)
  public static let secondary = Self.brightBlack

  /// Accent color (default: cyan)
  public static let accent = Self.cyan

  /// Warning color
  public static let warning = Self.yellow

  /// Error color
  public static let error = Self.red

  /// Success color
  public static let success = Self.green

  // MARK: - Palette-Aware Semantic Colors

  /// Namespace for palette-aware semantic colors.
  ///
  /// These colors are resolved at render time against the current ``Palette``
  /// via ``resolve(with:)``. Use them in view `body` properties where no
  /// ``RenderContext`` is available:
  ///
  /// ```swift
  /// Text("Hello").foregroundStyle(.palette.accent)
  /// ```
  public enum Semantic {
    // Background colors
    public static let background = Color(value: .semantic(.background))
    public static let statusBarBackground = Color(value: .semantic(.statusBarBackground))
    public static let appHeaderBackground = Color(value: .semantic(.appHeaderBackground))
    public static let overlayBackground = Color(value: .semantic(.overlayBackground))

    // Foreground colors
    public static let foreground = Color(value: .semantic(.foreground))
    public static let foregroundSecondary = Color(value: .semantic(.foregroundSecondary))
    public static let foregroundTertiary = Color(value: .semantic(.foregroundTertiary))
    public static let foregroundQuaternary = Color(value: .semantic(.foregroundQuaternary))

    /// Accent colors
    public static let accent = Color(value: .semantic(.accent))

    // Status colors
    public static let success = Color(value: .semantic(.success))
    public static let warning = Color(value: .semantic(.warning))
    public static let error = Color(value: .semantic(.error))
    public static let info = Color(value: .semantic(.info))

    /// UI element colors
    public static let border = Color(value: .semantic(.border))
  }

  /// Access palette-aware semantic colors.
  ///
  /// Colors returned by this namespace are not resolved until render time,
  /// when the current ``Palette`` is available via ``RenderContext``.
  ///
  /// ```swift
  /// Text("Hello").foregroundStyle(.palette.accent)
  /// ```
  public static var palette: Semantic.Type {
    Semantic.self
  }

  /// The RGB components of this color.
  ///
  /// Converts any color type to its RGB representation:
  /// - `.rgb` — returned directly
  /// - `.standard` / `.bright` — mapped to xterm standard RGB values
  /// - `.palette256` — mapped to xterm 256-color palette RGB values
  /// - `.semantic` — returns nil (must be resolved first via ``resolve(with:)``)
  public var rgbComponents: (red: UInt8, green: UInt8, blue: UInt8)? {
    switch value {
    case let .rgb(red, green, blue):
      (red, green, blue)
    case let .standard(ansi):
      ansi.rgbValues
    case let .bright(ansi):
      ansi.brightRGBValues
    case let .palette256(index):
      Self.palette256ToRGB(index)
    case .semantic:
      nil
    }
  }
}

extension Color {
  /// Converts a 256-color palette index to RGB values.
  ///
  /// - Indices 0–7: standard ANSI colors
  /// - Indices 8–15: bright ANSI colors
  /// - Indices 16–231: 6×6×6 color cube
  /// - Indices 232–255: grayscale ramp
  fileprivate static func palette256ToRGB(_ index: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
    switch index {
    case 0 ... 7:
      guard let ansi = ANSIColor(rawValue: index) else { return (0, 0, 0) }
      return ansi.rgbValues
    case 8 ... 15:
      guard let ansi = ANSIColor(rawValue: index - 8) else { return (0, 0, 0) }
      return ansi.brightRGBValues
    case 16 ... 231:
      // 6×6×6 color cube: index = 16 + 36*r + 6*g + b (each 0–5)
      let cubeIndex = index - 16
      let cubeRed = cubeIndex / 36
      let cubeGreen = (cubeIndex % 36) / 6
      let cubeBlue = cubeIndex % 6
      let channelMap: [UInt8] = [0, 95, 135, 175, 215, 255]
      return (channelMap[Int(cubeRed)], channelMap[Int(cubeGreen)], channelMap[Int(cubeBlue)])
    default:
      // Grayscale ramp: 232–255 → 8, 18, 28, ..., 238
      let gray = UInt8(8 + Int(index - 232) * 10)
      return (gray, gray, gray)
    }
  }
}
