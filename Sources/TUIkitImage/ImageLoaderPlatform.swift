//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageLoaderPlatform.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Platform Image Loader

/// Cross-platform image loader backed by pure Swift PNG and JPEG decoders.
public struct PlatformImageLoader: ImageLoader {
  private let decoder: PureSwiftImageDecoder

  public init(limits: ImageDecodingLimits = .default) {
    self.decoder = PureSwiftImageDecoder(limits: limits)
  }

  public func loadImage(from path: String) throws -> RGBAImage {
    try loadImage(from: path, maxPixelCount: nil)
  }

  public func loadImage(from data: Data) throws -> RGBAImage {
    try loadImage(from: data, maxPixelCount: nil)
  }

  /// Loads an image from a file path with an optional pixel count limit.
  ///
  /// - Parameters:
  ///   - path: The absolute file path to the image.
  ///   - maxPixelCount: An optional tighter pixel limit. The loader-wide limit always applies.
  /// - Returns: The decoded image as `RGBAImage`.
  /// - Throws: `ImageLoadError` if the file cannot be read, decoded, or exceeds the limit.
  public func loadImage(from path: String, maxPixelCount: Int?) throws -> RGBAImage {
    guard FileManager.default.fileExists(atPath: path) else {
      throw ImageLoadError.fileNotFound(path)
    }

    let data = try readImageData(at: path)
    return try decoder.decode(data, maxPixelCount: maxPixelCount)
  }

  /// Loads an image from raw data with an optional pixel count limit.
  ///
  /// - Parameters:
  ///   - data: The image file data.
  ///   - maxPixelCount: An optional tighter pixel limit. The loader-wide limit always applies.
  /// - Returns: The decoded image as `RGBAImage`.
  /// - Throws: `ImageLoadError` if the data cannot be decoded or exceeds the limit.
  public func loadImage(from data: Data, maxPixelCount: Int?) throws -> RGBAImage {
    try decoder.decode(data, maxPixelCount: maxPixelCount)
  }
}

extension PlatformImageLoader {
  private func readImageData(at path: String) throws -> Data {
    let limit = decoder.maxInputBytes
    guard limit >= 0 else {
      throw ImageLoadError.inputTooLarge(byteCount: 0, limit: limit)
    }

    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    } catch {
      throw ImageLoadError.decodingFailed("unable to read image file")
    }
    defer { try? handle.close() }

    var data = Data()
    do {
      while data.count <= limit {
        let remainingByteCount = limit == Int.max ? Int.max - data.count : limit + 1 - data.count
        let readByteCount = min(remainingByteCount, 64 * 1024)
        guard readByteCount > 0,
              let chunk = try handle.read(upToCount: readByteCount),
              !chunk.isEmpty
        else {
          break
        }
        data.append(chunk)
      }
    } catch {
      throw ImageLoadError.decodingFailed("unable to read image file")
    }

    guard data.count <= limit else {
      throw ImageLoadError.inputTooLarge(byteCount: data.count, limit: limit)
    }
    return data
  }
}

// MARK: - URL Image Loading

extension PlatformImageLoader {
  /// Loads an image from a URL, using the session cache.
  ///
  /// On first access the image is downloaded synchronously and cached.
  /// Subsequent calls for the same URL return the cached copy.
  ///
  /// - Parameters:
  ///   - urlString: The URL to download.
  ///   - cache: The image cache to use.
  ///   - timeout: The download timeout in seconds (default: 30).
  ///   - maxPixelCount: An optional tighter pixel limit. The loader-wide limit always applies.
  /// - Returns: The decoded image.
  /// - Throws: `ImageLoadError` on network or decoding failure, or if image exceeds size limit.
  public func loadImage(
    from urlString: String,
    cache: URLImageCache,
    timeout: TimeInterval = 30,
    maxPixelCount: Int? = nil
  ) throws -> RGBAImage {
    if let cached = cache.get(urlString) {
      try decoder.validateCachedImage(cached, maxPixelCount: maxPixelCount)
      return cached
    }

    guard let url = URL(string: urlString) else {
      throw ImageLoadError.downloadFailed("Invalid URL: \(urlString)")
    }

    let data: Data
    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = timeout
      data = try BoundedURLImageDataLoader.load(
        request: request,
        maxByteCount: decoder.maxInputBytes
      )
    } catch let error as ImageLoadError {
      throw error
    } catch {
      throw ImageLoadError.downloadFailed(error.localizedDescription)
    }

    let image = try loadImage(from: data, maxPixelCount: maxPixelCount)
    cache.set(urlString, image: image)
    return image
  }
}
