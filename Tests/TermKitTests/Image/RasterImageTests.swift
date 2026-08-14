import Foundation
import Testing

@testable import TermKit

struct RasterImageTests {
    @Test("Raster images validate dimensions and pixel count")
    func validation() throws {
        #expect(throws: RasterImageError.invalidDimensions(width: 0, height: 1)) {
            _ = try RasterImage(width: 0, height: 1, pixels: [])
        }
        #expect(throws: RasterImageError.invalidPixelCount(expected: 2, actual: 1)) {
            _ = try RasterImage(width: 2, height: 1, pixels: [RGBA8(red: 0, green: 0, blue: 0)])
        }
    }

    @Test("PNG alpha decodes to straight RGBA8")
    func pngAlpha() throws {
        let image = try RasterImage(decoding: fixtureData("alpha.png"))

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.pixels.contains { $0.alpha < 255 })
        #expect(image.pixels.contains { $0.green > $0.red && $0.green > $0.blue })
    }

    @Test("JPEG decodes to opaque RGBA8")
    func jpegOpaque() throws {
        let image = try RasterImage(decoding: fixtureData("opaque.jpg"))

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.pixels.allSatisfy { $0.alpha == 255 })
    }

    @Test("Unsupported and truncated inputs are rejected")
    func malformedInputs() throws {
        #expect(throws: RasterImageError.unsupportedFormat) {
            _ = try RasterImage(decoding: encodedFixtureData("invalid-signature.base64"))
        }
        #expect(throws: RasterImageError.malformedData) {
            _ = try RasterImage(decoding: encodedFixtureData("truncated-png.base64"))
        }
        #expect(throws: RasterImageError.malformedData) {
            _ = try RasterImage(decoding: encodedFixtureData("truncated-jpeg.base64"))
        }
    }

    @Test("PNG preflight rejects animation and unsafe dimensions")
    func pngPreflight() throws {
        #expect(throws: RasterImageError.animatedPNG) {
            _ = try RasterImage(decoding: encodedFixtureData("animated-png.base64"))
        }

        #expect(throws: RasterImageError.dimensionsExceedLimit(width: 256, height: 2, limit: 32)) {
            _ = try RasterImage(
                decoding: encodedFixtureData("excessive-dimensions.base64"),
                limits: ImageDecodingLimits(maximumDimension: 32)
            )
        }
        #expect(throws: RasterImageError.pixelCountExceedsLimit(limit: 3)) {
            _ = try RasterImage(
                decoding: encodedFixtureData("excessive-pixels.base64"),
                limits: ImageDecodingLimits(maximumPixelCount: 3)
            )
        }
        #expect(throws: RasterImageError.decodedByteCountExceedsLimit(limit: 15)) {
            _ = try RasterImage(
                decoding: fixtureData("alpha.png"),
                limits: ImageDecodingLimits(maximumDecodedByteCount: 15)
            )
        }
        #expect(throws: RasterImageError.workingMemoryExceedsLimit(limit: 63)) {
            _ = try RasterImage(
                decoding: fixtureData("alpha.png"),
                limits: ImageDecodingLimits(maximumWorkingMemoryByteCount: 63)
            )
        }
    }

    @Test("Data and local file reads enforce encoded byte limits")
    func encodedLimits() throws {
        let url = try #require(Bundle.module.url(forResource: "alpha", withExtension: "png", subdirectory: "Fixtures/Image"))
        let limit = ImageDecodingLimits(maximumEncodedByteCount: 8)
        #expect(throws: RasterImageError.encodedDataTooLarge(limit: 8)) {
            _ = try RasterImage(decoding: fixtureData("alpha.png"), limits: limit)
        }
        #expect(throws: RasterImageError.encodedDataTooLarge(limit: 8)) {
            _ = try RasterImage(contentsOf: url, limits: limit)
        }
        #expect(throws: RasterImageError.unreadableFile) {
            _ = try RasterImage(contentsOf: URL(string: "https://example.com/image.png")!)
        }
        let image = try RasterImage(
            contentsOf: url,
            limits: ImageDecodingLimits(maximumEncodedByteCount: .max)
        )
        #expect(image.width == 2)
        #expect(image.height == 2)
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
    let url = try #require(
        Bundle.module.url(
            forResource: parts[0],
            withExtension: parts[1],
            subdirectory: "Fixtures/Image"
        )
    )
    return try Data(contentsOf: url)
}

private func encodedFixtureData(_ name: String) throws -> Data {
    let encoded = try String(decoding: fixtureData(name), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return try #require(Data(base64Encoded: encoded))
}
