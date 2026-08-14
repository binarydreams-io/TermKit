# Terminal Compatibility

TermKit requires a UTF-8 terminal on macOS 14+ or glibc Linux.

## Capabilities

TermKit combines environment hints, bounded terminfo inspection, and optional synchronized-output probing.
A failed optional probe disables synchronized output without disabling ordinary presentation.

| Capability | Behavior |
| --- | --- |
| Truecolor | Emits 24-bit foreground and background colors |
| ANSI-256 | Quantizes colors to the 256-color palette |
| ANSI-16 | Quantizes colors to the standard 16-color palette |
| Monochrome | Emits glyphs and attributes without color SGR codes |
| Synchronized output | Uses one synchronized frame only after terminal proof |
| Mouse input | Uses SGR coordinates when the terminal supports them |
| Bracketed paste | Preserves pasted text as one bounded input event |

Ghostty is the reference terminal. Kitty, WezTerm, iTerm2, and modern xterm-compatible terminals use the same fallback renderer.

Terminal compositors, fonts, and remote sessions can change observed latency and glyph appearance.
Run the PTY tests and inspect a real terminal before release.
