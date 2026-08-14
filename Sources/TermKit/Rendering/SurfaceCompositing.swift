#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The foreground or background role of a cell color.
public enum CellColorRole: Sendable, Hashable {
    /// The cell's foreground color.
    case foreground
    /// The cell's background color.
    case background
}

/// An error that occurs while compositing surfaces.
public enum SurfaceCompositingError: Error, Sendable, Equatable {
    /// The grapheme interner does not contain an identifier.
    case unknownGrapheme(GraphemeID)
    /// The style interner does not contain an identifier.
    case unknownStyle(StyleID)
}

extension Surface {
    /// Composites a source surface over this surface with opacity and resolved colors.
    public mutating func composite(
        _ source: Surface,
        at origin: CellPoint = .zero,
        clip: CellRect? = nil,
        opacity: Double,
        graphemes: GraphemeInterner,
        styles: inout StyleInterner,
        resolveColor: (_ color: Color?, _ role: CellColorRole) throws -> RGBA
    ) throws {
        let opacity = Swift.min(1, Swift.max(0, opacity))
        guard opacity > 0 else { return }

        try validateWideCells()
        try source.validateWideCells()
        guard let destinationClip = bounds.intersection(clip ?? bounds) else { return }

        var result = self
        var resultStyles = styles
        for sourceY in source.bounds.minY..<source.bounds.maxY {
            var sourceX = source.bounds.minX
            while sourceX < source.bounds.maxX {
                let sourcePoint = CellPoint(x: sourceX, y: sourceY)
                let sourceCell = source[sourcePoint]
                if sourceCell.isContinuation {
                    sourceX += 1
                    continue
                }

                let width = Int(sourceCell.displayWidth)
                let destinationPoint = sourcePoint.offsetBy(dx: origin.x, dy: origin.y)
                let sourceAtom = CellRect(x: destinationPoint.x, y: destinationPoint.y, width: width, height: 1)
                guard sourceCell.isTransparent == false,
                    destinationClip.contains(sourceAtom),
                    bounds.contains(sourceAtom),
                    result.replacementAtom(at: destinationPoint, width: width).map(destinationClip.contains) == true
                else {
                    sourceX += width
                    continue
                }

                guard graphemes.value(for: sourceCell.graphemeID) != nil else {
                    throw SurfaceCompositingError.unknownGrapheme(sourceCell.graphemeID)
                }
                guard let sourceStyle = styles.value(for: sourceCell.styleID) else {
                    throw SurfaceCompositingError.unknownStyle(sourceCell.styleID)
                }
                let destinationCell = result[destinationPoint]
                guard let destinationStyle = resultStyles.value(for: destinationCell.styleID) else {
                    throw SurfaceCompositingError.unknownStyle(destinationCell.styleID)
                }

                let destinationIsClear = destinationCell.isTransparent
                let foreground = try Self.compositeColor(
                    sourceStyle.foreground,
                    over: destinationIsClear ? .rgba(.clear) : destinationStyle.foreground,
                    role: .foreground,
                    opacity: opacity,
                    resolveColor: resolveColor
                )
                let background = try Self.compositeColor(
                    sourceStyle.background,
                    over: destinationIsClear ? .rgba(.clear) : destinationStyle.background,
                    role: .background,
                    opacity: opacity,
                    resolveColor: resolveColor
                )
                let styleID = try resultStyles.intern(
                    CellStyle(
                        foreground: .rgba(foreground),
                        background: .rgba(background),
                        attributes: sourceStyle.attributes
                    )
                )
                _ = try result.write(
                    graphemeID: sourceCell.graphemeID,
                    at: destinationPoint,
                    styleID: styleID,
                    displayWidth: sourceCell.displayWidth,
                    flags: sourceCell.flags,
                    clip: destinationClip
                )
                sourceX += width
            }
        }

        self = result
        styles = resultStyles
    }

    private func replacementAtom(at point: CellPoint, width: Int) -> CellRect? {
        var minX = point.x
        var maxX = point.x + width
        for x in point.x..<point.x + width {
            let cellPoint = CellPoint(x: x, y: point.y)
            guard bounds.contains(cellPoint) else { return nil }
            let cell = self[cellPoint]
            if cell.isContinuation {
                minX = Swift.min(minX, x - 1)
            } else if cell.displayWidth == 2 {
                maxX = Swift.max(maxX, x + 2)
            }
        }
        return CellRect(x: minX, y: point.y, width: maxX - minX, height: 1)
    }

    private static func compositeColor(
        _ source: Color?,
        over destination: Color?,
        role: CellColorRole,
        opacity: Double,
        resolveColor: (Color?, CellColorRole) throws -> RGBA
    ) throws -> RGBA {
        let sourceRGBA = try resolve(source, role: role, using: resolveColor)
        let destinationRGBA = try resolve(destination, role: role, using: resolveColor)
        let linearSource = linearRGBA(sourceRGBA).applyingOpacity(opacity)
        let linearDestination = linearRGBA(destinationRGBA)
        return sRGBRGBA(linearSource.composited(over: linearDestination))
    }

    private static func resolve(
        _ color: Color?,
        role: CellColorRole,
        using resolveColor: (Color?, CellColorRole) throws -> RGBA
    ) throws -> RGBA {
        if case .rgba(let rgba)? = color { return rgba }
        return try resolveColor(color, role)
    }

    private static func linearRGBA(_ color: RGBA) -> RGBA {
        RGBA(
            red: sRGBToLinear(color.red),
            green: sRGBToLinear(color.green),
            blue: sRGBToLinear(color.blue),
            alpha: color.alpha
        )
    }

    private static func sRGBRGBA(_ color: RGBA) -> RGBA {
        RGBA(
            red: linearToSRGB(color.red),
            green: linearToSRGB(color.green),
            blue: linearToSRGB(color.blue),
            alpha: color.alpha
        )
    }

    private static func sRGBToLinear(_ value: Double) -> Double {
        if value <= 0 { return 0 }
        if value >= 1 { return 1 }
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Double) -> Double {
        if value <= 0 { return 0 }
        if value >= 1 { return 1 }
        return value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}
