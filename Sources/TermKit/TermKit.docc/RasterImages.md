# Raster Images

Decode bounded PNG and JPEG data and render pixels in terminal cells.

Create a ``RasterImage`` from `Data` or a local file URL. Use ``ImageDecodingLimits`` to bound input, dimensions, pixels, decoded bytes, and working memory.

```swift
let raster = try RasterImage(contentsOf: fileURL)
let view = Image(
    raster,
    label: "Album artwork",
    contentMode: .fit,
    background: RGBA8(red: 0, green: 0, blue: 0)
)
```

``ImageContentMode/fit`` shows the complete image. ``ImageContentMode/fill`` crops around the center.
The renderer corrects for terminal cell aspect ratio and combines two vertical pixels with an upper-half block.

The terminal encoder quantizes colors for truecolor, ANSI-256, and ANSI-16 modes.
Monochrome mode uses block glyphs without color SGR output.

Version 2.1.0 rejects network URLs, unknown formats, and animated PNG data.
