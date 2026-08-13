//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PalettePreset+Accessors.swift
//
//  Created by LAYERED.work
//  License: MIT

extension Palette where Self == SystemPalette {
  /// The default palette (green).
  public static var `default`: SystemPalette {
    SystemPalette(.green)
  }

  /// Green terminal palette (P1 phosphor).
  public static var green: SystemPalette {
    SystemPalette(.green)
  }

  /// Amber terminal palette (P3 phosphor).
  public static var amber: SystemPalette {
    SystemPalette(.amber)
  }

  /// Red terminal palette (night-vision).
  public static var red: SystemPalette {
    SystemPalette(.red)
  }

  /// Violet terminal palette (retro/sci-fi).
  public static var violet: SystemPalette {
    SystemPalette(.violet)
  }

  /// Blue VFD terminal palette.
  public static var blue: SystemPalette {
    SystemPalette(.blue)
  }

  /// White terminal palette (P4 phosphor).
  public static var white: SystemPalette {
    SystemPalette(.white)
  }
}
