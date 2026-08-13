# Terminal Compatibility

## Reference Terminal

Ghostty defines reference behavior. The accepted local baseline used Ghostty 1.3.1.

## Capability Policy

Environment variables provide bounded hints. They do not prove synchronized output. The capability probe accepts a bounded response and timeout.

If synchronized output is proven, `TerminalSession` wraps each frame in the protocol envelope. If the probe fails or the terminal does not support the protocol, the presenter sends the same ANSI cell diff without the envelope.

Optional Kitty keyboard input is disabled unless the application enables it. Bracketed paste, SGR mouse input, focus events, OSC 52 limits, and UTF-8 input have typed parser behavior.

## Tested Paths

Automated macOS and Linux suites cover:

- raw mode and restoration;
- alternate screen, cursor, paste, mouse, and focus modes;
- partial writes and `EINTR`;
- PTY input, bracketed paste, SGR mouse, and resize;
- signal delivery, termination cleanup, suspend, and resume;
- cancellation and thrown-error cleanup;
- synchronized-output fallback.

## Release Smoke Matrix

Run startup, resize, keyboard input, paste, mouse, color, fallback presentation, suspend/resume, and cleanup in:

- Ghostty;
- Kitty;
- WezTerm;
- iTerm2;
- a modern xterm-compatible terminal.

Record the terminal version and result in the release notes. A missing manual record does not invalidate the deterministic ANSI fallback tests, but it blocks a 1.0 compatibility claim.
