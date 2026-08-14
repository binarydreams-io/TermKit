/// A terminal color mode for ANSI output.
public enum ANSIColorMode: Sendable, Hashable {
    /// A 24-bit RGB color mode.
    case trueColor
    /// A 256-color indexed mode.
    case indexed256
    /// A 16-color ANSI mode.
    case ansi16
    /// A mode that emits no color control sequences.
    case monochrome
}

/// An error that occurs while encoding semantic operations as ANSI output.
public enum ANSIEncoderError: Error, Sendable, Equatable {
    /// A cursor point has a negative coordinate.
    case invalidCursorPoint(CellPoint)
    /// The grapheme interner does not contain an identifier.
    case unknownGrapheme(GraphemeID)
    /// The style interner does not contain an identifier.
    case unknownStyle(StyleID)
    /// A grapheme contains a terminal control scalar.
    case unsafeGrapheme(GraphemeID)
    /// A semantic color cannot resolve to a concrete color.
    case colorResolution(ColorResolutionError)
}

/// A stateful encoder that converts semantic operations to ANSI bytes.
public struct ANSIEncoder: Sendable {
    /// The color mode for encoded styles.
    public var colorMode: ANSIColorMode
    /// The encoder's last known cursor position.
    public private(set) var cursor: CellPoint?
    /// The encoder's last known style identifier.
    public private(set) var activeStyleID: StyleID?

    /// Creates an encoder for a terminal color mode.
    public init(colorMode: ANSIColorMode = .trueColor) {
        self.colorMode = colorMode
        cursor = nil
        activeStyleID = nil
    }

    /// Clears the encoder's cached cursor and style state.
    public mutating func invalidateState() {
        cursor = nil
        activeStyleID = nil
    }

    /// Encodes semantic operations as ANSI bytes and updates the cached state.
    public mutating func encode<S: Sequence>(
        _ operations: S,
        graphemes: GraphemeInterner,
        styles: StyleInterner,
        palette: SemanticPalette = SemanticPalette(),
        synchronizedOutput: Bool = false
    ) throws -> [UInt8] where S.Element == SemanticOperation {
        let operations = Array(operations)
        guard operations.isEmpty == false else { return [] }
        var copy = self
        let bytes = try copy.encodeInPlace(
            operations,
            graphemes: graphemes,
            styles: styles,
            palette: palette,
            synchronizedOutput: synchronizedOutput
        )
        self = copy
        return bytes
    }

    private mutating func encodeInPlace(
        _ operations: [SemanticOperation],
        graphemes: GraphemeInterner,
        styles: StyleInterner,
        palette: SemanticPalette,
        synchronizedOutput: Bool
    ) throws -> [UInt8] {
        var output = synchronizedOutput ? Array("\u{1b}[?2026h".utf8) : []
        for operation in operations {
            switch operation {
            case .moveCursor(let point):
                guard point.x >= 0, point.y >= 0 else {
                    throw ANSIEncoderError.invalidCursorPoint(point)
                }
                appendCursorMove(to: point, output: &output)
            case .setStyle(let identifier):
                guard activeStyleID != identifier else { continue }
                guard let style = styles.value(for: identifier) else {
                    throw ANSIEncoderError.unknownStyle(identifier)
                }
                do {
                    output.append(contentsOf: try sgr(for: style, palette: palette).utf8)
                } catch let error as ColorResolutionError {
                    throw ANSIEncoderError.colorResolution(error)
                }
                activeStyleID = identifier
            case .write(let identifier, let displayWidth, _):
                guard let grapheme = graphemes.value(for: identifier) else {
                    throw ANSIEncoderError.unknownGrapheme(identifier)
                }
                guard Self.isSafeForTerminal(grapheme) else {
                    throw ANSIEncoderError.unsafeGrapheme(identifier)
                }
                output.append(contentsOf: grapheme.utf8)
                if let cursor {
                    self.cursor = cursor.offsetBy(dx: Int(displayWidth))
                }
            }
        }
        if synchronizedOutput {
            output.append(contentsOf: "\u{1b}[?2026l".utf8)
        }
        return output
    }

    private mutating func appendCursorMove(to point: CellPoint, output: inout [UInt8]) {
        guard cursor != point else { return }
        let absolute = "\u{1b}[\(point.y + 1);\(point.x + 1)H"
        var selected = absolute
        if let cursor, cursor.y == point.y {
            let delta = point.x - cursor.x
            if delta != 0 {
                let relative = "\u{1b}[\(Swift.abs(delta))\(delta > 0 ? "C" : "D")"
                if relative.utf8.count < absolute.utf8.count { selected = relative }
            }
        }
        output.append(contentsOf: selected.utf8)
        cursor = point
    }

    private func sgr(for style: CellStyle, palette: SemanticPalette) throws -> String {
        var codes = ["0"]
        let attributes = style.attributes
        if attributes.contains(.bold) { codes.append("1") }
        if attributes.contains(.dim) { codes.append("2") }
        if attributes.contains(.italic) { codes.append("3") }
        if attributes.contains(.underline) { codes.append("4") }
        if attributes.contains(.blinking) { codes.append("5") }
        if attributes.contains(.inverse) { codes.append("7") }
        if attributes.contains(.strikethrough) { codes.append("9") }
        if colorMode != .monochrome, let foreground = style.foreground {
            codes.append(try colorCode(for: palette.resolve(foreground), foreground: true))
        }
        if colorMode != .monochrome, let background = style.background {
            codes.append(try colorCode(for: palette.resolve(background), foreground: false))
        }
        return "\u{1b}[\(codes.joined(separator: ";"))m"
    }

    private func colorCode(for color: RGBA, foreground: Bool) -> String {
        switch colorMode {
        case .trueColor:
            return "\(foreground ? 38 : 48);2;\(color.redByte);\(color.greenByte);\(color.blueByte)"
        case .indexed256:
            return "\(foreground ? 38 : 48);5;\(Self.nearest256(to: color))"
        case .ansi16:
            let index = Self.nearest16(to: color)
            let base: Int
            if index < 8 {
                base = (foreground ? 30 : 40) + index
            } else {
                base = (foreground ? 90 : 100) + index - 8
            }
            return String(base)
        case .monochrome:
            return ""
        }
    }

    private static func isSafeForTerminal(_ grapheme: String) -> Bool {
        grapheme.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value >= 0x20 && value != 0x7f && (value < 0x80 || value > 0x9f)
        }
    }

    private static func nearest256(to color: RGBA) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for index in 16..<256 {
            let candidate = paletteColor(index)
            let distance = squaredDistance(color, candidate)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func nearest16(to color: RGBA) -> Int {
        (0..<16).min { squaredDistance(color, paletteColor($0)) < squaredDistance(color, paletteColor($1)) } ?? 0
    }

    private static func squaredDistance(_ lhs: RGBA, _ rhs: RGBA) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return red * red + green * green + blue * blue
    }

    private static func paletteColor(_ index: Int) -> RGBA {
        let system: [(UInt8, UInt8, UInt8)] = [
            (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
            (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
            (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
            (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
        ]
        if index < 16 {
            let value = system[index]
            return RGBA(redByte: value.0, greenByte: value.1, blueByte: value.2)
        }
        if index < 232 {
            let value = index - 16
            let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
            return RGBA(
                redByte: levels[value / 36],
                greenByte: levels[(value / 6) % 6],
                blueByte: levels[value % 6]
            )
        }
        let level = UInt8(8 + (index - 232) * 10)
        return RGBA(redByte: level, greenByte: level, blueByte: level)
    }
}
