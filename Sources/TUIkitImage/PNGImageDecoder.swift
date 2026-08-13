//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PNGImageDecoder.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitVendorPNG

enum PNGImageDecoder {
  static func decode(_ bytes: [UInt8]) throws -> RGBAImage {
    do {
      var source = try ImageByteStream(bytes: discardingCompressedMetadata(from: bytes))
      let image: PNG.Image = try .decompress(stream: &source)
      let decodedPixels: [PNG.RGBA<UInt8>] = image.unpack(as: PNG.RGBA<UInt8>.self)
      let pixels = decodedPixels.map { pixel in
        RGBA(r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a)
      }
      let (expectedPixelCount, overflow) = image.size.x.multipliedReportingOverflow(by: image.size.y)
      guard !overflow, pixels.count == expectedPixelCount else {
        throw ImageLoadError.decodingFailed("inconsistent PNG pixel count")
      }
      return RGBAImage(width: image.size.x, height: image.size.y, pixels: pixels)
    } catch {
      throw ImageLoadError.decodingFailed("invalid PNG data")
    }
  }
}

extension ImageByteStream: PNG.BytestreamSource {}

private struct PNGByteDestination: PNG.BytestreamDestination {
  private(set) var bytes: [UInt8] = []

  init(capacity: Int) {
    bytes.reserveCapacity(capacity)
  }

  mutating func write(_ buffer: [UInt8]) -> Void? {
    bytes.append(contentsOf: buffer)
    return ()
  }
}

extension PNGImageDecoder {
  fileprivate static var maximumImageDataChunkBytes: Int {
    64
  }

  fileprivate static func discardingCompressedMetadata(from bytes: [UInt8]) throws -> [UInt8] {
    var source = ImageByteStream(bytes: bytes)
    try source.signature()

    var destination = PNGByteDestination(capacity: bytes.count)
    try destination.signature()
    var imageDataSequenceStarted = false
    var imageDataSequenceEnded = false

    while true {
      let chunk = try source.chunk()
      if chunk.type == .IDAT {
        guard !imageDataSequenceEnded else {
          throw ImageLoadError.decodingFailed("non-contiguous PNG image data")
        }
        imageDataSequenceStarted = true
        try writeImageData(chunk.data, to: &destination)
      } else {
        if imageDataSequenceStarted {
          imageDataSequenceEnded = true
        }
        if shouldKeep(chunk.type) {
          try destination.format(type: chunk.type, data: chunk.data)
        }
      }
      if chunk.type == .IEND {
        return destination.bytes
      }
    }
  }

  fileprivate static func shouldKeep(_ chunkType: PNG.Chunk) -> Bool {
    switch chunkType {
    case .CgBI, .IHDR, .PLTE, .tRNS, .IEND:
      true
    default:
      false
    }
  }

  fileprivate static func writeImageData(_ data: [UInt8], to destination: inout PNGByteDestination) throws {
    guard !data.isEmpty else {
      try destination.format(type: .IDAT)
      return
    }

    var offset = 0
    while offset < data.endIndex {
      let endOffset = min(offset + maximumImageDataChunkBytes, data.endIndex)
      try destination.format(type: .IDAT, data: Array(data[offset ..< endOffset]))
      offset = endOffset
    }
  }
}
