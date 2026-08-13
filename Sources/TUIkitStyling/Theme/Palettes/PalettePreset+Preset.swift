//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PalettePreset+Preset.swift
//
//  Created by LAYERED.work
//  License: MIT

extension SystemPalette {
  /// Built-in palette presets inspired by classic terminal phosphors.
  ///
  /// | Preset   | Hue  | Inspiration                                |
  /// |----------|------|--------------------------------------------|
  /// | `green`  | 120° | IBM 5151, Apple II (P1 phosphor)           |
  /// | `amber`  |  40° | IBM 3278, Wyse 50 (P3 phosphor)            |
  /// | `red`    |   0° | Military/specialized, night-vision         |
  /// | `violet` | 270° | Retro computing, sci-fi terminals          |
  /// | `blue`   | 200° | Vacuum fluorescent displays (VFDs)         |
  /// | `white`  | 225° | DEC VT100/VT220 (P4 phosphor)              |
  public enum Preset: String, CaseIterable, Sendable {
    case green
    case amber
    case red
    case violet
    case blue
    case white
  }
}
