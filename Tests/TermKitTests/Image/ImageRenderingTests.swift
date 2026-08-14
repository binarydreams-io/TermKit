import Testing

@testable import TermKit

@MainActor
struct ImageRenderingTests {
    @Test("Two vertical pixels render as one colored upper block")
    func halfBlock() throws {
        let raster = try RasterImage(
            width: 1,
            height: 2,
            pixels: [
                RGBA8(red: 255, green: 0, blue: 0),
                RGBA8(red: 0, green: 0, blue: 255),
            ]
        )
        var resources = ControlRenderResources(colorCapability: .trueColor)
        var surface = Surface(size: CellSize(width: 1, height: 1))
        let view = Image(raster, label: "Red over blue", background: RGBA8(red: 0, green: 0, blue: 0))

        let semantics = try view.paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )
        let cell = surface[.zero]
        let style = try #require(resources.styles.value(for: cell.styleID))

        #expect(resources.graphemes.value(for: cell.graphemeID) == "▀")
        #expect(style.foreground == .rgba(RGBA(redByte: 255, greenByte: 0, blueByte: 0)))
        #expect(style.background == .rgba(RGBA(redByte: 0, greenByte: 0, blueByte: 255)))
        #expect(semantics.role == .image)
        #expect(semantics.label == "Red over blue")
    }

    @Test("Odd image height composites its missing lower pixel against the background")
    func oddHeight() throws {
        let raster = try RasterImage(width: 1, height: 1, pixels: [RGBA8(red: 255, green: 255, blue: 255)])
        var resources = ControlRenderResources(colorCapability: .trueColor)
        var surface = Surface(size: CellSize(width: 1, height: 1))
        let background = RGBA8(red: 8, green: 16, blue: 24)

        _ = try Image(raster, label: "Pixel", background: background).paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )
        let style = try #require(resources.styles.value(for: surface[.zero].styleID))
        #expect(style.background == .rgba(RGBA(redByte: 8, greenByte: 16, blueByte: 24)))
    }

    @Test("Transparent pixels composite against the explicit background")
    func alphaComposition() throws {
        let raster = try RasterImage(
            width: 1,
            height: 2,
            pixels: [
                RGBA8(red: 255, green: 0, blue: 0, alpha: 128),
                RGBA8(red: 0, green: 0, blue: 255, alpha: 64),
            ]
        )
        var resources = ControlRenderResources(colorCapability: .trueColor)
        var surface = Surface(size: CellSize(width: 1, height: 1))

        _ = try Image(raster, label: "Alpha", background: RGBA8(red: 0, green: 255, blue: 0)).paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )
        let style = try #require(resources.styles.value(for: surface[.zero].styleID))
        #expect(style.foreground == .rgba(RGBA(redByte: 128, greenByte: 127, blueByte: 0)))
        #expect(style.background == .rgba(RGBA(redByte: 0, greenByte: 191, blueByte: 64)))
    }

    @Test("Monochrome rendering uses block glyphs and default styles")
    func monochrome() throws {
        let raster = try RasterImage(
            width: 2,
            height: 2,
            pixels: [
                RGBA8(red: 255, green: 255, blue: 255), RGBA8(red: 0, green: 0, blue: 0),
                RGBA8(red: 0, green: 0, blue: 0), RGBA8(red: 255, green: 255, blue: 255),
            ]
        )
        var resources = ControlRenderResources(colorCapability: .monochrome)
        var surface = Surface(size: CellSize(width: 2, height: 1))

        _ = try Image(raster, label: "Pattern", background: RGBA8(red: 0, green: 0, blue: 0)).paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )

        #expect(resources.graphemes.value(for: surface[CellPoint(x: 0, y: 0)].graphemeID) == "▀")
        #expect(resources.graphemes.value(for: surface[CellPoint(x: 1, y: 0)].graphemeID) == "▄")
        #expect(surface.cells.allSatisfy { $0.styleID == .default })
    }

    @Test("Fit and fill use centered deterministic sampling")
    func contentModes() throws {
        let raster = try RasterImage(
            width: 4,
            height: 2,
            pixels: [
                RGBA8(red: 255, green: 0, blue: 0), RGBA8(red: 0, green: 255, blue: 0),
                RGBA8(red: 0, green: 0, blue: 255), RGBA8(red: 255, green: 255, blue: 0),
                RGBA8(red: 255, green: 0, blue: 0), RGBA8(red: 0, green: 255, blue: 0),
                RGBA8(red: 0, green: 0, blue: 255), RGBA8(red: 255, green: 255, blue: 0),
            ]
        )
        let fit = try paint(raster, mode: .fit, size: CellSize(width: 2, height: 2))
        let fill = try paint(raster, mode: .fill, size: CellSize(width: 2, height: 2))

        #expect(fit != fill)
        #expect(try fit == paint(raster, mode: .fit, size: CellSize(width: 2, height: 2)))
        #expect(try fill == paint(raster, mode: .fill, size: CellSize(width: 2, height: 2)))
        #expect(fit.count == 4)
        #expect(fill.count == 4)
    }

    @Test(
        "Image colors use the terminal encoder mode",
        arguments: [
            (TerminalColorCapability.trueColor, ANSIColorMode.trueColor, "38;2;255;0;0"),
            (.ansi256, .indexed256, "38;5;"),
            (.ansi16, .ansi16, "[0;91;44m"),
        ]
    )
    func colorModes(
        capability: TerminalColorCapability,
        mode: ANSIColorMode,
        expected: String
    ) throws {
        let raster = try RasterImage(
            width: 1,
            height: 2,
            pixels: [
                RGBA8(red: 255, green: 0, blue: 0),
                RGBA8(red: 0, green: 0, blue: 255),
            ]
        )
        var resources = ControlRenderResources(colorCapability: capability)
        var surface = Surface(size: CellSize(width: 1, height: 1))
        _ = try Image(raster, label: "Color", background: RGBA8(red: 0, green: 0, blue: 0)).paint(
            into: &surface,
            context: PaintContext(clip: surface.bounds),
            resources: &resources
        )
        var encoder = ANSIEncoder(colorMode: mode)
        let cell = surface[.zero]
        let output = try encoder.encode(
            [
                .setStyle(cell.styleID),
                .write(graphemeID: cell.graphemeID, displayWidth: cell.displayWidth, flags: cell.flags),
            ],
            graphemes: resources.graphemes,
            styles: resources.styles
        )

        #expect(String(decoding: output, as: UTF8.self).contains(expected))
    }

    private func paint(_ raster: RasterImage, mode: ImageContentMode, size: CellSize) throws -> [PackedCell] {
        var resources = ControlRenderResources(colorCapability: .trueColor)
        var surface = Surface(size: size)
        _ = try Image(
            raster,
            label: "Mode",
            contentMode: mode,
            background: RGBA8(red: 0, green: 0, blue: 0)
        ).paint(into: &surface, context: PaintContext(clip: surface.bounds), resources: &resources)
        return surface.cells
    }
}
