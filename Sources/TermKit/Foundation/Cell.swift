/// A compact identifier for an interned grapheme.
public struct GraphemeID: RawRepresentable, Sendable, Hashable, Comparable {
  /// The largest value that fits in a packed cell.
  public static let maximumRawValue: UInt32 = 0x00FFFFFF
  /// The identifier reserved for a space.
  public static let space = GraphemeID(rawValue: 0)

  /// The identifier's unsigned value.
  public var rawValue: UInt32

  /// Creates a grapheme identifier from a packed value.
  public init(rawValue: UInt32) {
    precondition(rawValue <= Self.maximumRawValue, "GraphemeID exceeds its packed representation.")
    self.rawValue = rawValue
  }

  /// Returns whether the left identifier precedes the right identifier.
  public static func < (lhs: GraphemeID, rhs: GraphemeID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// A compact identifier for an interned cell style.
public struct StyleID: RawRepresentable, Sendable, Hashable, Comparable {
  /// The largest value that fits in a packed cell.
  public static let maximumRawValue: UInt32 = 0x00FFFFFF
  /// The identifier reserved for the default style.
  public static let `default` = StyleID(rawValue: 0)

  /// The identifier's unsigned value.
  public var rawValue: UInt32

  /// Creates a style identifier from a packed value.
  public init(rawValue: UInt32) {
    precondition(rawValue <= Self.maximumRawValue, "StyleID exceeds its packed representation.")
    self.rawValue = rawValue
  }

  /// Returns whether the left identifier precedes the right identifier.
  public static func < (lhs: StyleID, rhs: StyleID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Flags that describe a packed cell's rendering role.
public struct CellFlags: OptionSet, Sendable, Hashable {
  /// The flags' bit representation.
  public let rawValue: UInt8

  /// Creates flags from a bit representation.
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// The cell contains no visible grapheme.
  public static let empty = CellFlags(rawValue: 1 << 0)
  /// The cell continues a two-cell grapheme.
  public static let continuation = CellFlags(rawValue: 1 << 1)
  /// The cell does not replace content below it.
  public static let transparent = CellFlags(rawValue: 1 << 2)
  /// The cell represents an explicit blank.
  public static let explicitBlank = CellFlags(rawValue: 1 << 3)
}

/// A compact terminal cell representation.
public struct PackedCell: RawRepresentable, Sendable, Hashable {
  private static let identifierMask: UInt64 = 0x00FFFFFF
  private static let styleShift: UInt64 = 24
  private static let widthShift: UInt64 = 48
  private static let flagsShift: UInt64 = 50

  /// The cell's packed bit representation.
  public var rawValue: UInt64

  /// Creates a cell from a packed bit representation.
  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  /// Creates a packed cell from its components.
  public init(graphemeID: GraphemeID, styleID: StyleID, displayWidth: UInt8, flags: CellFlags = []) {
    precondition(displayWidth <= 2, "A packed cell width must be 0, 1, or 2.")
    self.rawValue =
      UInt64(graphemeID.rawValue)
        | (UInt64(styleID.rawValue) << Self.styleShift)
        | (UInt64(displayWidth) << Self.widthShift)
        | (UInt64(flags.rawValue) << Self.flagsShift)
  }

  /// The interned grapheme identifier.
  public var graphemeID: GraphemeID {
    GraphemeID(rawValue: UInt32(rawValue & Self.identifierMask))
  }

  /// The interned style identifier.
  public var styleID: StyleID {
    StyleID(rawValue: UInt32((rawValue >> Self.styleShift) & Self.identifierMask))
  }

  /// The grapheme's terminal display width.
  public var displayWidth: UInt8 {
    UInt8((rawValue >> Self.widthShift) & 0b11)
  }

  /// The cell flags.
  public var flags: CellFlags {
    CellFlags(rawValue: UInt8((rawValue >> Self.flagsShift) & 0xFF))
  }

  /// A Boolean value that indicates whether the cell continues a wide grapheme.
  public var isContinuation: Bool {
    flags.contains(.continuation)
  }

  /// A Boolean value that indicates whether the cell preserves content below it.
  public var isTransparent: Bool {
    flags.contains(.transparent)
  }

  /// Creates an explicit blank cell with a style.
  public static func makeBlank(styleID: StyleID = .default) -> PackedCell {
    PackedCell(graphemeID: .space, styleID: styleID, displayWidth: 1, flags: [.empty, .explicitBlank])
  }

  /// A transparent single-width cell.
  public static let transparent = PackedCell(
    graphemeID: .space,
    styleID: .default,
    displayWidth: 1,
    flags: [.empty, .transparent]
  )

  /// Creates a continuation cell for a two-cell grapheme.
  public static func makeContinuation(graphemeID: GraphemeID, styleID: StyleID) -> PackedCell {
    PackedCell(graphemeID: graphemeID, styleID: styleID, displayWidth: 0, flags: .continuation)
  }
}

/// Text attributes that a terminal can apply to a cell.
public struct TextAttributes: OptionSet, Sendable, Hashable {
  /// The attributes' bit representation.
  public let rawValue: UInt16

  /// Creates attributes from a bit representation.
  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  /// Bold text.
  public static let bold = TextAttributes(rawValue: 1 << 0)
  /// Dim text.
  public static let dim = TextAttributes(rawValue: 1 << 1)
  /// Italic text.
  public static let italic = TextAttributes(rawValue: 1 << 2)
  /// Underlined text.
  public static let underline = TextAttributes(rawValue: 1 << 3)
  /// Blinking text.
  public static let blinking = TextAttributes(rawValue: 1 << 4)
  /// Text with reversed foreground and background colors.
  public static let inverse = TextAttributes(rawValue: 1 << 5)
  /// Struck-through text.
  public static let strikethrough = TextAttributes(rawValue: 1 << 6)
}

/// The colors and text attributes of a terminal cell.
public struct CellStyle: Sendable, Hashable {
  /// The optional foreground color.
  public var foreground: Color?
  /// The optional background color.
  public var background: Color?
  /// The text attributes.
  public var attributes: TextAttributes

  /// Creates a cell style.
  public init(foreground: Color? = nil, background: Color? = nil, attributes: TextAttributes = []) {
    self.foreground = foreground
    self.background = background
    self.attributes = attributes
  }

  /// A style with no explicit colors or attributes.
  public static let `default` = CellStyle()
}
