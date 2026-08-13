# Terminal Fallback

Understand how SwiftTUI presents frames when optional terminal protocols are unavailable.

## Capability Policy

Ghostty defines reference behavior. SwiftTUI uses bounded capability probes and treats environment variables as hints, not proof.

When the terminal proves synchronized-output support, the session wraps each frame in the protocol envelope. Otherwise, the presenter sends the same ANSI cell diff without the envelope.

The fallback preserves rendering correctness in Kitty, WezTerm, iTerm2, and modern xterm-compatible terminals.
