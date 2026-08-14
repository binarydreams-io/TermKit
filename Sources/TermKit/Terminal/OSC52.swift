/// Encodes optional OSC 52 clipboard output.
public enum OSC52Encoder {
  /// The terminal clipboard selection.
  public enum Selection: String, Sendable {
    /// The system clipboard selection.
    case clipboard = "c"
    /// The primary selection.
    case primary = "p"
    /// The terminal-defined select selection.
    case select = "s"
  }

  /// An OSC 52 encoding failure.
  public enum EncodingError: Error, Equatable, Sendable {
    /// The encoded payload exceeds the configured limit.
    case payloadTooLarge(limit: Int)
  }

  /// Encodes text as an OSC 52 terminal sequence.
  ///
  /// - Complexity: O(n), where n is the UTF-8 byte count of `text`.
  public static func encode(
    _ text: String,
    selection: Selection = .clipboard,
    maximumPayloadByteCount: Int = 100000
  ) throws -> [UInt8] {
    let limit = min(max(maximumPayloadByteCount, 1), 16_777_216)
    let encoded = encodeBase64(Array(text.utf8))
    guard encoded.count <= limit else { throw EncodingError.payloadTooLarge(limit: limit) }
    return Array("\u{1B}]52;\(selection.rawValue);".utf8) + encoded + [0x07]
  }

  private static func encodeBase64(_ bytes: [UInt8]) -> [UInt8] {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var output: [UInt8] = []
    output.reserveCapacity(((bytes.count + 2) / 3) * 4)

    var index = 0
    while index < bytes.count {
      let first = UInt32(bytes[index])
      let hasSecond = index + 1 < bytes.count
      let hasThird = index + 2 < bytes.count
      let second = hasSecond ? UInt32(bytes[index + 1]) : 0
      let third = hasThird ? UInt32(bytes[index + 2]) : 0
      let value = first << 16 | second << 8 | third

      output.append(alphabet[Int((value >> 18) & 0x3F)])
      output.append(alphabet[Int((value >> 12) & 0x3F)])
      output.append(hasSecond ? alphabet[Int((value >> 6) & 0x3F)] : 0x3D)
      output.append(hasThird ? alphabet[Int(value & 0x3F)] : 0x3D)
      index += 3
    }
    return output
  }
}
