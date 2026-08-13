# Legacy TUIkit Regression: Vendored Image Codecs

SwiftTUI retains these sources as internal TUIkit regression and provenance evidence. The codec targets are not public SwiftTUI products.

| Source | Revision | Included targets | License |
| --- | --- | --- | --- |
| `tayloraswift/swift-png` | `2f68db3d6b3005035dc213275e8f35b6a4d0581f` | `PNG`, `LZ77` | Apache-2.0 and MPL-2.0 |
| `tayloraswift/swift-jpeg` | `c393ac5a683d09c6b1d6410402e25a606d36836f` | `JPEG` | MPL-2.0 |
| `tayloraswift/swift-hash` | `7fd5fb1753fe69bd6c04ecda36aab546cdcaae99` | `BaseDigits`, `Base16`, `CRC` | Apache-2.0 |

The original licenses and notices remain beside each source tree. Imports use `TUIkit`-prefixed module names to prevent collisions during legacy tests.

Legacy regression changes must preserve these properties:

- Pure Swift sources with Swift 6.0.3 support on macOS and Linux.
- Static PNG and JPEG decoding to non-premultiplied 8-bit RGBA output.
- Bounds for input, dimensions, pixels, frames, decompressed samples, and final allocations.
- Separation between deterministic decoding and file or network lifecycle code.
- Explicit notices for local safety changes.
