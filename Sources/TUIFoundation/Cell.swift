public struct GraphemeID: RawRepresentable, Sendable, Hashable, Comparable {
    public static let maximumRawValue: UInt32 = 0x00ff_ffff
    public static let space = GraphemeID(rawValue: 0)

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        precondition(rawValue <= Self.maximumRawValue, "GraphemeID exceeds its packed representation.")
        self.rawValue = rawValue
    }

    public static func < (lhs: GraphemeID, rhs: GraphemeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct StyleID: RawRepresentable, Sendable, Hashable, Comparable {
    public static let maximumRawValue: UInt32 = 0x00ff_ffff
    public static let `default` = StyleID(rawValue: 0)

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        precondition(rawValue <= Self.maximumRawValue, "StyleID exceeds its packed representation.")
        self.rawValue = rawValue
    }

    public static func < (lhs: StyleID, rhs: StyleID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct CellFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let empty = CellFlags(rawValue: 1 << 0)
    public static let continuation = CellFlags(rawValue: 1 << 1)
    public static let transparent = CellFlags(rawValue: 1 << 2)
    public static let explicitBlank = CellFlags(rawValue: 1 << 3)
}

public struct PackedCell: RawRepresentable, Sendable, Hashable {
    private static let identifierMask: UInt64 = 0x00ff_ffff
    private static let styleShift: UInt64 = 24
    private static let widthShift: UInt64 = 48
    private static let flagsShift: UInt64 = 50

    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(graphemeID: GraphemeID, styleID: StyleID, displayWidth: UInt8, flags: CellFlags = []) {
        precondition(displayWidth <= 2, "A packed cell width must be 0, 1, or 2.")
        rawValue =
            UInt64(graphemeID.rawValue)
            | (UInt64(styleID.rawValue) << Self.styleShift)
            | (UInt64(displayWidth) << Self.widthShift)
            | (UInt64(flags.rawValue) << Self.flagsShift)
    }

    public var graphemeID: GraphemeID {
        GraphemeID(rawValue: UInt32(rawValue & Self.identifierMask))
    }

    public var styleID: StyleID {
        StyleID(rawValue: UInt32((rawValue >> Self.styleShift) & Self.identifierMask))
    }

    public var displayWidth: UInt8 {
        UInt8((rawValue >> Self.widthShift) & 0b11)
    }

    public var flags: CellFlags {
        CellFlags(rawValue: UInt8((rawValue >> Self.flagsShift) & 0xff))
    }

    public var isContinuation: Bool { flags.contains(.continuation) }
    public var isTransparent: Bool { flags.contains(.transparent) }

    public static func blank(styleID: StyleID = .default) -> PackedCell {
        PackedCell(graphemeID: .space, styleID: styleID, displayWidth: 1, flags: [.empty, .explicitBlank])
    }

    public static let transparent = PackedCell(
        graphemeID: .space,
        styleID: .default,
        displayWidth: 1,
        flags: [.empty, .transparent]
    )

    public static func continuation(graphemeID: GraphemeID, styleID: StyleID) -> PackedCell {
        PackedCell(graphemeID: graphemeID, styleID: styleID, displayWidth: 0, flags: .continuation)
    }
}

public struct TextAttributes: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let bold = TextAttributes(rawValue: 1 << 0)
    public static let dim = TextAttributes(rawValue: 1 << 1)
    public static let italic = TextAttributes(rawValue: 1 << 2)
    public static let underline = TextAttributes(rawValue: 1 << 3)
    public static let blinking = TextAttributes(rawValue: 1 << 4)
    public static let inverse = TextAttributes(rawValue: 1 << 5)
    public static let strikethrough = TextAttributes(rawValue: 1 << 6)
}

public struct CellStyle: Sendable, Hashable {
    public var foreground: Color?
    public var background: Color?
    public var attributes: TextAttributes

    public init(foreground: Color? = nil, background: Color? = nil, attributes: TextAttributes = []) {
        self.foreground = foreground
        self.background = background
        self.attributes = attributes
    }

    public static let `default` = CellStyle()
}
