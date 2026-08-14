import Foundation

/// The scaling behavior for a raster image in a terminal frame.
public enum ImageContentMode: Sendable, Hashable {
    /// Shows the complete image and adds centered letterboxing when needed.
    case fit
    /// Fills the frame and crops the image around its center when needed.
    case fill
}

/// A terminal view that renders a raster image with half-block cells.
public struct Image: View, SemanticRenderable, Sendable, Hashable {
    /// The semantic identifier.
    public var id: SemanticID
    /// The raster image.
    public var image: RasterImage
    /// The accessibility label.
    public var label: String
    /// The scaling behavior.
    public var contentMode: ImageContentMode
    /// The explicit color used behind transparent pixels and letterboxing.
    public var background: RGBA8
    /// The physical cell height divided by its width.
    public var cellAspectRatio: Double

    /// Creates a terminal image view.
    public init(
        _ image: RasterImage,
        id: SemanticID = "image",
        label: String,
        contentMode: ImageContentMode = .fit,
        background: RGBA8,
        cellAspectRatio: Double = 2
    ) {
        precondition(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        precondition(cellAspectRatio.isFinite && cellAspectRatio > 0)
        self.id = id
        self.image = image
        self.label = label
        self.contentMode = contentMode
        self.background = background
        self.cellAspectRatio = cellAspectRatio
    }

    /// Returns the image's intrinsic terminal size constrained by the proposal.
    public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let natural = CellSize(width: image.width, height: (image.height + 1) / 2)
        return CellSize(
            width: min(natural.width, proposal.width ?? natural.width),
            height: min(natural.height, proposal.height ?? natural.height)
        )
    }

    /// Paints deterministic image samples and returns image semantics.
    public func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let frame = CellRect(origin: context.origin, size: context.frameSize)
        let visible = frame.intersection(context.clip).flatMap { $0.intersection(surface.bounds) }
        if let visible {
            let glyphs = try Glyphs(resources: &resources)
            for y in visible.minY..<visible.maxY {
                for x in visible.minX..<visible.maxX {
                    let localX = x - frame.minX
                    let localY = y - frame.minY
                    let upper = sample(targetX: localX, targetPixelY: localY * 2, frameSize: frame.size)
                    let lower = sample(targetX: localX, targetPixelY: localY * 2 + 1, frameSize: frame.size)
                    let output = try renderedCell(upper: upper, lower: lower, resources: &resources, glyphs: glyphs)
                    _ = try surface.write(
                        graphemeID: output.grapheme,
                        at: CellPoint(x: x, y: y),
                        styleID: output.style,
                        clip: visible
                    )
                }
            }
        }
        return SemanticNode(id: id, role: .image, label: label, frame: frame)
    }

    /// The retained view descriptor.
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, dirtyOnUpdate: .layout)]
    }

    private func renderedCell(
        upper: RGBA8,
        lower: RGBA8,
        resources: inout ControlRenderResources,
        glyphs: Glyphs
    ) throws -> (grapheme: GraphemeID, style: StyleID) {
        guard resources.colorCapability != .monochrome else {
            let upperLight = luminance(upper) >= 0.5
            let lowerLight = luminance(lower) >= 0.5
            let grapheme: GraphemeID =
                switch (upperLight, lowerLight) {
                case (false, false): glyphs.space
                case (true, false): glyphs.upper
                case (false, true): glyphs.lower
                case (true, true): glyphs.full
                }
            return (grapheme, .default)
        }
        let style = CellStyle(
            foreground: .rgba(upper.rgba),
            background: .rgba(lower.rgba)
        )
        return (glyphs.upper, try resources.internPaintStyle(style))
    }

    private func sample(targetX: Int, targetPixelY: Int, frameSize: CellSize) -> RGBA8 {
        guard frameSize.width > 0, frameSize.height > 0 else { return background }
        let physicalHeight = Double(frameSize.height) * cellAspectRatio
        let scale =
            switch contentMode {
            case .fit:
                min(Double(frameSize.width) / Double(image.width), physicalHeight / Double(image.height))
            case .fill:
                max(Double(frameSize.width) / Double(image.width), physicalHeight / Double(image.height))
            }
        let drawnWidth = Double(image.width) * scale
        let drawnHeight = Double(image.height) * scale
        let physicalX = Double(targetX) + 0.5
        let physicalY = (Double(targetPixelY) + 0.5) * cellAspectRatio / 2
        let sourceX = (physicalX - (Double(frameSize.width) - drawnWidth) / 2) / scale
        let sourceY = (physicalY - (physicalHeight - drawnHeight) / 2) / scale
        guard sourceX >= 0, sourceY >= 0, sourceX < Double(image.width), sourceY < Double(image.height) else {
            return background
        }
        return composite(image[Int(sourceX), Int(sourceY)], over: background)
    }

    private func composite(_ foreground: RGBA8, over background: RGBA8) -> RGBA8 {
        let alpha = Double(foreground.alpha) / 255
        func channel(_ foreground: UInt8, _ background: UInt8) -> UInt8 {
            UInt8((Double(foreground) * alpha + Double(background) * (1 - alpha)).rounded())
        }
        return RGBA8(
            red: channel(foreground.red, background.red),
            green: channel(foreground.green, background.green),
            blue: channel(foreground.blue, background.blue)
        )
    }

    private func luminance(_ pixel: RGBA8) -> Double {
        (0.2126 * Double(pixel.red) + 0.7152 * Double(pixel.green) + 0.0722 * Double(pixel.blue)) / 255
    }
}

private struct Glyphs {
    let space: GraphemeID
    let upper: GraphemeID
    let lower: GraphemeID
    let full: GraphemeID

    init(resources: inout ControlRenderResources) throws {
        space = try resources.graphemes.intern(" ")
        upper = try resources.graphemes.intern("▀")
        lower = try resources.graphemes.intern("▄")
        full = try resources.graphemes.intern("█")
    }
}

extension RGBA8 {
    fileprivate var rgba: RGBA {
        RGBA(redByte: red, greenByte: green, blueByte: blue)
    }
}
