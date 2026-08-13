//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageLoader.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - ImageLoader Protocol

/// Loads images from file paths or raw data and converts them to `RGBAImage`.
///
/// Uses pure Swift decoders on all platforms for consistent behavior.
/// Supported formats: static PNG and JPEG, decoded as non-premultiplied 8-bit RGBA.
public protocol ImageLoader: Sendable {
  /// Loads an image from a file path.
  ///
  /// - Parameter path: The absolute file path to the image.
  /// - Returns: The decoded image as `RGBAImage`.
  /// - Throws: `ImageLoadError` if the file cannot be read or decoded.
  func loadImage(from path: String) throws -> RGBAImage

  /// Loads an image from raw data.
  ///
  /// - Parameter data: The image file data.
  /// - Returns: The decoded image as `RGBAImage`.
  /// - Throws: `ImageLoadError` if the data cannot be decoded.
  func loadImage(from data: Data) throws -> RGBAImage

  /// Loads an image from a file path with an optional pixel limit.
  func loadImage(from path: String, maxPixelCount: Int?) throws -> RGBAImage

  /// Loads an image from a URL using the supplied runtime cache.
  func loadImage(
    from urlString: String,
    cache: URLImageCache,
    timeout: TimeInterval,
    maxPixelCount: Int?
  ) throws -> RGBAImage
}

// MARK: - ImageLoader Defaults

extension ImageLoader {
  public func loadImage(from path: String, maxPixelCount: Int?) throws -> RGBAImage {
    let image = try loadImage(from: path)
    try validatePixelCount(image, maxPixelCount: maxPixelCount)
    return image
  }

  public func loadImage(
    from urlString: String,
    cache: URLImageCache,
    timeout: TimeInterval,
    maxPixelCount: Int?
  ) throws -> RGBAImage {
    if let image = cache.get(urlString) {
      try validatePixelCount(image, maxPixelCount: maxPixelCount)
      return image
    }
    throw ImageLoadError.downloadFailed("URL loading is not supported by this image loader")
  }
}

// MARK: - ImageLoadError

/// Errors that can occur during image loading.
public enum ImageLoadError: Error, LocalizedError, CustomStringConvertible {
  /// The file was not found at the given path.
  case fileNotFound(String)

  /// The image format is not supported.
  case unsupportedFormat(String)

  /// The image data could not be decoded.
  case decodingFailed(String)

  /// A URL download failed.
  case downloadFailed(String)

  /// The image exceeds the maximum allowed pixel count.
  case imageTooLarge(pixelCount: Int, limit: Int)

  /// The encoded image exceeds the maximum allowed byte count.
  case inputTooLarge(byteCount: Int, limit: Int)

  /// An image dimension exceeds the maximum allowed size.
  case dimensionTooLarge(width: Int, height: Int, limit: Int)

  /// Image dimensions cannot be represented as a safe allocation size.
  case sizeOverflow(width: Int, height: Int)

  /// The final RGBA buffer would exceed its allocation limit.
  case allocationLimitExceeded(byteCount: Int, limit: Int)

  /// The decompressed source samples would exceed their byte limit.
  case decompressionLimitExceeded(byteCount: Int, limit: Int)

  /// The image contains more frames than the configured limit.
  case frameLimitExceeded(frameCount: Int, limit: Int)

  public var description: String {
    switch self {
    case let .fileNotFound(path):
      "Image file not found: \(path)"
    case let .unsupportedFormat(format):
      "Unsupported image format: \(format)"
    case let .decodingFailed(reason):
      "Image decoding failed: \(reason)"
    case let .downloadFailed(reason):
      "Image download failed: \(reason)"
    case let .imageTooLarge(pixelCount, limit):
      "Image too large: \(pixelCount) pixels (limit: \(limit))"
    case let .inputTooLarge(byteCount, limit):
      "Image input too large: \(byteCount) bytes (limit: \(limit))"
    case let .dimensionTooLarge(width, height, limit):
      "Image dimensions too large: \(width)x\(height) (limit: \(limit))"
    case let .sizeOverflow(width, height):
      "Image dimensions overflow: \(width)x\(height)"
    case let .allocationLimitExceeded(byteCount, limit):
      "Image allocation too large: \(byteCount) bytes (limit: \(limit))"
    case let .decompressionLimitExceeded(byteCount, limit):
      "Image decompression too large: \(byteCount) bytes (limit: \(limit))"
    case let .frameLimitExceeded(frameCount, limit):
      "Image frame count too large: \(frameCount) frames (limit: \(limit))"
    }
  }

  public var errorDescription: String? {
    description
  }
}

// MARK: - URL Image Cache

/// A session-scoped cache for images downloaded from URLs.
///
/// Cached entries persist for the lifetime of the application.
/// Thread-safe via an internal lock.
public final class URLImageCache: @unchecked Sendable {
  private var cache: [String: RGBAImage] = [:]
  private let lock = NSLock()

  /// Creates an empty session cache.
  public init() {}

  /// Returns a cached image for the given URL string, or nil.
  public func get(_ urlString: String) -> RGBAImage? {
    lock.lock()
    defer { lock.unlock() }
    return cache[urlString]
  }

  /// Stores an image in the cache for the given URL string.
  public func set(_ urlString: String, image: RGBAImage) {
    lock.lock()
    defer { lock.unlock() }
    cache[urlString] = image
  }

  /// Removes every cached image.
  public func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    cache.removeAll()
  }
}

// MARK: - Pixel Limit Validation

private func validatePixelCount(_ image: RGBAImage, maxPixelCount: Int?) throws {
  guard let maxPixelCount else { return }
  let (pixelCount, overflow) = image.width.multipliedReportingOverflow(by: image.height)
  guard !overflow else {
    throw ImageLoadError.sizeOverflow(width: image.width, height: image.height)
  }
  guard pixelCount <= maxPixelCount else {
    throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: maxPixelCount)
  }
}
