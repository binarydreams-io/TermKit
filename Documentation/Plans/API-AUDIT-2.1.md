# TermKit 2.1 Public API Audit

- Audit date: `2026-08-14`
- Source revision: `b4c5348045929b4e259ebc0191fd2fafe70edf2d`
- Toolchain: Apple Swift `6.3.3`
- Module: `TermKit`
- Source-authored public declarations: `3,126`

## Method

The audit built the `TermKit` target and generated a fresh module-only symbol graph:

```bash
swift build --target TermKit --scratch-path /tmp/termkit-api-audit
mkdir -p /tmp/termkit-api-symbols
xcrun swift-symbolgraph-extract \
  -module-name TermKit \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -I /tmp/termkit-api-audit/arm64-apple-macosx/debug/Modules \
  -minimum-access-level public \
  -skip-synthesized-members \
  -pretty-print \
  -output-dir /tmp/termkit-api-symbols
```

The audit inspected every source-located declaration in `TermKit.symbols.json` and
`TermKit@Swift.symbols.json`. It applied the Swift API Design Guidelines to names, argument labels,
default arguments, closure parameters, documentation, complexity notes, and overloads.

The final graphs contain 3,154 records after the extractor omits synthesized members. Of these,
3,126 records have source locations. All 3,126 source-authored declarations have documentation
comments.

## Resolved Findings

The audit found no critical ambiguity. The implementation resolved these guideline findings before
the `2.1.0` release:

- Boolean properties now read as assertions.
- `TimeSource.now` is a property.
- factory methods use a `make` prefix when no framework precedent applies.
- `LayoutResult.clipped(to:)` replaces the free clipping function.
- environment and invalidation APIs use explicit `value:` and `flags:` labels.
- required parameters precede defaulted parameters.
- public closure types name their parameters.

A second symbol-graph pass found no replaced declarations or compatibility overloads.

## Concurrency Review

The source contains three `@unchecked Sendable` conformances. Each conformance protects mutable
state with a lock:

- `LockedState` serializes all access to its generic `Sendable` state with `NSLock`.
- `BackgroundPulseCacheStore` serializes all cache reads and writes with `NSLock`.
- `TerminalEventSourcePOSIXOwner` uses locked state for wake and wait coordination. Its signal
  teardown uses lock-free atomics because signal handlers cannot acquire locks.

No other source declaration uses `@unchecked Sendable`.

## Identity Review

`StructuralIdentity` equality and hashing use `ObjectIdentifier`, branch paths, keys, and indexes.
They do not use reflected type names. `String(reflecting:)` affects diagnostic descriptions and
in-memory animation property keys only. Both animation-key producers use the same reflected type.
No reflected value is persisted or decoded across process launches.

`structuralIdentityDescriptionUsesTermKitModule` verifies the consolidated diagnostic value
`TermKit.Text(index=0)`.

## Result

The public API has no open Swift API Design finding. The strict build, DocC conversion, consumer
fixture, and complete test suite provide separate checks for access control, documentation,
concurrency, and runtime behavior.
