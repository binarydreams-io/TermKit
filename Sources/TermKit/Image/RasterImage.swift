import Foundation

/// A pixel with 8-bit straight red, green, blue, and alpha components.
public struct RGBA8: Sendable, Hashable {
  /// The red component.
  public var red: UInt8
  /// The green component.
  public var green: UInt8
  /// The blue component.
  public var blue: UInt8
  /// The straight alpha component.
  public var alpha: UInt8

  /// Creates a straight RGBA pixel.
  public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}

/// Limits applied before and during raster image decoding.
public struct ImageDecodingLimits: Sendable, Hashable {
  /// The maximum encoded input size.
  public var maximumEncodedByteCount: Int
  /// The maximum width or height.
  public var maximumDimension: Int
  /// The maximum pixel count.
  public var maximumPixelCount: Int
  /// The maximum byte count of the RGBA result.
  public var maximumDecodedByteCount: Int
  /// The maximum estimated decoder working memory.
  public var maximumWorkingMemoryByteCount: Int

  /// Creates decoding limits.
  public init(
    maximumEncodedByteCount: Int = 64 * 1024 * 1024,
    maximumDimension: Int = 16384,
    maximumPixelCount: Int = 40_000_000,
    maximumDecodedByteCount: Int = 160 * 1024 * 1024,
    maximumWorkingMemoryByteCount: Int = 640 * 1024 * 1024
  ) {
    precondition(maximumEncodedByteCount > 0)
    precondition(maximumDimension > 0)
    precondition(maximumPixelCount > 0)
    precondition(maximumDecodedByteCount > 0)
    precondition(maximumWorkingMemoryByteCount > 0)
    self.maximumEncodedByteCount = maximumEncodedByteCount
    self.maximumDimension = maximumDimension
    self.maximumPixelCount = maximumPixelCount
    self.maximumDecodedByteCount = maximumDecodedByteCount
    self.maximumWorkingMemoryByteCount = maximumWorkingMemoryByteCount
  }

  /// The default limits for local image decoding.
  public static let `default` = ImageDecodingLimits()
}

/// An error produced while loading or decoding a raster image.
public enum RasterImageError: Error, Sendable, Equatable {
  /// The raster dimensions are not positive.
  case invalidDimensions(width: Int, height: Int)
  /// The pixel array does not match the dimensions.
  case invalidPixelCount(expected: Int, actual: Int)
  /// The encoded input exceeds its byte limit.
  case encodedDataTooLarge(limit: Int)
  /// The input is not a supported PNG or JPEG image.
  case unsupportedFormat
  /// The input is an animated PNG.
  case animatedPNG
  /// A dimension exceeds its configured limit.
  case dimensionsExceedLimit(width: Int, height: Int, limit: Int)
  /// The image exceeds its configured pixel-count limit.
  case pixelCountExceedsLimit(limit: Int)
  /// The decoded output exceeds its configured byte limit.
  case decodedByteCountExceedsLimit(limit: Int)
  /// The estimated decoder memory exceeds its configured limit.
  case workingMemoryExceedsLimit(limit: Int)
  /// The encoded image is malformed or truncated.
  case malformedData
  /// A local file cannot be read.
  case unreadableFile
}

/// A row-major raster image with straight RGBA8 pixels.
public struct RasterImage: Sendable, Hashable {
  /// The image width in pixels.
  public let width: Int
  /// The image height in pixels.
  public let height: Int
  /// The row-major straight RGBA8 pixels.
  public let pixels: [RGBA8]

  /// Creates a raster image from validated pixels.
  public init(width: Int, height: Int, pixels: [RGBA8]) throws {
    guard width > 0, height > 0 else {
      throw RasterImageError.invalidDimensions(width: width, height: height)
    }
    let expected = try Self.checkedProduct(width, height, overflow: .invalidDimensions(width: width, height: height))
    guard pixels.count == expected else {
      throw RasterImageError.invalidPixelCount(expected: expected, actual: pixels.count)
    }
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// Decodes PNG or JPEG data within the specified limits.
  public init(decoding data: Data, limits: ImageDecodingLimits = .default) throws {
    self = try ImageDecoder.decode(data, limits: limits)
  }

  /// Loads and decodes a bounded local file URL.
  public init(contentsOf url: URL, limits: ImageDecodingLimits = .default) throws {
    guard url.isFileURL else { throw RasterImageError.unreadableFile }
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      throw RasterImageError.unreadableFile
    }
    defer { try? handle.close() }
    do {
      let data = try handle.read(upToCount: limits.maximumEncodedByteCount) ?? Data()
      let trailingData = try handle.read(upToCount: 1) ?? Data()
      guard trailingData.isEmpty else {
        throw RasterImageError.encodedDataTooLarge(limit: limits.maximumEncodedByteCount)
      }
      self = try ImageDecoder.decode(data, limits: limits)
    } catch let error as RasterImageError {
      throw error
    } catch {
      throw RasterImageError.unreadableFile
    }
  }

  /// Returns the pixel at a validated coordinate.
  public subscript(x: Int, y: Int) -> RGBA8 {
    precondition((0 ..< width).contains(x) && (0 ..< height).contains(y))
    return pixels[y * width + x]
  }

  static func checkedProduct(_ lhs: Int, _ rhs: Int, overflow error: RasterImageError) throws -> Int {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    guard result.overflow == false else { throw error }
    return result.partialValue
  }
}
