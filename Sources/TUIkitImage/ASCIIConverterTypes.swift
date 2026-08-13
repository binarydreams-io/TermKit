//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIConverterTypes.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Standard ANSI escape sequences for ASCII art colorization.
enum ANSIEscape {
  /// The escape character.
  static let escape = "\u{1B}"
  /// The Control Sequence Introducer.
  static let csi = "\(escape)["
  /// Reset all formatting.
  static let reset = "\(csi)0m"
}

// MARK: - Character Set

/// The set of characters used for ASCII art rendering.
///
/// Each set trades off between compatibility and visual quality.
public enum ASCIICharacterSet: Sendable, Equatable {
  /// Standard ASCII characters (10 levels). Works in every terminal.
  case ascii

  /// Unicode block elements (5 levels). Requires Unicode support.
  case blocks

  /// Unicode Braille patterns (2x4 pixel cells, 256 patterns). Highest resolution.
  case braille
}

// MARK: - Color Mode

/// Controls how colors are rendered in ASCII art output.
public enum ASCIIColorMode: Sendable, Equatable {
  /// 24-bit RGB using `\e[38;2;R;G;B` sequences. Best quality.
  case trueColor

  /// 256-color ANSI palette. Good terminal compatibility.
  case ansi256

  /// 24 shades of gray.
  case grayscale

  /// Black and white only. Universal compatibility.
  case mono
}

// MARK: - Dithering Mode

/// The dithering algorithm applied during color quantization.
public enum DitheringMode: Sendable, Equatable {
  /// Floyd-Steinberg error diffusion. Good for smooth gradients.
  case floydSteinberg

  /// No dithering. Fastest.
  case none
}
