import Testing

@testable import TermKit

struct SurfaceCompositingTests {
    @Test func boundedSurfaceUsesAbsoluteCoordinates() throws {
        var surface = Surface(bounds: CellRect(x: 7, y: 3, width: 2, height: 1), fill: .transparent)
        let point = CellPoint(x: 8, y: 3)

        try surface.write(graphemeID: GraphemeID(rawValue: 1), at: point)

        #expect(surface.origin == CellPoint(x: 7, y: 3))
        #expect(surface.bounds == CellRect(x: 7, y: 3, width: 2, height: 1))
        #expect(surface[point].graphemeID == GraphemeID(rawValue: 1))
    }

    @Test func nestedTransparentCompositingPreservesAlphaUntilOpaqueDestination() throws {
        var graphemes = GraphemeInterner()
        var styles = StyleInterner()
        let red = try styles.intern(CellStyle(foreground: .rgba(RGBA(red: 1, green: 0, blue: 0))))
        let white = try styles.intern(CellStyle(foreground: .rgba(.white)))
        let lowerGlyph = try graphemes.intern("r")
        let upperGlyph = try graphemes.intern("w")
        var destination = Surface(size: CellSize(width: 1, height: 1))
        var child = Surface(bounds: destination.bounds, fill: .transparent)
        var wrapper = Surface(bounds: destination.bounds, fill: .transparent)
        try destination.write(graphemeID: lowerGlyph, at: .zero, styleID: red)
        try child.write(graphemeID: upperGlyph, at: .zero, styleID: white)

        try wrapper.composite(
            child,
            opacity: 0.5,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )
        let intermediate = try #require(styles.value(for: wrapper[.zero].styleID))
        #expect(rgba(intermediate.foreground)?.alpha == 0.5)
        try destination.composite(
            wrapper,
            opacity: 1,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )

        let result = try #require(rgba(styles.value(for: destination[.zero].styleID)?.foreground))
        #expect(result.redByte == 255)
        #expect(result.greenByte == 188)
        #expect(result.blueByte == 188)
        #expect(result.alphaByte == 255)
    }

    @Test func halfOpacityBlendsWhiteOverBlackInLinearSRGB() throws {
        var graphemes = GraphemeInterner()
        var styles = StyleInterner()
        let lower = try styles.intern(CellStyle(foreground: .rgba(.black), background: .rgba(.black)))
        let upper = try styles.intern(CellStyle(foreground: .rgba(.white), background: .rgba(.white), attributes: .bold))
        let lowerGrapheme = try graphemes.intern("a")
        let upperGrapheme = try graphemes.intern("b")
        var destination = Surface(size: CellSize(width: 1, height: 1))
        var source = Surface(size: CellSize(width: 1, height: 1))
        try destination.write(graphemeID: lowerGrapheme, at: .zero, styleID: lower)
        try source.write(graphemeID: upperGrapheme, at: .zero, styleID: upper)

        try destination.composite(
            source,
            opacity: 0.5,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )

        let cell = destination[.zero]
        let style = try #require(styles.value(for: cell.styleID))
        let foreground = try #require(rgba(style.foreground))
        let background = try #require(rgba(style.background))
        #expect(cell.graphemeID == upperGrapheme)
        #expect(foreground.redByte == 188)
        #expect(foreground.greenByte == 188)
        #expect(foreground.blueByte == 188)
        #expect(background.redByte == 188)
        #expect(style.attributes == .bold)
    }

    @Test func zeroOpacityPreservesDestinationAndOneUsesSource() throws {
        var graphemes = GraphemeInterner()
        var styles = StyleInterner()
        let lowerStyle = try styles.intern(CellStyle(foreground: .rgba(.black), background: .rgba(.white)))
        let upperStyle = try styles.intern(CellStyle(foreground: .rgba(.white), background: .rgba(.black)))
        let lowerGrapheme = try graphemes.intern("a")
        let upperGrapheme = try graphemes.intern("b")
        var destination = Surface(size: CellSize(width: 1, height: 1))
        var source = Surface(size: CellSize(width: 1, height: 1))
        try destination.write(graphemeID: lowerGrapheme, at: .zero, styleID: lowerStyle)
        try source.write(graphemeID: upperGrapheme, at: .zero, styleID: upperStyle)
        let original = destination

        try destination.composite(
            source,
            opacity: 0,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: { _, _ in
                Issue.record("Opacity zero resolved a color")
                return .clear
            }
        )
        #expect(destination == original)

        try destination.composite(
            source,
            opacity: 1,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )
        let result = destination[.zero]
        let resultStyle = try #require(styles.value(for: result.styleID))
        #expect(result.graphemeID == upperGrapheme)
        #expect(rgba(resultStyle.foreground) == .white)
        #expect(rgba(resultStyle.background) == .black)
    }

    @Test func clipUsesActualLowerLayerStyles() throws {
        var graphemes = GraphemeInterner()
        var styles = StyleInterner()
        let red = RGBA(redByte: 255, greenByte: 0, blueByte: 0)
        let blue = RGBA(redByte: 0, greenByte: 0, blueByte: 255)
        let green = RGBA(redByte: 0, greenByte: 255, blueByte: 0)
        let firstLower = try styles.intern(CellStyle(foreground: .rgba(.black), background: .rgba(red)))
        let secondLower = try styles.intern(CellStyle(foreground: .rgba(.white), background: .rgba(blue)))
        let upper = try styles.intern(CellStyle(foreground: .rgba(.white), background: .rgba(green)))
        let lowerGrapheme = try graphemes.intern("a")
        let upperGrapheme = try graphemes.intern("b")
        var destination = Surface(size: CellSize(width: 2, height: 1))
        var source = Surface(size: CellSize(width: 2, height: 1))
        try destination.write(graphemeID: lowerGrapheme, at: .zero, styleID: firstLower)
        try destination.write(graphemeID: lowerGrapheme, at: CellPoint(x: 1, y: 0), styleID: secondLower)
        try source.write(graphemeID: upperGrapheme, at: .zero, styleID: upper)
        try source.write(graphemeID: upperGrapheme, at: CellPoint(x: 1, y: 0), styleID: upper)

        try destination.composite(
            source,
            clip: CellRect(x: 1, y: 0, width: 1, height: 1),
            opacity: 0.5,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )

        #expect(destination[.zero].styleID == firstLower)
        #expect(destination[.zero].graphemeID == lowerGrapheme)
        let blended = try #require(styles.value(for: destination[CellPoint(x: 1, y: 0)].styleID))
        let blendedForeground = try #require(rgba(blended.foreground))
        let blendedBackground = try #require(rgba(blended.background))
        #expect(blendedForeground == .white)
        #expect(blendedBackground.blueByte == 188)
        #expect(blendedBackground.greenByte == 188)
        #expect(blendedBackground.redByte == 0)
    }

    @Test func wideSourceAndDestinationAtomsDoNotCrossClipBoundaries() throws {
        var graphemes = GraphemeInterner()
        var styles = StyleInterner()
        let style = try styles.intern(CellStyle(foreground: .rgba(.white), background: .rgba(.black)))
        let narrow = try graphemes.intern("x")
        let wide = try graphemes.intern("界")
        var destination = Surface(size: CellSize(width: 4, height: 1))
        var wideSource = Surface(size: CellSize(width: 2, height: 1), fill: .transparent)
        try destination.write(graphemeID: narrow, at: .zero, styleID: style)
        try destination.write(graphemeID: wide, at: CellPoint(x: 1, y: 0), styleID: style, displayWidth: 2)
        try wideSource.write(graphemeID: wide, at: .zero, styleID: style, displayWidth: 2)
        let original = destination

        try destination.composite(
            wideSource,
            at: CellPoint(x: 2, y: 0),
            clip: CellRect(x: 2, y: 0, width: 1, height: 1),
            opacity: 1,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )
        #expect(destination == original)

        var narrowSource = Surface(size: CellSize(width: 1, height: 1))
        try narrowSource.write(graphemeID: narrow, at: .zero, styleID: style)
        try destination.composite(
            narrowSource,
            at: CellPoint(x: 2, y: 0),
            clip: CellRect(x: 2, y: 0, width: 1, height: 1),
            opacity: 1,
            graphemes: graphemes,
            styles: &styles,
            resolveColor: explicitDefaults
        )
        #expect(destination == original)
        #expect(throws: Never.self) { try destination.validateWideCells() }
    }
}

private func explicitDefaults(_ color: Color?, role: CellColorRole) -> RGBA {
    guard let color else { return role == .foreground ? .white : .black }
    guard case .rgba(let rgba) = color else {
        Issue.record("A semantic color reached the explicit test resolver")
        return .clear
    }
    return rgba
}

private func rgba(_ color: Color?) -> RGBA? {
    guard case .rgba(let rgba)? = color else { return nil }
    return rgba
}
