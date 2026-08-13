//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PNGImageDecoderMetadata.swift
//
//  Created by LAYERED.work
//  License: MIT

extension PNGImageDecoder {
  static func inspect(_ bytes: [UInt8]) throws -> DecodedImageMetadata {
    guard bytes.count >= 29,
          readUInt32(bytes, at: 8) == 13,
          Array(bytes[12 ..< 16]) == [0x49, 0x48, 0x44, 0x52]
    else {
      throw ImageLoadError.decodingFailed("invalid PNG header")
    }

    let width = Int(readUInt32(bytes, at: 16))
    let height = Int(readUInt32(bytes, at: 20))
    let bitDepth = Int(bytes[24])
    let colorType = bytes[25]
    let interlaceMethod = bytes[28]

    guard bytes[26] == 0, bytes[27] == 0 else {
      throw ImageLoadError.decodingFailed("unsupported PNG compression or filter method")
    }
    guard validBitDepth(bitDepth, for: colorType) else {
      throw ImageLoadError.decodingFailed("invalid PNG color format")
    }

    let bitsPerPixel = bitDepth * channelCount(for: colorType)
    let decompressedByteCount = try decompressedByteCount(
      width: width,
      height: height,
      bitsPerPixel: bitsPerPixel,
      interlaceMethod: interlaceMethod
    )
    return try DecodedImageMetadata(
      width: width,
      height: height,
      frameCount: frameCount(in: bytes),
      decompressedByteCount: decompressedByteCount
    )
  }
}

extension PNGImageDecoder {
  fileprivate static func frameCount(in bytes: [UInt8]) throws -> Int {
    var chunkOffset = 33
    while chunkOffset <= bytes.count - 12 {
      let chunkDataLength = Int(readUInt32(bytes, at: chunkOffset))
      let (chunkByteCount, chunkByteCountOverflow) = chunkDataLength.addingReportingOverflow(12)
      guard !chunkByteCountOverflow, chunkByteCount <= bytes.count - chunkOffset else {
        return 1
      }

      let chunkType = Array(bytes[(chunkOffset + 4) ..< (chunkOffset + 8)])
      if chunkType == [0x61, 0x63, 0x54, 0x4C] {
        guard chunkDataLength == 8 else {
          throw ImageLoadError.decodingFailed("invalid PNG animation control")
        }
        let count = Int(readUInt32(bytes, at: chunkOffset + 8))
        guard count > 0 else {
          throw ImageLoadError.decodingFailed("invalid PNG animation frame count")
        }
        return count
      }
      if chunkType == [0x49, 0x45, 0x4E, 0x44] {
        return 1
      }
      chunkOffset += chunkByteCount
    }
    return 1
  }

  fileprivate static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24
      | UInt32(bytes[offset + 1]) << 16
      | UInt32(bytes[offset + 2]) << 8
      | UInt32(bytes[offset + 3])
  }

  fileprivate static func channelCount(for colorType: UInt8) -> Int {
    switch colorType {
    case 0, 3: 1
    case 2: 3
    case 4: 2
    case 6: 4
    default: 0
    }
  }

  fileprivate static func validBitDepth(_ bitDepth: Int, for colorType: UInt8) -> Bool {
    switch colorType {
    case 0:
      [1, 2, 4, 8, 16].contains(bitDepth)
    case 2, 4, 6:
      [8, 16].contains(bitDepth)
    case 3:
      [1, 2, 4, 8].contains(bitDepth)
    default:
      false
    }
  }

  fileprivate static func decompressedByteCount(
    width: Int,
    height: Int,
    bitsPerPixel: Int,
    interlaceMethod: UInt8
  ) throws -> Int {
    switch interlaceMethod {
    case 0:
      return try scanlineByteCount(
        width: width,
        height: height,
        bitsPerPixel: bitsPerPixel,
        imageWidth: width,
        imageHeight: height
      )
    case 1:
      let passes = [
        (x: 0, y: 0, dx: 8, dy: 8),
        (x: 4, y: 0, dx: 8, dy: 8),
        (x: 0, y: 4, dx: 4, dy: 8),
        (x: 2, y: 0, dx: 4, dy: 4),
        (x: 0, y: 2, dx: 2, dy: 4),
        (x: 1, y: 0, dx: 2, dy: 2),
        (x: 0, y: 1, dx: 1, dy: 2)
      ]
      var byteCount = 0
      for pass in passes {
        let passWidth = passLength(width, start: pass.x, step: pass.dx)
        let passHeight = passLength(height, start: pass.y, step: pass.dy)
        guard passWidth > 0, passHeight > 0 else { continue }

        let passByteCount = try scanlineByteCount(
          width: passWidth,
          height: passHeight,
          bitsPerPixel: bitsPerPixel,
          imageWidth: width,
          imageHeight: height
        )
        let (sum, overflow) = byteCount.addingReportingOverflow(passByteCount)
        guard !overflow else {
          throw ImageLoadError.sizeOverflow(width: width, height: height)
        }
        byteCount = sum
      }
      return byteCount
    default:
      throw ImageLoadError.decodingFailed("invalid PNG interlace method")
    }
  }

  fileprivate static func scanlineByteCount(
    width: Int,
    height: Int,
    bitsPerPixel: Int,
    imageWidth: Int,
    imageHeight: Int
  ) throws -> Int {
    let (rowBitCount, rowBitCountOverflow) = width.multipliedReportingOverflow(by: bitsPerPixel)
    guard !rowBitCountOverflow, rowBitCount <= Int.max - 7 else {
      throw ImageLoadError.sizeOverflow(width: imageWidth, height: imageHeight)
    }
    let rowByteCount = (rowBitCount + 7) / 8
    guard rowByteCount < Int.max else {
      throw ImageLoadError.sizeOverflow(width: imageWidth, height: imageHeight)
    }
    let (byteCount, byteCountOverflow) = (rowByteCount + 1).multipliedReportingOverflow(by: height)
    guard !byteCountOverflow else {
      throw ImageLoadError.sizeOverflow(width: imageWidth, height: imageHeight)
    }
    return byteCount
  }

  fileprivate static func passLength(_ length: Int, start: Int, step: Int) -> Int {
    guard length > start else { return 0 }
    return (length - start + step - 1) / step
  }
}
