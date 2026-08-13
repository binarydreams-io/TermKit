# Development Stage Evidence

This ledger reconstructs evidence from the current imported worktree. The worktree has no Git `HEAD`, so this file does not claim historical commit boundaries.

| Stage | Current artifact | Executable evidence | Test or gate | Remaining limitation |
| --- | --- | --- | --- | --- |
| 1. Baseline and origin | `PROVENANCE.md`, `NOTICE.md`, `CREDITS.md`, `docs/design-origin.md` | Legacy `TUIkitExample` remains an internal regression target | Legacy tests and API compatibility tool | Historical commits are unavailable in this import |
| 2. Package and foundation | `Package.swift`, `Sources/TUIFoundation` | `SwiftTUIShowcase` links the separated products | `TUIFoundationTests`, boundary validator | None for the preview scope |
| 3. Terminal ownership | `Sources/TUITerminal` | Showcase creates one `TerminalSession` | Terminal unit and PTY tests | Real-terminal matrix remains manual |
| 4. Packed renderer | `Sources/TUIRenderer`, `FramePresenter` | Showcase presents packed-cell diffs | Renderer property tests and one-write tests | Visual tearing requires terminal observation |
| 5. Retained graph | `Sources/TUIViewGraph` | Declarative runtime mounts retained nodes | Identity, lifecycle, rollback, and state tests | None for the preview scope |
| 6. Layout and interaction | `Sources/TUILayout`, runtime hit testing | Showcase uses measured terminal geometry | Layout, focus, modal, mouse, and lazy viewport tests | Bidirectional paragraph layout is not included |
| 7. Animation | `Sources/TUIAnimation` | Runtime drives one shared scheduler | Animation, transition, timeline, reduced-motion, and transaction tests | Matched geometry and keyframes are not included |
| 8. Universal controls | `Sources/TUIControls` | Buttons and prompt input run through declarative dispatch | Control rendering, editor, focus, and command tests | None for the preview scope |
| 9. Design system | `Sources/TUIDesign` | Showcase renders semantic themes and primitives | Theme, primitive, overlay, and snapshot tests | Terminal palettes can approximate colors |
| 10. Rich content | `Sources/TUIRichText` | Showcase renders Markdown, code, and diff content | Parser, layout, syntax, diff, and fallback tests | Tree-sitter is not included |
| 11. Agent UI | `Sources/TUIAgentUI` | Showcase includes every required agent component | Component, semantic snapshot, pulse, and transcript tests | Network, tool execution, and session stores stay in applications |
| 12. Release hardening | `scripts/quality-gate.sh`, CI, release docs | PTY smoke starts and exits the real showcase | Strict build, full tests, DocC, consumer, Linux, and performance gates | Manual terminal records are required for a release candidate |

The current accepted benchmark is in `docs/benchmarks.md`. The current product limitations are in `LIMITATIONS.md`.
