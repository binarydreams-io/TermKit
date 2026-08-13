# SwiftTUI Provenance

SwiftTUI is a new terminal UI framework derived from TUIkit and informed by OpenCode interaction patterns.

## TUIkit Source

- Repository: `https://github.com/phranck/TUIkit.git`
- Fork base: `9f9aaed5ba332adaa678f07744395b9de812bbf0`
- Imported version: `0.6.0+rigyard.1.upstream.9f9aaed`
- License: MIT

The repository retains the imported TUIkit sources as internal regression targets. The Swift package does not publish the legacy TUIkit products.

## OpenCode Source

- Repository: `https://github.com/anomalyco/opencode`
- Reference branch when the design was approved: `dev`
- License: MIT

SwiftTUI does not copy OpenCode branding, logos, product text, network clients, session stores, or tool execution. `TUIAgentUI` adapts general interaction concepts to independent Swift models and semantic cell renderers.

## SwiftTUI Delta

The SwiftTUI implementation adds:

- packed terminal-cell surfaces and stable interners;
- front/back cell diff and ANSI state tracking;
- retained graph reconciliation with staged lifecycle commits;
- proposal-based layout and lazy viewport planning;
- transaction-based animation and one frame scheduler;
- semantic themes, rich text, and coding-agent components;
- an async POSIX runtime with self-pipe signal delivery;
- deterministic, PTY, property, snapshot, and performance tests.

See `docs/design-origin.md` for the source classification of each subsystem.

## Verification State

The current workspace has no Git `HEAD`. Benchmark records therefore use `uncommitted` as the revision. Replace this value with a commit identifier when the project receives its first commit.
