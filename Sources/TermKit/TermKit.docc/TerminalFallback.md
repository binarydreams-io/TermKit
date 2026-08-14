# Terminal Fallback

Learn how TermKit preserves output across different terminal capabilities.

TermKit preserves frame output when optional terminal protocols are unavailable.

## Capability policy

``TerminalCapabilityDetector`` reads bounded environment and terminfo hints without terminal I/O. Environment values do not prove support for queryable protocols.

When support for synchronized output is unknown, ``Runtime`` performs a bounded probe. A failed or unsupported probe records a diagnostic.

When the terminal confirms support, ``FramePresenter`` wraps each frame in a synchronized-output envelope. Otherwise, it sends the same ANSI cell diff without that envelope.

Color detection also falls back from true color to ANSI 256, ANSI 16, or monochrome according to available hints.
Monochrome image output uses block glyphs and emits no color SGR sequences.
