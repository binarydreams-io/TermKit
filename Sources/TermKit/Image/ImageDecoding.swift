import Foundation
internal import JPEG
internal import PNG

enum ImageDecoder {
    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    static func decode(_ data: Data, limits: ImageDecodingLimits) throws -> RasterImage {
        guard data.count <= limits.maximumEncodedByteCount else {
            throw RasterImageError.encodedDataTooLarge(limit: limits.maximumEncodedByteCount)
        }
        let bytes = [UInt8](data)
        if bytes.starts(with: pngSignature) {
            return try decodePNG(bytes, limits: limits)
        }
        if bytes.count >= 3, bytes[0] == 0xff, bytes[1] == 0xd8, bytes[2] == 0xff {
            return try decodeJPEG(bytes, limits: limits)
        }
        throw RasterImageError.unsupportedFormat
    }

    private static func validate(width: Int, height: Int, limits: ImageDecodingLimits) throws {
        guard width > 0, height > 0 else {
            throw RasterImageError.invalidDimensions(width: width, height: height)
        }
        guard width <= limits.maximumDimension, height <= limits.maximumDimension else {
            throw RasterImageError.dimensionsExceedLimit(width: width, height: height, limit: limits.maximumDimension)
        }
        let pixels = try RasterImage.checkedProduct(
            width,
            height,
            overflow: .pixelCountExceedsLimit(limit: limits.maximumPixelCount)
        )
        guard pixels <= limits.maximumPixelCount else {
            throw RasterImageError.pixelCountExceedsLimit(limit: limits.maximumPixelCount)
        }
        let decoded = try RasterImage.checkedProduct(
            pixels,
            4,
            overflow: .decodedByteCountExceedsLimit(limit: limits.maximumDecodedByteCount)
        )
        guard decoded <= limits.maximumDecodedByteCount else {
            throw RasterImageError.decodedByteCountExceedsLimit(limit: limits.maximumDecodedByteCount)
        }
        let working = try RasterImage.checkedProduct(
            pixels,
            16,
            overflow: .workingMemoryExceedsLimit(limit: limits.maximumWorkingMemoryByteCount)
        )
        guard working <= limits.maximumWorkingMemoryByteCount else {
            throw RasterImageError.workingMemoryExceedsLimit(limit: limits.maximumWorkingMemoryByteCount)
        }
    }

    private static func decodePNG(_ bytes: [UInt8], limits: ImageDecodingLimits) throws -> RasterImage {
        let inspection = try inspectPNG(bytes)
        try validate(width: inspection.width, height: inspection.height, limits: limits)
        guard inspection.isAnimated == false else { throw RasterImageError.animatedPNG }
        do {
            var source = PNGMemorySource(bytes)
            let image = try PNG.Image.decompress(stream: &source)
            guard image.size.x == inspection.width, image.size.y == inspection.height else {
                throw RasterImageError.malformedData
            }
            var unpacked = image.unpack(as: PNG.RGBA<UInt8>.self)
            if inspection.isCgBI {
                unpacked = unpacked.map(\.straightened)
            }
            return try RasterImage(
                width: image.size.x,
                height: image.size.y,
                pixels: unpacked.map { RGBA8(red: $0.r, green: $0.g, blue: $0.b, alpha: $0.a) }
            )
        } catch let error as RasterImageError {
            throw error
        } catch {
            throw RasterImageError.malformedData
        }
    }

    private static func inspectPNG(_ bytes: [UInt8]) throws -> (width: Int, height: Int, isCgBI: Bool, isAnimated: Bool) {
        guard bytes.starts(with: pngSignature) else { throw RasterImageError.malformedData }
        var offset = pngSignature.count
        var width: Int?
        var height: Int?
        var isCgBI = false
        var isAnimated = false
        while offset <= bytes.count - 12 {
            let length = Int(readUInt32(bytes, at: offset))
            let headerEnd = offset + 8
            let chunkEnd = headerEnd.addingReportingOverflow(length)
            guard chunkEnd.overflow == false, chunkEnd.partialValue <= bytes.count - 4 else {
                throw RasterImageError.malformedData
            }
            let type = String(bytes: bytes[(offset + 4)..<headerEnd], encoding: .ascii)
            switch type {
            case "CgBI": isCgBI = true
            case "IHDR":
                guard length == 13 else { throw RasterImageError.malformedData }
                width = Int(readUInt32(bytes, at: headerEnd))
                height = Int(readUInt32(bytes, at: headerEnd + 4))
            case "acTL", "fcTL", "fdAT": isAnimated = true
            case "IEND":
                guard let width, let height else { throw RasterImageError.malformedData }
                return (width, height, isCgBI, isAnimated)
            default: break
            }
            offset = chunkEnd.partialValue + 4
        }
        throw RasterImageError.malformedData
    }

    private static func decodeJPEG(_ bytes: [UInt8], limits: ImageDecodingLimits) throws -> RasterImage {
        do {
            var source = JPEGMemorySource(bytes)
            let frame = try inspectJPEG(source: &source)
            try validate(width: frame.size.x, height: frame.size.y, limits: limits)
            source.rewind()
            let image: JPEG.Data.Rectangular<JPEG.Common> = try .decompress(stream: &source)
            guard image.size.x == frame.size.x, image.size.y == frame.size.y else {
                throw RasterImageError.malformedData
            }
            let pixels = image.unpack(as: JPEGRGBA8.self).map {
                RGBA8(red: $0.red, green: $0.green, blue: $0.blue, alpha: 255)
            }
            return try RasterImage(width: image.size.x, height: image.size.y, pixels: pixels)
        } catch let error as RasterImageError {
            throw error
        } catch {
            throw RasterImageError.malformedData
        }
    }

    private static func inspectJPEG(source: inout JPEGMemorySource) throws -> JPEG.Header.Frame {
        let first = try source.segment().0
        guard case .start = first else { throw RasterImageError.malformedData }
        while true {
            let segment = try source.segment()
            switch segment.0 {
            case .frame(let process):
                let frame = try JPEG.Header.Frame.parse(segment.1, process: process)
                guard frame.size.y > 0 else { throw RasterImageError.malformedData }
                return frame
            case .scan, .end:
                throw RasterImageError.malformedData
            default:
                continue
            }
        }
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}

private struct PNGMemorySource: PNG.BytestreamSource {
    let bytes: [UInt8]
    var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func read(count: Int) -> [UInt8]? {
        guard count >= 0, count <= bytes.count - offset else { return nil }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }
}

private struct JPEGMemorySource: JPEG.Bytestream.Source {
    let bytes: [UInt8]
    var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func read(count: Int) -> [UInt8]? {
        guard count >= 0, count <= bytes.count - offset else { return nil }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func rewind() { offset = 0 }
}

private struct JPEGRGBA8: JPEG.Color {
    typealias Format = JPEG.Common
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static func unpack(_ interleaved: [UInt16], of format: JPEG.Common) -> [Self] {
        switch format {
        case .y8, .nonconforming1x8:
            return interleaved.map { Self(red: UInt8($0), green: UInt8($0), blue: UInt8($0)) }
        case .ycc8, .nonconforming3x8:
            return stride(from: 0, to: interleaved.count, by: 3).map { index in
                let rgb = JPEG.YCbCr(
                    y: UInt8(interleaved[index]),
                    cb: UInt8(interleaved[index + 1]),
                    cr: UInt8(interleaved[index + 2])
                ).rgb
                return Self(red: rgb.r, green: rgb.g, blue: rgb.b)
            }
        }
    }

    static func pack(_ pixels: [Self], as format: JPEG.Common) -> [UInt16] {
        JPEG.RGB.pack(pixels.map { JPEG.RGB($0.red, $0.green, $0.blue) }, as: format)
    }
}
