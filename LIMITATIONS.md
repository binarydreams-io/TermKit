# Limitations

- TermKit 2.1.0 includes source-breaking changes from earlier development versions.
- TUIkit 1.x source and binary compatibility are not supported.
- Windows and ConPTY are not supported.
- Layout is left to right. TermKit preserves RTL graphemes but does not implement bidirectional paragraph layout.
- Network image loading and animated PNG are not supported.
- TermKitPlayer simulates playback and does not produce audio.
- The upstream image decoders are not described as hardened.
- The clean codec releases omit strict checks for reserved PNG filters, JPEG DNL height, and JPEG entropy padding.
- Tree-sitter parsing is not included. Syntax highlighting uses the built-in lightweight highlighter.
- Optional synchronized-output probing can fall back to ordinary buffered ANSI presentation.
- Hosted-runner timing is diagnostic evidence, not the only performance gate.
