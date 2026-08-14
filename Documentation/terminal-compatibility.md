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
| Mouse input | Uses SGR coordinates and button-motion events when the terminal supports them |
| Bracketed paste | Preserves pasted text as one bounded input event |
| Kitty keyboard | Parses alternate and base-layout keys when both session and parser support are enabled |
| OSC 52 | Reports conservative support from known direct-terminal environment hints |
| Terminal title | Uses OSC 2 and restores a saved title when the session exits |

Ghostty is the reference terminal. Kitty, WezTerm, iTerm2, and modern xterm-compatible terminals use the same fallback renderer.

OSC 52 detection is a heuristic, not a protocol probe. TermKit reports support only for known direct terminals.
It reports no support for `TERM=dumb`, tmux sessions, generic xterm values, and unknown environments.
An application must also set `allowsOSC52` before TermKit writes clipboard data.

Kitty base-layout data takes priority during hotkey matching. Without that data, TermKit maps both cases of the JCUKEN layout.
ASCII digits and punctuation pass through unchanged. Focused text controls still receive the original text.

Terminal compositors, fonts, and remote sessions can change observed latency and glyph appearance.
Run the PTY tests and inspect a real terminal before release.
