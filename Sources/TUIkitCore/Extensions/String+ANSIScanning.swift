//  🖥️ TUIKit — Terminal UI Kit for Swift
//  String+ANSIScanning.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Escape Sequence Scanning

extension String {
  /// The index just past the escape sequence that starts at `start`.
  ///
  /// Every width and truncation helper walks a line the same way: count the
  /// visible cells, and step over the escape sequences between them. This is
  /// the one scanner they share, so a sequence a terminal swallows never counts
  /// as a cell in one helper and as text in another.
  ///
  /// The scanner follows the CSI grammar: `ESC [`, the parameter bytes `0x30`
  /// to `0x3F` (the digits and `;`, and the private markers `<`, `=`, `>`, `?`),
  /// the intermediate bytes `0x20` to `0x2F`, then one final byte `0x40` to
  /// `0x7E`. A sequence the string ends before its final byte reaches the end
  /// index, and an escape that no `[` follows steps over the escape alone,
  /// which leaves the byte behind it visible.
  ///
  /// - Parameter start: The index of the escape character.
  /// - Returns: The index of the first character after the sequence.
  func indexAfterEscapeSequence(startingAt start: Index) -> Index {
    var index = self.index(after: start)
    guard index < endIndex, self[index] == "[" else { return index }
    index = self.index(after: index)
    while index < endIndex, self[index].isCSIParameterByte {
      index = self.index(after: index)
    }
    while index < endIndex, self[index].isCSIIntermediateByte {
      index = self.index(after: index)
    }
    if index < endIndex, self[index].isCSIFinalByte {
      index = self.index(after: index)
    }
    return index
  }
}

// MARK: - CSI Byte Classes

extension Character {
  /// Whether this is a CSI parameter byte: `0` to `9`, `:`, `;`, and the
  /// private markers `<`, `=`, `>`, `?`.
  fileprivate var isCSIParameterByte: Bool {
    isASCIIByte(in: 0x30 ... 0x3F)
  }

  /// Whether this is a CSI intermediate byte: the space through `/`.
  fileprivate var isCSIIntermediateByte: Bool {
    isASCIIByte(in: 0x20 ... 0x2F)
  }

  /// Whether this is a CSI final byte: `@` through `~`.
  fileprivate var isCSIFinalByte: Bool {
    isASCIIByte(in: 0x40 ... 0x7E)
  }

  /// Whether this character is one scalar inside the given code-point range.
  private func isASCIIByte(in range: ClosedRange<UInt32>) -> Bool {
    let scalars = unicodeScalars
    guard scalars.count == 1, let scalar = scalars.first else { return false }
    return range.contains(scalar.value)
  }
}
