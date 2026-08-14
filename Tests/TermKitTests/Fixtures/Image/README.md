# Image Fixtures

`alpha.png` and `opaque.jpg` are generated test images released under the repository MIT license.
Their SVG and PPM source files are stored beside the encoded files.

The `.base64` files contain deterministic malformed variants of these images:

- `invalid-signature.base64` contains text instead of an image signature.
- `truncated-png.base64` contains the first 20 bytes of `alpha.png`.
- `truncated-jpeg.base64` contains the first 12 bytes of `opaque.jpg`.
- `animated-png.base64` inserts an `acTL` marker into `alpha.png`.
- `excessive-dimensions.base64` sets the PNG width to 256 pixels.
- `excessive-pixels.base64` sets the PNG size to 4 by 4 pixels.

The malformed files test wrapper preflight checks. They are not valid decoder outputs.
