@testable import TermKit
import Testing

struct OSC52Tests {
  @Test
  func `OSC 52 encodes UTF-8 as Base64`() throws {
    let bytes = try OSC52Encoder.encode("hello")

    #expect(String(decoding: bytes, as: UTF8.self) == "\u{1B}]52;c;aGVsbG8=\u{07}")
  }

  @Test
  func `OSC 52 enforces its encoded payload limit`() {
    #expect(throws: OSC52Encoder.EncodingError.payloadTooLarge(limit: 4)) {
      try OSC52Encoder.encode("hello", maximumPayloadByteCount: 4)
    }
  }
}
