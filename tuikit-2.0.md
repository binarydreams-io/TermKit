# Swift TUI 2.0 Design

Date: 2026-08-13  
Status: approved design  
Source projects: TUIkit and OpenCode  
Targets: macOS and Linux  
Reference terminal: Ghostty

## 1. Purpose

This project creates a new Swift terminal UI framework derived from TUIkit. It keeps the declarative, SwiftUI-inspired programming model while replacing the rendering, runtime, animation, and component architecture.

The framework must render local animations at up to 60 frames per second in Ghostty, consume no periodic CPU while idle, and remain usable in Kitty, WezTerm, iTerm2, and modern xterm-compatible terminals. It will ship reusable controls and a separate component library for coding-agent applications.

The project does not preserve source compatibility with TUIkit 1.x. It will be published under a new name and will credit TUIkit and OpenCode according to their MIT licenses.

## 2. Goals

1. Provide a SwiftUI-inspired API for views, state, environment, layout, focus, and animations.
2. Render into a packed terminal-cell surface and present only changed cells.
3. Sustain 60 FPS for localized animations on a 120-by-40 terminal in Ghostty.
4. Avoid timer wakeups and terminal writes when the interface is idle.
5. Support macOS and glibc-based Linux with the same public Swift API.
6. Treat Ghostty as the reference implementation while degrading safely in other terminals.
7. Separate general-purpose framework modules from coding-agent models and components.
8. Reimplement OpenCode-inspired components as idiomatic Swift views with generic data models.
9. Preserve terminal state on errors, cancellation, signals, suspend, and normal exit.
10. Establish deterministic tests for rendering, layout, animation, and terminal output.

## 3. Non-goals for the first stable release

- Windows and ConPTY support.
- Binary or source compatibility with TUIkit 1.x.
- A graphical canvas or direct access to Ghostty's Metal/OpenGL renderer.
- Pixel-accurate movement, arbitrary rotation, or meaningful terminal `scaleEffect` behavior.
- Full SwiftUI API compatibility.
- A built-in networking, LLM, session persistence, or tool-execution layer.
- A required Tree-sitter or other native syntax-highlighting dependency.
- Matched geometry, keyframe animation, and phase animation in the initial animation release.
- Copying OpenCode branding, logo, product text, or SolidJS component structure.

## 4. Design principles

### 4.1 Declarative API, retained runtime

Application code declares value-type `View` values. The runtime reconciles those values into a persistent `ViewGraph` that owns identity, state slots, layout results, focus registrations, animation tracks, and render caches.

### 4.2 Work follows invalidation

The runtime distinguishes structural, layout, and paint changes. A color animation must not rebuild the full tree. A local size change must not lay out unrelated branches.

### 4.3 Terminal-native effects

The public API borrows SwiftUI concepts but exposes effects that make sense on a cell grid. Color, opacity, clipping, reveal, scroll, and short cell movement are supported. APIs that imply unavailable pixel geometry are omitted.

### 4.4 One source of animation time

A single scheduler drives cursors, spinners, notifications, transitions, and custom timelines. Components must not create private frame timers.

### 4.5 Generic core, optional agent UI

Framework modules do not import message, model, provider, tool, permission, or session types. `TUIAgentUI` adapts generic agent-facing models to reusable views.

### 4.6 Measured performance

Performance requirements are executable benchmarks. Changes that miss a frame or idle-wakeup budget fail the performance gate unless maintainers explicitly update the baseline with evidence.

## 5. Package architecture

```text
TUIFoundation
    ↓
TUITerminal → TUIRenderer
    ↓           ↓
TUIViewGraph → TUILayout
    ↓           ↓
TUIAnimation → TUIControls
                     ↓
                  TUIDesign
                     ↓
                  TUIRichText
                     ↓
                  TUIAgentUI
```

### 5.1 `TUIFoundation`

Owns platform-independent value types and low-level utilities:

- geometry: `CellPoint`, `CellSize`, `CellRect`, `EdgeInsets`;
- color: RGBA storage, semantic color resolution, linear-sRGB interpolation;
- time abstractions and deterministic clocks;
- packed cell identifiers and flags;
- grapheme and style interning;
- bounded buffers and diagnostics counters;
- shared locking primitives where actor isolation is inappropriate.

It does not import Foundation APIs that prevent Linux support unless those APIs have stable equivalents on both targets.

### 5.2 `TUITerminal`

Owns POSIX terminal I/O and protocols:

- raw mode and termios restoration;
- alternate-screen and cursor state;
- bracketed paste;
- SGR mouse input;
- resize and signal event delivery;
- synchronized-output detection;
- capability detection with bounded timeouts;
- robust buffered writes with `EINTR` and partial-write handling;
- suspend/resume;
- optional OSC 52 clipboard support.

### 5.3 `TUIRenderer`

Owns packed surfaces, painting, compositing, terminal diffing, ANSI encoding, and presentation. It does not know about application models or Swift property wrappers.

### 5.4 `TUIViewGraph`

Owns `View`, `ViewBuilder`, mounted nodes, structural identity, dynamic properties, state storage, environment, preferences, lifecycle, observation, and reconciliation.

### 5.5 `TUILayout`

Owns proposal/measure/place layout, stacks, frames, padding, alignment, overlay, clipping, lazy layout, scrolling, and hit-test geometry.

### 5.6 `TUIAnimation`

Owns transactions, interpolation, animation tracks, curves, springs, transitions, timelines, and reduced-motion policies.

### 5.7 `TUIControls`

Owns generic interactive controls: text, rich spans, button, text field/editor, list, selection, scroll view, dialog host, focus, keyboard commands, mouse actions, and accessibility-like semantic labels for tests and automation.

### 5.8 `TUIDesign`

Owns semantic themes and refined reusable presentation primitives. It contains no coding-agent concepts.

### 5.9 `TUIRichText`

Owns streaming Markdown presentation, code blocks, syntax-highlighter protocols, line numbers, unified-diff parsing, and diff presentation.

### 5.10 `TUIAgentUI`

Owns generic coding-agent components such as prompts, messages, reasoning disclosures, tool calls, permissions, questions, diagnostics, todos, and session chrome.

## 6. Runtime and view graph

### 6.1 Mounted nodes

Each persistent node stores:

- stable `NodeID` and structural identity;
- current view type and relevant value snapshot;
- child identities and ordering;
- dynamic-property slots;
- environment and preference dependencies;
- cached measurement and placed frame;
- paint bounds and z-order;
- focus and hit-test metadata;
- active animations;
- lifecycle state;
- dirty flags.

Keyed collections use explicit keys. Conditional branches include branch identity. Removed nodes may remain mounted as non-interactive presentation nodes until their removal transition completes.

### 6.2 Invalidation levels

`paint` invalidation marks visual output dirty without changing geometry. Examples include color, opacity, cursor phase, and spinner frame.

`layout` invalidation marks the node and affected ancestors for measurement and placement. Examples include padding, frame size, text wrapping width, and animated offset when it changes occupied geometry.

`structure` invalidation reevaluates `body`, reconciles children, and may imply layout and paint invalidation.

The runtime coalesces multiple requests before a frame. A stronger invalidation subsumes weaker invalidations for the same subtree.

### 6.3 Reconciliation

The reconciler compares type, structural identity, explicit key, and branch identity. It preserves state only when those identities match. It records lifecycle effects during traversal and commits them only after the final successful frame plan, avoiding side effects from discarded measure or correction passes.

### 6.4 Concurrency

The view graph, layout, paint planning, and terminal presentation run on one UI executor. State invalidation may originate on other tasks and enters the UI executor through a thread-safe event channel. The runtime never renders two frames concurrently.

The first release uses `@MainActor` for public view operations because that matches SwiftUI expectations and simplifies migration. Internal data structures may move to a dedicated custom executor later without changing the public API.

## 7. Rendering architecture

### 7.1 Packed cells

The root surface uses contiguous storage. A cell contains:

- `GraphemeID`;
- `StyleID`;
- display width;
- content flags such as empty, continuation, transparent, and explicit blank.

Grapheme and style tables retain stable IDs across frames so cell equality is an integer comparison. Tables live for the terminal session. When a configurable memory threshold is reached, the renderer rebuilds the tables from live surfaces and forces one full repaint.

### 7.2 Grapheme rules

The text shaper segments Swift strings into extended grapheme clusters and assigns terminal display width. Wide graphemes reserve continuation cells. Clipping, replacement, and overlay operations treat the entire grapheme atomically and never leave orphan continuation cells.

The framework preserves RTL grapheme clusters but does not implement a full bidirectional paragraph algorithm in the first release. Applications receive documented left-to-right terminal layout behavior.

### 7.3 Paint pass

Layout produces absolute frames. Primitive views paint into the root surface through a `PaintContext` that carries origin, clip stack, opacity stack, environment, and z-order.

The renderer clears previous paint bounds before repainting moved or removed nodes. It creates offscreen layers only when an operation needs independent opacity, clipping, overlay composition, or a custom canvas. Ordinary stacks and text do not allocate child framebuffers.

### 7.4 Damage tracking

Each paint operation reports damaged rectangles. The renderer unions overlapping damage and limits diff scanning to damaged rows and ranges. A full repaint occurs after resize, resume, capability changes, interner rebuild, or an explicitly invalidated terminal state.

### 7.5 Front/back diff

The presenter compares the completed surface with the previously presented surface. It groups changed cells into runs while respecting wide graphemes. A cost heuristic chooses between cursor movement and rewriting a short unchanged gap. The encoder tracks cursor position and active SGR state to avoid redundant control sequences.

### 7.6 Frame scheduler

The scheduler uses `ContinuousClock` and never queues stale frames.

- Idle applications have no frame timer.
- Ordinary invalidations coalesce into the next available frame.
- Active animations request a maximum cadence of 60 FPS.
- Slow effects may request lower cadence.
- `deltaTime` is monotonic and clamped after debugger pauses, suspend, or severe stalls.
- If a frame misses its budget, the next frame samples current animation time instead of replaying missed frames.

## 8. Terminal presentation

### 8.1 Capability policy

Ghostty defines reference behavior. The runtime probes synchronized output with a bounded asynchronous query. It also uses environment and terminfo information as hints, never as the sole proof for a protocol that can be queried.

Kitty, WezTerm, iTerm2, and xterm-compatible terminals use the same cell diff. Unsupported capabilities disable only the related optimization or input feature.

### 8.2 Synchronized output

On supported terminals, every presented frame is encoded as one byte buffer:

```text
CSI ? 2026 h
<cursor, SGR, and changed-cell payload>
CSI ? 2026 l
```

The presenter performs one logical write operation for this buffer. The syscall wrapper retries interruptions and completes partial writes. A permanent I/O error stops the runtime and restores terminal modes.

### 8.3 Lifecycle safety

`TerminalSession` owns raw mode, alternate screen, cursor visibility, paste mode, mouse mode, and capability state. It restores them during normal exit, thrown errors, task cancellation, termination signals, and suspend/resume.

Signal handlers perform only async-signal-safe notification through a self-pipe or equivalent event source. Cleanup runs in normal runtime code.

### 8.4 Input and hit testing

The input parser supports UTF-8 keys, escape sequences, bracketed paste, SGR mouse events, focus events, and optional Kitty keyboard enhancements. Layout nodes publish hit-test rectangles. The runtime dispatches input from the topmost eligible node and respects clipping, modal focus scopes, disabled state, and removal transitions.

## 9. Animation model

### 9.1 Public API

The first animation release includes:

- `Animation`;
- `Transaction`;
- `withAnimation`;
- `.animation(_:value:)`;
- `Animatable`;
- `VectorArithmetic`;
- `AnimatablePair`;
- `AnimatableModifier`;
- `AnyTransition`;
- `TimelineView`.

Supported curves include linear, ease-in, ease-out, ease-in-out, cubic Bézier, and spring.

### 9.2 Transactions

`withAnimation` establishes a task-local transaction. A state mutation carries that transaction with its invalidation. Mounted nodes compare previous and next animatable values and create tracks for changed properties.

`.animation(_:value:)` injects an animation only when its watched value changes. Transactions also carry reduced-motion behavior and optional completion callbacks.

### 9.3 Animation tracks

The runtime keys a track by `NodeID` and property key. A track stores start, target, sampled value, timing, curve, invalidation class, and completion policy.

When a property changes during an active animation, the runtime samples its current value and retargets from that value. It does not jump back to the previous endpoint.

### 9.4 Supported effects

The initial implementation animates:

- foreground, background, and border colors;
- composited opacity;
- offset;
- frame dimensions;
- padding and spacing;
- clipping and reveal;
- selection and focus highlights;
- scroll position;
- insertion and removal.

Opacity resolves against the actual lower layer. Colors interpolate in linear sRGB. Spatial values remain floating point in the animation engine and quantize to terminal cells during layout or paint.

The framework omits `scaleEffect` from the first API. It provides `.reveal`, `.wipe`, `.move`, `.opacity`, and `.symbolFrames` instead.

### 9.5 Transitions

Insertion transitions mount the destination node and animate from its transition start state. Removal transitions detach input and focus immediately, retain presentation state, and destroy the node after completion.

Transitions may be combined or asymmetric. The default component transitions last 120 to 220 milliseconds.

### 9.6 Timeline schedules

`TimelineView` supports animation, periodic, and explicit schedules. Cursors, spinners, notifications, and custom canvases use these schedules instead of private tasks.

### 9.7 Motion policy

The environment exposes `animationsEnabled` and `reduceMotion`. Disabled animations render their final state. Reduced motion removes spatial movement while allowing short color changes where appropriate. Every indefinite animation has a static fallback.

## 10. Design system

### 10.1 Semantic theme

`SemanticTheme` defines light and dark values for:

- primary, secondary, and accent;
- error, warning, success, and info;
- text and muted text;
- background, panel, element, and menu;
- regular, active, and subtle borders;
- diff colors and backgrounds;
- Markdown and syntax roles.

The resolver supports semantic references and validates cycles. It computes readable selected text when a theme omits an explicit value. Terminals without true color receive an ANSI-256 or ANSI-16 approximation.

### 10.2 Visual rules

- Layout uses whitespace before adding borders.
- A surface uses at most one strong accent rail unless its semantics require a full border.
- Background, panel, and element form the primary depth hierarchy.
- Accent color identifies focus and action; body content uses text colors.
- Metadata uses muted text and does not compete with primary content.
- Components simplify metadata before truncating primary content on narrow terminals.
- Indefinite animation is limited to active work.

### 10.3 Reusable primitives

`Surface` provides background, padding, clipping, and optional elevation token.

`AccentRail` draws one semantic vertical edge. `BottomCap` closes an element with a half-block treatment where the terminal supports the glyph.

`SelectionRow` presents selected, current, disabled, and hovered states without retro checkbox or full-box decoration.

`MetadataLine` lays out muted fields with semantic separators and progressive hiding rules.

`KeyHint` pairs a normalized shortcut with a muted label.

`StatusPill` presents compact semantic state without mandatory ASCII brackets.

`ActivityIndicator` uses timeline-driven frames and renders a static ellipsis when motion is disabled.

`OverlayHost` owns z-order, focus trapping, dismissal, and focus restoration.

`DialogSurface` provides a translucent backdrop, centered panel, terminal-aware maximum width, and no mandatory outer border. Standard widths are 60, 88, and 116 cells.

`Toast` appears near the top-right edge, uses vertical accent rails, wraps at a bounded width, and leaves through a short fade or static removal under reduced motion.

`SelectList` owns filtering, grouping, selection, current-value markers, details, footer actions, keyboard navigation, mouse navigation, and scroll-to-selection.

`CommandPalette` adapts command data into `SelectList` and dispatches selected commands. It does not duplicate filtering or selection logic.

## 11. Rich text and diff

### 11.1 Styled text

`StyledText` stores semantic spans rather than ANSI strings. Layout wraps spans while preserving grapheme boundaries and links. The paint pass resolves semantic roles through the current theme.

### 11.2 Markdown

The built-in streaming Markdown subset supports headings, emphasis, strong text, links, lists, block quotes, inline code, fenced code, horizontal rules, and tables. Incomplete streaming constructs render conservatively and reparse only the affected tail region.

### 11.3 Syntax highlighting

`SyntaxHighlighter` accepts text, language, and changed ranges and returns semantic spans. The default implementation provides plain and subtle pure-Swift highlighting. Optional Tree-sitter integration may ship in a separate package later. Code remains readable with no highlighter.

### 11.4 Diff

The pure-Swift unified-diff parser produces files, hunks, and lines with old/new line numbers. `DiffView` uses unified layout on narrow terminals and may use side-by-side layout above 120 columns. It supports wrapping policy, semantic backgrounds, line-number gutters, diagnostics, and selectable text.

## 12. Agent UI component specifications

All components accept generic presentation models and closures. They do not call network clients, execute tools, or mutate session stores directly.

### 12.1 `AgentPrompt`

Inputs:

- `Binding<PromptDocument>`;
- mode, placeholder, enabled/busy state;
- agent/model/provider/variant metadata;
- submit, cancel, paste, and attachment actions;
- optional leading/trailing accessory views.

Presentation:

- element background;
- two-cell horizontal padding and one-row top padding;
- one semantic left rail and a bottom half-block cap;
- default maximum width `max(75, floor(terminalWidth * 0.7))`;
- muted metadata row below the editor;
- status output outside the editable surface.

Behavior:

- multiline editing and selection;
- submit command independent of newline insertion;
- bracketed paste and large-paste handling;
- focus retention across metadata updates;
- metadata fade-in of 120 to 180 milliseconds;
- static metadata when animations are disabled.

### 12.2 `PromptAutocomplete`

An anchored overlay presents commands, files, agents, and symbols using `SelectList`. Providers return typed `PromptSuggestion` values. Selecting an item returns a semantic `PromptInsertion`; the prompt editor owns document mutation and cursor placement.

### 12.3 `AttachmentChip`

The chip contains one semantic segment for kind and one muted segment for name. It supports file, directory, image, and contextual attachment types, plus focus and removal actions.

### 12.4 `ConversationViewport`

The viewport lazily lays out visible transcript nodes, preserves the visual anchor when older content is prepended, and supports an anchored-bottom mode. New output keeps the bottom pinned only when the user has not scrolled away. Submission may explicitly request scroll-to-bottom.

### 12.5 `UserMessageCard`

The card uses the agent color for its left rail, a panel background, two-cell horizontal padding, one-row vertical padding, and optional hover elevation. It presents message text, attachments, timestamp, and queued state. Queued state uses a semantic badge rather than changing body readability.

### 12.6 `AssistantMessage`

The assistant presentation remains visually open rather than enclosing the full response in a box. It composes Markdown, reasoning, tool activity, diagnostics, and footer metadata. The footer may show agent mode, model, duration, and interruption state.

### 12.7 `ReasoningDisclosure`

Running reasoning shows an activity indicator and a short summary. Completed reasoning shows a `Thought` label, optional summary, and duration. Minimal mode keeps a single stable header row and reveals the body on demand without changing the collapsed height during streaming.

### 12.8 `ToolCallRow`

The row reserves a fixed icon column and gives the label the remaining width. It supports pending, running, completed, denied, and failed states. Failed state may reveal an error body. Denied state uses muted or struck presentation while preserving legibility.

### 12.9 `ToolResultPanel`

The panel uses a left rail, panel background, muted title, and content body. It appears only when output benefits from block presentation. Short successful tool activity stays in `ToolCallRow`.

### 12.10 `ShellResult`

The component presents command, optional working directory, streaming output, running state, failure state, and collapsed output. The default collapsed limit depends on viewport width and line count. Expansion preserves text selection and scroll anchoring.

### 12.11 `CodeBlock`

The component supports language, optional title, optional line numbers, selection, copy action, wrap policy, and syntax highlighting through `SyntaxHighlighter`.

### 12.12 `DiffView`

The component accepts a parsed diff model or unified-diff text. It selects unified or side-by-side layout from available width and user policy. Added, removed, context, hunk, and line-number regions use semantic theme roles.

### 12.13 `DiagnosticsList`

The component presents severity, path, line, column, and message. Inline mode summarizes diagnostics under a related tool result. Block mode supports longer lists and navigation actions.

### 12.14 `PermissionPrompt`

The prompt presents the requested action, affected resources, risk emphasis, and available choices. It traps focus and requires an explicit user action. Destructive or persistent choices receive stronger semantic emphasis than temporary approval.

### 12.15 `QuestionPrompt`

The prompt supports one or more questions, single or multiple selection, custom text, validation, and step navigation. The model owns answer values; the view owns temporary focus and selection state.

### 12.16 `TodoItem`

The item supports pending, in-progress, completed, and cancelled states with semantic symbols. Completed text becomes muted; in-progress state may animate only its activity symbol.

### 12.17 `SessionSidebar`

The sidebar composes generic sections for metadata, files, language services, integrations, and todos. Wide layouts place it in a fixed column. Narrow layouts present it as a dismissible trailing overlay.

### 12.18 `AgentStatusFooter`

The footer uses one row where possible and progressively hides low-priority fields. It may present model, agent, duration, context usage, connection state, and keyboard hints.

### 12.19 `BackgroundPulse`

This optional `Canvas` component renders a precomputed radial or logo-adjacent color pulse at 30 FPS. It caches geometry and reusable frames, obeys reduced motion, and never becomes a dependency of the base theme or prompt.

## 13. Error handling and diagnostics

The runtime exposes typed errors for terminal setup, terminal write, capability timeout where a capability is mandatory, invalid theme data, and malformed rich-text input where recovery is impossible.

Optional capability failure selects a fallback and records diagnostics. Malformed Markdown or diff content renders as plain text with an attached diagnostic rather than terminating the app.

Debug builds validate surface bounds, wide-cell invariants, clip stacks, layout finiteness, duplicate identities, state mutation during body evaluation, and unbalanced terminal transactions.

`RenderStats` records frame duration, reconciliation time, layout time, paint time, diff time, encoded bytes, damaged cells, write duration, missed budgets, active animations, and interner memory.

## 14. Testing strategy

### 14.1 Unit tests

- Surface tests cover graphemes, combining marks, emoji, CJK, continuation cells, clipping, clearing, and composition.
- Diff tests verify that applying encoded operations to the previous semantic screen produces the next screen.
- ANSI tests verify cursor movement, SGR minimization, reset behavior, and synchronized-output framing.
- Animation tests use a deterministic clock for curves, springs, interruption, cancellation, completion, and reduced motion.
- View-graph tests cover identity, conditional branches, keyed collections, lifecycle, preferences, and removal transitions.
- Layout tests cover proposals, measurement, placement, dirty propagation, lazy visibility, and scroll anchoring.
- Focus tests cover overlays, removal, keyboard commands, mouse hit testing, and restoration.

### 14.2 Snapshot tests

Component snapshots store semantic cell grids for dark and light themes at widths 40, 80, 120, and 180. Interactive components include snapshots for idle, focused, hovered, selected, disabled, busy, error, and reduced-motion states where applicable.

Byte snapshots remain limited to terminal-presenter tests.

### 14.3 Property and fuzz tests

Random Unicode surfaces, arbitrary resize sequences, overlapping layers, and generated previous/next frames validate renderer invariants. The diff invariant is: replaying presenter operations against the previous semantic terminal state produces the next state.

### 14.4 PTY integration tests

macOS and Linux tests exercise raw mode, bracketed paste, resize, signals, suspend/resume, mouse sequences, cancellation, and cleanup. Tests run inside a pseudo-terminal and verify final terminal-restoration sequences.

### 14.5 Real-terminal compatibility

Ghostty runs the full manual and automated performance suite. Kitty, WezTerm, iTerm2, and xterm-compatible terminals run smoke scenarios for startup, resize, input, color, synchronized-output fallback, and cleanup.

## 15. Performance gates

Release-mode benchmarks enforce:

- localized 120-by-40 animation at 60 FPS with p95 frame time below 8 milliseconds;
- 200-by-60 full repaint below 16.67 milliseconds on the reference machine;
- no paint pass and no terminal write for an unchanged frame;
- no periodic wakeup while idle;
- one logical terminal write per ordinary frame;
- lazy transcript behavior with 10,000 items;
- local invalidation for one tool row without transcript-wide layout or paint;
- bounded interner memory followed by controlled rebuild;
- no unbounded frame queue under sustained state updates.

The repository records the reference hardware, Swift version, build flags, terminal version, and benchmark command beside each accepted baseline.

## 16. Development sequence

The project proceeds through runnable vertical slices:

1. Capture the TUIkit 1.x behavior and performance baseline; add license and origin records.
2. Establish package boundaries and foundation types.
3. Implement terminal session ownership, signals, capabilities, and buffered transport.
4. Implement packed surfaces, paint context, front/back diff, ANSI encoding, and Ghostty synchronized output.
5. Migrate view identity, state, environment, reconciliation, and lifecycle into the retained graph.
6. Migrate and optimize layout, lazy layout, scrolling, hit testing, and focus.
7. Implement transactions, animation tracks, timelines, and transitions.
8. Rebuild universal controls on the new graph and renderer.
9. Implement the semantic design system and reusable refined primitives.
10. Implement rich text, Markdown, code, and diff.
11. Implement agent UI components in dependency order.
12. Run performance, compatibility, accessibility-like semantics, documentation, and release hardening.

Each stage ends with a runnable showcase, passing tests, benchmark results, and a written statement of remaining limitations. The team may adapt an old TUIkit test or replace it with a stronger invariant test. It must not delete failing tests without recording the replacement invariant.

## 17. Release policy

Version `0.1` begins after the new renderer, view graph, basic animations, and core controls work together on macOS and Linux. Agent UI components may enter during preview releases. Version `1.0` requires stable public APIs, documented terminal fallbacks, passing compatibility suites, and accepted performance baselines.

The project uses semantic versioning after `1.0`. Preview releases may change public APIs but must publish migration notes.

## 18. Attribution and licensing

The repository includes:

- the new project's license;
- `NOTICE.md`;
- the complete TUIkit MIT notice;
- the complete OpenCode MIT notice;
- `CREDITS.md` describing both sources;
- source comments on files that adapt substantial algorithms;
- `docs/design-origin.md` mapping reused, adapted, and original work.

The project does not use TUIkit or OpenCode branding as its own. It does not copy OpenCode logos or product language. Components use generic models and independent public names.

## 19. Acceptance criteria

The design is complete when the implementation can demonstrate all of the following:

1. A Swift application declares views and animations through the new public API.
2. Ghostty displays localized animations at 60 FPS without tearing.
3. Idle applications produce no periodic frames.
4. The renderer updates only damaged terminal cells and performs one logical write per frame.
5. macOS and Linux pass the same semantic test suite.
6. A terminal without synchronized output renders correctly through fallback presentation.
7. State, lifecycle, focus, and removal transitions remain correct under rapid updates.
8. The component showcase includes prompt, command palette, messages, reasoning, tools, diff, permissions, questions, toast, and sidebar.
9. Reduced-motion and disabled-animation modes produce stable static interfaces.
10. The repository carries complete attribution for TUIkit and OpenCode.
