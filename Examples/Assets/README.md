# TermKitPlayer Assets

The TermKitPlayer artwork is original work created for this repository on August 14, 2026.
Binary Dreams, LLC releases the source and generated artwork under the repository MIT License.

The artwork contains no third-party logos, fonts, photographs, or product branding.

## Blue Hour

- Source: `Sources/TermKitPlayer/Resources/Artwork/Sources/blue-hour.svg`
- Output: `Sources/TermKitPlayer/Resources/Artwork/blue-hour.png`
- Size: 96 x 96 pixels
- Source SHA-256: `e601234f1db15a1bef9c71b61521b170f384336153248348fee4f745209934c4`
- Output SHA-256: `8b42cc79eef4162d2b8b42032222eb9dc8b5464eec1c32b7db23a6b35ecb9e43`
- Command: `sips -s format png blue-hour.svg --out blue-hour.png`

## Signal Drift

- Source: `Sources/TermKitPlayer/Resources/Artwork/Sources/signal-drift.svg`
- Output: `Sources/TermKitPlayer/Resources/Artwork/signal-drift.jpg`
- Size: 96 x 96 pixels
- Source SHA-256: `6c9e9c82b2d8338103801c053d5fa213efe5640e82320fffdbe998364e796c4c`
- Output SHA-256: `0b0077382e50a214efff2669398bd7097ef438ed515536f4815678230b739414`
- Commands:
  1. `sips -s format png signal-drift.svg --out signal-drift-source.png`
  2. `sips -s format jpeg -s formatOptions 90 signal-drift-source.png --out signal-drift.jpg`
