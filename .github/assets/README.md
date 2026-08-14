# Showcase Capture Metadata

The images show the full and compact TermKitPlayer layouts. The recording uses the asciinema cast version 2 format.

## Environment

- Platform: macOS 15
- Terminal model: xterm-256color
- Font: Menlo
- Full terminal size: 120 x 32 cells
- Compact terminal size: 56 x 18 cells
- Command: `swift run --package-path Examples TermKitPlayer`
- Creation date: August 14, 2026

## Method

The committed semantic snapshots supplied the text and layout data. Custom SVG files reproduce the smoked-steel player palette.
The `sips` tool converted each SVG file to PNG. The cast records startup, playback, resize, and pause states.

## Files

- `termkit-player-full.png`: full player screenshot
- `termkit-player-compact.png`: compact player screenshot
- `termkit-player-demo.cast`: short terminal recording
- `termkit-player-full.svg`: editable source for the full screenshot
- `termkit-player-compact.svg`: editable source for the compact screenshot

## SHA-256

- `termkit-player-full.png`: `3fb2112e0437ef7d85ba6800578ab98933b5ecc29a4620c2d11bfca6ea6c0965`
- `termkit-player-compact.png`: `b754e43743e1b15749286da532eae2ec8cc745432b42602dc7a4ff78a2dfca12`
- `termkit-player-demo.cast`: `4f9a4a226096b41cf9e6cc0d22c4cca618f4597530cdae0e296e574c76160999`
- `termkit-player-full.svg`: `a3018b937dfd19c7c1ee3379cb01c0b1bc928350ea36b2079b8af8bb9151d6a0`
- `termkit-player-compact.svg`: `fc52b08e6f69f398588686992fa547d02852c6ddc64ac8d53394814d6d40b44a`

TermKitPlayer is a visual simulation. It does not load or play audio files.
