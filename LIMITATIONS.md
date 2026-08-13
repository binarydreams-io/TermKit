# Known Limitations

- SwiftTUI is a preview and does not provide stable 1.0 API guarantees.
- TUIkit 1.x source and binary compatibility are not supported.
- Windows and ConPTY are not supported.
- Terminal layout is left to right. SwiftTUI preserves RTL grapheme clusters but does not implement bidirectional paragraph layout.
- Movement resolves to terminal cells. Rotation, pixel geometry, and `scaleEffect` are not available.
- Matched geometry, keyframe animation, and phase animation are not part of the first release.
- The built-in syntax highlighter is intentionally subtle. Tree-sitter integration is not included.
- Synchronized output is enabled only after protocol proof. Other terminals use the ANSI fallback.
- Automated compatibility runs cover macOS and glibc Linux. Manual terminal smoke records are still required for each release candidate.
- The accepted performance baseline measures the in-process runtime pipeline. It does not measure terminal compositor latency or prove the absence of visual tearing.
- Legacy TUIkit targets remain in the repository for regression tests. They are not public SwiftTUI products.
