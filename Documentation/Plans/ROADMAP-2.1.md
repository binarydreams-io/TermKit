# TermKit Roadmap 2.1

- Roadmap version: `2.1`
- Target library release: `0.1.0`
- Status: Approved for implementation
- Canonical repository: `https://github.com/binarydreams-io/termkit`
- Publisher: Binary Dreams, LLC

## Objective

Transform the current SwiftTUI and TUIkit repository into a release-grade Swift library named TermKit, published by Binary Dreams, LLC.

Complete the work end to end. Use phased conventional commits. Do not push, create tags, or publish releases.

## Approved Decisions

| Area | Decision |
| --- | --- |
| Package name | `TermKit` |
| Library product | One product named `TermKit` |
| Library target | One package-owned target named `TermKit` |
| Tests | One root test target named `TermKitTests` |
| Examples | Separate package under `Examples/` |
| Legacy TUIkit | Delete legacy sources, tests, example, vendor targets, and parity tooling |
| Agent UI | Keep, audit, document, and attribute correctly |
| Version | `0.1.0` |
| Toolchain | Swift 6.3.3 minimum |
| Platforms | macOS 14 or later and glibc Linux |
| License | Standard MIT License |
| Copyright | `Copyright (c) 2026 Binary Dreams, LLC` |
| Attribution request | Recommend a public TermKit link, but do not make it an extra license condition |
| TUIkit credit | Preserve `https://github.com/phranck/TUIkit` and its MIT notice |
| OpenTUI credit | Credit `https://github.com/anomalyco/opentui` for directly studied styles and component ideas |
| OpenCode | Remove OpenCode attribution and claims |
| Image dependencies | Clean upstream `swift-png 4.5.1` and `swift-jpeg 2.1.0` |
| Audio | Visual playback simulation only |
| `Surface` collision | Keep renderer `Surface`; rename the design view to `SurfaceView` |
| Toast collision | Use one `ToastKind` with `info`, `success`, `warning`, and `error` |
| Runtime names | Rename `TUIRuntime*` to `Runtime`, `RuntimeError`, and `RuntimeDiagnostic` |
| Duration name | Rename `TUIDuration` to `TimeSpan` |
| Compatibility shims | Do not add old module or API aliases |
| Name collision | Keep `TermKit`; do not add a disclaimer about the other Swift package |
| Commits | Create separate conventional commits for coherent phases |

## Target Structure

```text
TermKit/
|-- Package.swift
|-- Package.resolved
|-- Sources/
|   `-- TermKit/
|       |-- Foundation/
|       |-- Terminal/
|       |-- Rendering/
|       |-- ViewGraph/
|       |-- Layout/
|       |-- Animation/
|       |-- Controls/
|       |-- Design/
|       |-- RichText/
|       |-- AgentUI/
|       |-- Runtime/
|       |-- Image/
|       |-- TermKit.swift
|       |-- VERSION
|       `-- TermKit.docc/
|-- Tests/
|   `-- TermKitTests/
|       |-- Foundation/
|       |-- Terminal/
|       |-- Rendering/
|       |-- ViewGraph/
|       |-- Layout/
|       |-- Animation/
|       |-- Controls/
|       |-- Design/
|       |-- RichText/
|       |-- AgentUI/
|       |-- Runtime/
|       |-- Image/
|       |-- Integration/
|       |-- Performance/
|       `-- Snapshots/
|-- Examples/
|   |-- Package.swift
|   |-- Sources/TermKitPlayer/
|   |-- Sources/TermKitPlayerPTYHarness/
|   |-- Tests/TermKitPlayerTests/
|   `-- Assets/
|-- Documentation/
|-- Licenses/
|-- scripts/
`-- .github/
```

The root manifest must contain exactly:

- One library product named `TermKit`.
- One regular package-owned target named `TermKit`.
- One test target named `TermKitTests`.
- Exact direct dependencies on `swift-png 4.5.1` and `swift-jpeg 2.1.0`.
- No executable products.
- No legacy or compatibility targets.

External dependency targets do not violate the one-target requirement.

## Phase 0: Establish the Baseline

1. Inspect `git status`, the current diff, and recent commits.
2. Preserve unrelated user changes.
3. Use fresh scratch paths. Do not trust the existing `.build`, which contains caches from the old TUIkit path.
4. Record all current modern SwiftTUI tests before deleting legacy tests.
5. Record the 13 current performance tests and their behavioral contracts.
6. Generate a symbol graph for the current modern API.
7. Record semantic snapshots and PTY smoke behavior.
8. Resolve `swift-png 4.5.1` and `swift-jpeg 2.1.0` in a temporary Swift 6.3.3 package.
9. Record the complete resolved dependency graph and licenses.

Expected baseline evidence:

- Approximately 465 modern test identifiers.
- Approximately 1,400 legacy TUIkit tests marked for intentional deletion.
- 93 modern Swift source files marked for migration.
- 13 performance tests marked for preservation.
- No unexplained loss of modern test coverage.

## Phase 1: Remove Legacy Infrastructure

Delete these repository areas:

```text
Sources/TUIkit
Sources/TUIkitCore
Sources/TUIkitStyling
Sources/TUIkitView
Sources/TUIkitImage
Sources/TUIkitExample
Tests/TUIkit*
Vendor/
Tools/APICompatibility/
.claude/
tuikit-2.0.md
```

Delete scripts and fixtures that only support:

- TUIkit versus SwiftUI API parity.
- Compatibility manifests.
- API snapshot assembly.
- External TUIkit issue-owner validation.
- Legacy module boundaries.
- README test-count badges.
- Old Astro documentation.
- Old fonts and generated site plans.

Delete stale and unlicensed assets:

```text
.github/assets/github-banner.png
.github/assets/spotnik_1.png
Sources/TUIkitExample/Resources/demo-image.jpg
Scripts/fonts/
```

Before deletion, preserve the useful image-decoding design knowledge in provenance notes:

- Signature detection.
- Checked dimension and allocation arithmetic.
- PNG metadata inspection.
- JPEG frame and sampling inspection.
- Bounded file reads.
- Pixel-to-cell sizing formulas.

Do not retain the old TUIkit architecture or its public types.

Acceptance criteria:

- No `TUIkit*` targets remain.
- No legacy codecs remain vendored.
- No API compatibility package remains.
- Modern sources still build before module consolidation.
- Legal notices no longer refer to removed directories.

Suggested commit:

```text
chore(repo): remove legacy TUIkit infrastructure
```

## Phase 2: Consolidate the Package

1. Set `swift-tools-version` to 6.3.
2. Set `.swift-version` and CI to Swift 6.3.3.
3. Move all modern source files into `Sources/TermKit/` by subsystem.
4. Remove old internal module imports.
5. Remove all `@_exported import` declarations.
6. Remove obsolete module-qualified references such as `TUIRenderer.Surface`.
7. Replace the umbrella target with the real `TermKit` implementation target.
8. Move `VERSION` to `Sources/TermKit/VERSION`.
9. Rename `SwiftTUIRelease` to `TermKitRelease`.
10. Rename `SWIFTTUI_*` environment variables to `TERMKIT_*`.
11. Rename `Surface` in the design subsystem to `SurfaceView`.
12. Merge both toast enums into one `ToastKind`.
13. Rename `TUIDuration` to `TimeSpan`.
14. Rename `TUIRuntime` to `Runtime`.
15. Rename `TUIRuntimeError` to `RuntimeError`.
16. Rename `TUIRuntimeDiagnostic` to `RuntimeDiagnostic`.
17. Audit identities built with `String(reflecting:)`, because the module-name change alters their values.
18. Do not add deprecated aliases for old modules or names.

Merge all modern root tests into `Tests/TermKitTests/`.

Resolve helper and suite-name collisions that were previously isolated by test targets. Keep subsystem directories for navigation, but use only one SwiftPM test target.

Acceptance criteria:

- `Sources/` contains only `Sources/TermKit`.
- Root `Tests/` contains only `Tests/TermKitTests`.
- `swift package describe` reports one library product, one regular target, and one test target.
- No source imports `SwiftTUI`, `TUIFoundation`, `TUIRenderer`, or another removed project module.
- Debug and release builds pass with warnings as errors.
- All preserved modern tests pass.

Suggested commit:

```text
refactor(package): consolidate sources into TermKit
```

## Phase 3: Audit the Public API

Perform a complete Swift API Design Guidelines review.

1. Generate a complete list of public declarations.
2. Review every public name at its call site.
3. Reduce accidental `public` and `package` declarations to `internal` or `private`.
4. Prevent PNG and JPEG dependency types from appearing in public signatures.
5. Use `internal import PNG` and `internal import JPEG`.
6. Add DocC comments to every supported public declaration.
7. Add complexity notes to nonconstant computed properties.
8. Audit generic constraints, argument labels, default values, and Boolean names.
9. Audit Swift 6.3 strict-concurrency behavior.
10. Remove unnecessary `@unchecked Sendable`.
11. Review actor isolation and cancellation in runtime and terminal code.
12. Keep Agent UI public, but remove application-specific or accidental implementation details.
13. Replace module-boundary assumptions with directory structure and review rules.
14. Add public consumer tests that use only `import TermKit`.
15. Add negative compile checks for removed module names.

Acceptance criteria:

- Public documentation builds without warnings.
- No old product or module name appears in a public declaration.
- A fresh consumer imports only `TermKit`.
- Public signatures expose no `PNG`, `JPEG`, `LZ77`, or `CRC` types.
- Symbol-graph inspection finds no accidental implementation API.
- Strict-concurrency compilation passes on macOS and Linux.

Suggested commit:

```text
refactor(api): refine the public TermKit API
```

## Phase 4: Add Raster Image Support

Use exact upstream dependencies:

```swift
.package(
    url: "https://github.com/tayloraswift/swift-png",
    exact: "4.5.1"
),
.package(
    url: "https://github.com/tayloraswift/swift-jpeg",
    exact: "2.1.0"
)
```

Implement a small public API with names validated during the API review:

```swift
public struct RGBA8
public struct RasterImage
public struct ImageDecodingLimits
public enum RasterImageError
public enum ImageContentMode
public struct Image
```

Required behavior:

- Decode PNG and JPEG from `Data`.
- Load bounded local and bundle files through `URL`.
- Do not add network loading in 0.1.0.
- Reject unsupported formats before decoder invocation.
- Reject animated PNG input in the initial API.
- Bound input size, dimensions, pixel count, decoded bytes, and estimated working memory.
- Use checked arithmetic for all allocation calculations.
- Convert output to straight, non-premultiplied RGBA8.
- Support `fit` and centered `fill`.
- Preserve image proportions with terminal-cell aspect correction.
- Downsample deterministically.
- Composite alpha against an explicit background.
- Render two vertical pixels per cell with `▀`.
- Use foreground for the upper pixel and background for the lower pixel.
- Let `ANSIEncoder` quantize output for truecolor, ANSI-256, and ANSI-16 terminals.
- Implement a real monochrome path without color SGR output.
- Add `.image` to the semantic role system.
- Require a useful accessibility label.

Add generated and redistributable fixtures for:

- PNG with alpha.
- Opaque JPEG.
- Truncated input.
- Invalid signatures.
- Excessive dimensions.
- Excessive pixel counts.
- Animated PNG.
- Fit and fill behavior.
- Odd source heights.
- Truecolor, 256-color, 16-color, and monochrome rendering.

Accepted safety tradeoff:

The clean upstream releases do not contain three strict decoder checks that exist in the current vendor copy. These concern reserved PNG filter bytes, JPEG DNL height handling, and JPEG entropy padding. Preserve wrapper-level limits and malformed-input tests, but do not describe the decoders as hardened.

Suggested commit:

```text
feat(image): add raster image rendering
```

## Phase 5: Add Missing Reusable Controls

Add only the reusable APIs required by the showcase:

- Terminal-size environment access for adaptive layouts.
- A keyboard-input modifier or command API suitable for application shortcuts.
- A deterministic `ProgressBar`.
- A minimal layout spacer if composition cannot express the layout cleanly.
- Semantic adjustable actions for progress and volume controls.
- Pointer activation for transport buttons and queue rows where current hit testing supports it.

Do not build player-specific concepts into TermKit.

Add focused tests for:

- Resize propagation.
- Keyboard dispatch.
- Progress clipping.
- Semantic values.
- Reduced-motion behavior.
- Zero idle frame demand.

Suggested commit:

```text
feat(controls): add adaptive terminal controls
```

## Phase 6: Build the Player Example

Create a separate package under `Examples/`.

Use an executable named `TermKitPlayer`. Treat it as a visual simulation, not an audio framework.

Visual direction:

- Use a compact late-1990s rack-mounted digital player, not a copied Winamp skin.
- Use original text, layout, glyphs, colors, and artwork.
- Do not use Winamp, OpenTUI, OpenCode, Spotnik, or TUIkit branding.
- Use a smoked-steel background, blue panel surfaces, amber LCD text, cyan signal data, red peak indicators, and neutral light text.
- Make the spectrum and transport timeline the visual signature.
- Keep decoration subordinate to state and controls.

Full layout for terminals at least `100x28`:

```text
+-------------+ +------------------------------------------------+
| Album art   | | Track, artist, album, clock                     |
|             | | Seek bar and playback state                     |
| Real PNG    | | Transport, volume, shuffle, repeat              |
| or JPEG     | | Animated spectrum                               |
+-------------+ +------------------------------------------------+
+----------------------------------------------------------------+
| Queue with selection, duration, and current-track state         |
+----------------------------------------------------------------+
| Keyboard hints and "visual simulation, no audio output"        |
+----------------------------------------------------------------+
```

Responsive behavior:

| Terminal size | Behavior |
| --- | --- |
| `>=100x28` | Full artwork, metadata, spectrum, controls, and queue |
| `72...99x24` | Smaller artwork, reduced metadata, shorter queue |
| `48...71x18` | Hide artwork and spectrum; show compact player and queue |
| Smaller | Stable minimum-size message with play state and quit shortcut |

Interactions:

| Input | Action |
| --- | --- |
| Space | Play or pause |
| `n` / `p` | Next or previous track |
| Left / Right | Seek by five seconds |
| `+` / `-` | Change volume |
| `m` | Toggle mute |
| `s` | Toggle shuffle |
| `r` | Cycle repeat mode |
| Up / Down | Select a queue row |
| Enter | Play the selected row |
| Tab / Shift-Tab | Move focus |
| `q` | Quit |
| Escape | Close temporary UI or quit when nothing is open |

Behavioral requirements:

- Use fictional artists, albums, and tracks.
- Include no audio files.
- Advance the playback clock only while playing.
- Request timeline frames only while playback or the spectrum is active.
- Stop animation demand while paused.
- Decode at least one PNG and one JPEG through the public TermKit API.
- Add original artwork with source and license information.
- Add a PTY smoke harness and tests for startup, input, resize, and terminal restoration.
- Add semantic snapshots at widths 40, 80, 120, and 180.
- Add a full screenshot, a compact screenshot, and a short recording or GIF.
- Record terminal, font, dimensions, command, creation method, and asset hashes in `.github/assets/README.md`.

Suggested commit:

```text
feat(example): add terminal player showcase
```

## Phase 7: Rebuild Documentation and Legal Files

Use clear English for all shipped documentation.

Rewrite:

```text
README.md
CHANGELOG.md
MIGRATION.md
LIMITATIONS.md
CONTRIBUTING.md
CREDITS.md
PROVENANCE.md
NOTICE.md
Documentation/*
Sources/TermKit/TermKit.docc/*
```

Add:

```text
SECURITY.md
CODE_OF_CONDUCT.md
SUPPORT.md
CITATION.cff
Licenses/Apache-2.0.txt
```

License requirements:

- Put the standard MIT text in `LICENSE`.
- Use `Copyright (c) 2026 Binary Dreams, LLC`.
- Do not add commercial restrictions.
- Do not add an advertising clause.
- State in the README that public credit is appreciated.
- Make clear that the credit request does not modify the MIT License.

Attribution requirements:

- Preserve the complete TUIkit MIT notice.
- Link to `https://github.com/phranck/TUIkit`.
- Record fork base `9f9aaed5ba332adaa678f07744395b9de812bbf0`.
- Credit OpenTUI at `https://github.com/anomalyco/opentui`.
- Describe OpenTUI as the directly studied source of component styles and ideas.
- Do not claim that OpenCode was directly studied.
- Remove every OpenCode notice and source comment.
- Credit `swift-png 4.5.1`, `swift-jpeg 2.1.0`, and `h`.
- Include upstream NOTICE text where required by Apache-2.0.
- Audit `dollup`, which currently lacks GitHub license metadata.
- If `dollup` is included in distributed artifacts or executed in the build graph, do not declare legal readiness until its terms are confirmed.
- Do not claim that Binary Dreams owns inherited TUIkit code.

README content:

- Binary Dreams branding and website.
- Canonical repository URL.
- CI and release badges.
- Swift 6.3.3 and platform requirements.
- SwiftPM installation.
- A minimal compile-tested example.
- Player screenshot.
- Player run command.
- Architecture summary.
- Image-rendering capabilities.
- Terminal compatibility.
- License and attribution.
- Contribution and security links.

Use this package declaration:

```swift
.package(
    url: "https://github.com/binarydreams-io/termkit",
    from: "0.1.0"
)
```

Use this product dependency:

```swift
.product(name: "TermKit", package: "termkit")
```

Suggested commit:

```text
docs(repo): publish TermKit documentation and notices
```

## Phase 8: Replace Tooling

Normalize directory names:

```text
Scripts/ -> scripts/
Docs/ -> Documentation/
```

Keep a small tooling surface:

```text
scripts/toolchain.env
scripts/quality-gate.sh
scripts/test-linux.sh
scripts/generate-documentation.sh
scripts/run-benchmarks.sh
scripts/verify-consumer.sh
scripts/verify-package-shape.sh
scripts/verify-release.sh
```

Update:

```text
.swift-format
.swiftlint.yml
.gitignore
.gitattributes
```

Requirements:

- Remove Astro, API compatibility, legacy target, badge, and old cache rules.
- Preserve legal and provenance files in source archives.
- Pin downloaded tools and GitHub Actions by immutable versions or SHAs.
- Keep scripts portable to case-sensitive Linux file systems.
- Make package-shape validation inspect the manifest rather than grep formatting.
- Verify the exact product and target count.
- Verify version consistency across `VERSION`, changelog, tags, and release metadata.
- Verify that repository archives contain all legal notices.
- Verify that no placeholder URL remains.
- Verify allowed historical occurrences of `TUIkit`.
- Reject unexpected occurrences of `SwiftTUI`, `SWIFTTUI_`, `TUIFoundation`, and removed module names.
- Reject all `OpenCode` occurrences.

## Phase 9: Rebuild CI and Release Automation

Create or replace these workflows:

```text
.github/workflows/ci.yml
.github/workflows/docs.yml
.github/workflows/performance.yml
.github/workflows/release.yml
```

Add:

```text
.github/dependabot.yml
.github/ISSUE_TEMPLATE/bug_report.yml
.github/ISSUE_TEMPLATE/feature_request.yml
.github/ISSUE_TEMPLATE/config.yml
.github/PULL_REQUEST_TEMPLATE.md
```

Required CI jobs:

| Job | Required checks |
| --- | --- |
| Hygiene | swift-format, SwiftLint, actionlint, stale-name scan, package shape |
| macOS | Debug build, release build, all tests, examples, PTY smoke, DocC |
| Linux | Pinned Swift 6.3.3 image, build, tests, examples, PTY smoke |
| Consumer | Fresh package using only the `TermKit` product |
| Image | PNG/JPEG fixtures, malformed corpus, color-mode snapshots |
| Performance | Deterministic invariants on pull requests; timing data as scheduled or manual artifacts |
| Documentation | Warning-free DocC archive and link checks |
| Release | Version, changelog, legal files, archive, checksums, consumer verification |

Performance policy:

- Keep deterministic scheduler and rendering invariants as required pull-request checks.
- Do not use unstable hosted-runner timing as the only merge gate.
- Run timing benchmarks on schedule, manually, and before release.
- Store machine-readable benchmark output as an artifact.
- Regenerate the baseline because the current file records incompatible revision and toolchain data.

Release workflow:

- Trigger only for SemVer tags.
- Require the tag to match `VERSION`.
- Require a matching changelog entry.
- Build source archives.
- Include legal notices.
- Generate SHA-256 checksums.
- Build DocC.
- Verify a versioned consumer.
- Prepare GitHub Release notes and artifacts.
- Do not publish automatically during this task.

Suggested commit:

```text
ci(repo): rebuild verification and release workflows
```

## Phase 10: Final Audit

Run the complete audit from clean scratch paths.

Required commands:

```bash
swift --version
swift package describe --type json
swift package show-dependencies
./scripts/verify-package-shape.sh
swift build -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
swift test
swift build --package-path Examples
swift test --package-path Examples
./scripts/generate-documentation.sh
./scripts/verify-consumer.sh
./scripts/run-benchmarks.sh
./scripts/quality-gate.sh
./scripts/test-linux.sh
./scripts/verify-release.sh 0.1.0
```

Inspect:

```bash
git status
git diff
git log --oneline
git archive
```

Do not push or create the `0.1.0` tag.

## Definition of Done

The roadmap is complete only when all conditions are true:

- The root package publishes only `TermKit`.
- The root package owns one library target and one test target.
- All modern SwiftTUI behavior has migrated or has an explicit removal record.
- Legacy TUIkit code, tests, vendor trees, tools, and scripts are gone.
- All preserved modern tests pass on macOS and Linux.
- The 13 performance contracts remain covered.
- Swift 6.3.3 is consistent across the manifest, environment, documentation, and CI.
- `import TermKit` works in a fresh consumer.
- Removed module imports fail.
- Public API names, access control, concurrency, and documentation pass a complete review.
- Real PNG and JPEG images render through upstream codecs.
- Truecolor, 256-color, 16-color, and monochrome image paths are tested.
- The player example is adaptive, interactive, visually coherent, and explicitly silent.
- All demo media is original and has provenance.
- README and DocC contain current commands and compile-tested snippets.
- MIT, TUIkit, OpenTUI, and dependency notices are accurate.
- OpenCode is no longer referenced.
- The attribution request is clearly nonbinding.
- No stale names remain outside approved historical files.
- CI and release workflows are pinned and warning-free.
- Each phase has a focused conventional commit.
- The working tree is clean after the final commit.
- Nothing has been pushed.

## Known Tradeoffs

- MIT requires preservation of the license notice. It cannot require every application UI to display a TermKit link.
- The README credit request remains voluntary.
- Swift 6.3.3 and current codecs reduce compatibility with older toolchains.
- Clean upstream codecs omit three strict checks from the old vendor copy.
- The plan preserves outer bounds but does not describe the decoders as hardened.
- The `TermKit` package and module-name collision is accepted.
- Do not add compatibility code or a README disclaimer for the name collision.
- `dollup` needs a dependency-license classification before legal readiness is claimed.
