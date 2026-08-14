# TermKit 2.1 Baseline

- Baseline revision: `ccf2071238fe8abb69a1c49caa10ea8ec2357d34`
- Baseline date: `2026-08-14`
- Toolchain: Apple Swift `6.3.3`
- Target: `arm64-apple-macosx26.0`

This record identifies the behavior that the TermKit 2.1 migration must preserve.
It also identifies the legacy behavior that the migration intentionally removes.

## Source Inventory

The modern implementation contains 93 Swift source files:

| Module | Files |
| --- | ---: |
| `TUIFoundation` | 9 |
| `TUITerminal` | 10 |
| `TUIRenderer` | 8 |
| `TUIViewGraph` | 7 |
| `TUILayout` | 5 |
| `TUIAnimation` | 14 |
| `TUIControls` | 9 |
| `TUIDesign` | 6 |
| `TUIRichText` | 8 |
| `TUIAgentUI` | 11 |
| `TUIRuntime` | 5 |
| `SwiftTUI` | 1 |

The two showcase executable files are not part of this count.

## Test Inventory

The baseline contains these source-level test declarations:

| Classification | Swift files | `@Test` declarations |
| --- | ---: | ---: |
| Modern implementation | 77 | 465 |
| Legacy implementation | 124 | 1,400 |
| Total | 201 | 1,865 |

The modern tests include 16 semantic snapshot files. The legacy test count excludes two
`@Test` strings in documentation comments.

The command below passed all 1,865 tests. The run reported two expected legacy issues.

```bash
swift test \
  --scratch-path /tmp/termkit-baseline-tests
```

The focused PTY smoke test also passed:

```bash
swift test \
  --scratch-path /tmp/termkit-baseline-pty \
  --filter SwiftTUIShowcaseSmokeTests
```

The smoke test starts the showcase, activates its command palette, and verifies terminal
restoration.

## Performance Contracts

The migration must preserve these 13 deterministic contracts:

1. A localized `120x40` frame stays below its p95 budget and scans only the damaged cells.
2. Declarative paint animation skips reconciliation and layout.
3. A `200x60` full repaint stays below one 60 Hz frame.
4. An unchanged frame performs no work and writes no bytes.
5. An ordinary changed frame performs one logical write.
6. The real event source has no periodic idle wake.
7. Sustained invalidations coalesce into one frame.
8. A stalled animation does not queue stale frames.
9. An idle scheduler has no frame or deadline.
10. A 10,000-item conversation renders only its visible lazy range.
11. One tool-row mutation remains local in a 10,000-item transcript.
12. One runtime row invalidation scans one row instead of the full surface.
13. Interner growth stays bounded, and rebuild retains only live cells.

## Semantic Snapshots

The baseline snapshot hashes are:

```text
2350c4c1213ac92ba90177dcb65c0dec11a7bc5fba88c4d0977b4bb97a7f9f6d  dark-120.snap
f209f526cdcfcad1fe44a7853c2a1dc2eab3dafdb753e0f5134f24b0b73546ec  dark-180.snap
ea45ed7c3ce83d7d5af081bb93504ab0a576153f84600911ce7be76f26f19989  dark-40.snap
047f1cf1db76fe6766f6fdb90d9cb2c304f33e0daa2a1dd357c930907f7bff83  dark-80.snap
f8cfe93c2df6c436c661c457342a223e346a9fb7870005bbfbfa57085da865f1  light-120.snap
8a9f9e9144a1ae07da00a3693acfd4d960f503df0192099a188edbbada78c401  light-180.snap
63e2eaaae68c7a4d97fb42521e6f62e697e4fc9b80a390308382d67c4d3e0663  light-40.snap
e684ccc6b2e3197ac4e1dd8b754514c7cefbcdf4fd11dd2afb309d51344a8b28  light-80.snap
b648accd7d50bb82335041e47b7536b211e106536449e5579735457187917022  states-dark-120.snap
8b41ce60a46f692ba087c3707265aeb40e17a9692452b05bce4e732695b2d436  states-dark-180.snap
6520f7af9d09e68da9c115582052379d4c95a997fa933aa7cfce264727339c08  states-dark-40.snap
309843a3f9eb1f1999e5890d17a6b73b590357ae89b106eccdf7906c6f7bd9da  states-dark-80.snap
92012e78e03bb37a6b9b11d7c9f076832521278628855a090eaedd8711953946  states-light-120.snap
1c0ce1e93ca0bbe4a27423841e5d291808c9721752c1e9be9181881feb3dd46c  states-light-180.snap
a78f876d337097fc0debb775337fd1bb5d68397cae6844ecc32da7dc6d5a73a6  states-light-40.snap
4a6231e05714197bf98061251112527744db738d259bc18aede26b4a88e2e796  states-light-80.snap
```

## Public Symbols

The baseline symbol-graph command emitted graphs for all modern library modules:

```bash
swift package \
  --scratch-path /tmp/termkit-baseline-symbols \
  dump-symbol-graph --minimum-access-level public --pretty-print
```

The command later failed on the synthetic `SwiftTUIPackageTests` runner. The modern library
graphs remain valid baseline artifacts in the scratch directory. A static source inventory found
467 named top-level public declarations. The final API audit must use the consolidated TermKit
symbol graph, not this source count.

## Image-Decoding Design Record

The legacy image API and architecture are not part of the migration. The new image subsystem must
preserve these safety and sizing rules:

- Detect PNG from its complete eight-byte signature.
- Detect JPEG from the `FF D8 FF` prefix.
- Reject an unknown signature before decoder invocation.
- Limit the encoded input before copying or decoding it.
- Read local files in bounded chunks and stop after `limit + 1` bytes.
- Parse PNG `IHDR` dimensions, color type, bit depth, and interlace mode before decoding.
- Detect the PNG `acTL` chunk and reject animated input.
- Parse JPEG frame dimensions, component count, sampling factors, and process before decoding.
- Use checked arithmetic for dimensions, pixel counts, row bytes, MCU blocks, samples, and RGBA bytes.
- Bound source width and height, pixel count, final RGBA bytes, and estimated decoder memory.
- Treat decoder-memory estimates as outer bounds, not as a complete process-memory guarantee.
- Produce straight, non-premultiplied, row-major RGBA8 pixels.
- Treat JPEG output as opaque.
- Apply terminal-cell aspect correction before downsampling.
- Use a terminal cell height-to-width ratio of `2.0` unless the caller supplies another ratio.

The historical defaults were 64 MiB of encoded input, 16,384 pixels per dimension,
40,000,000 pixels, 160 MiB of final RGBA data, and 160 MiB of estimated source samples.
The TermKit API can use stricter values but must not silently remove these categories.

Do not copy these legacy implementation details:

- the public image-loader and ASCII-converter types;
- synchronous network loading;
- the lifetime cache;
- vendored codec wrappers;
- unchecked scaling arithmetic;
- alpha-dropping interpolation and rendering;
- lenient animated-PNG parsing;
- decoder-specific error strings.

The removed external PNG and JPEG assets have no sufficient fixture-specific provenance.
The new subsystem must use generated or explicitly redistributable fixtures.

## Proposed Codec Dependency Inventory

The baseline audit resolved the exact proposed codec releases before implementation:

| Package | Version | Revision | License |
| --- | --- | --- | --- |
| `swift-png` | `4.5.1` | `fc304242192135626a7e921f1327c5e64aa4386e` | Apache-2.0 |
| `swift-jpeg` | `2.1.0` | `f8b05e91056df5a578a9b2153aad50a7983bc4af` | Apache-2.0 |
| `h` | `1.0.1` | `82c0f986652d78ac11838a03e18f1e88f144258d` | Apache-2.0 |

The proposed graph contained two direct packages. `swift-png` resolved `h` transitively.
`swift-jpeg` had no additional resolved package. `dollup` did not enter the graph.
