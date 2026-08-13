# Legacy TUIkit Regression: API Compatibility Gate

This internal tool preserves reviewed TUIkit and SwiftUI symbol evidence from the predecessor project. It does not define SwiftTUI public API, product scope, or architecture. SwiftTUI does not promise TUIkit or SwiftUI parity.

The evidence uses SwiftUI from Xcode 26.6 and TUIkit snapshots built with Swift 6.0.3 on macOS and Linux.

The host snapshot job also extracts every public SwiftTUI library product. `Configuration/public-api-products.tsv` maps each product to its module. `Configuration/public-api-coverage.tsv` requires both hosts. `scripts/validate-api-snapshot-coverage.sh` compares these files with `Package.swift`.

`Configuration/api-platform-exceptions.tsv` records explicit platform exceptions. Each row contains a module, `macOS` or `Linux`, and a reason. Keep the file sorted. The validator rejects unknown modules, malformed rows, and undocumented omissions. An empty file means that all public modules support both platforms.

CI runs `scripts/validate-public-api-parity.sh` after both host jobs. The script compares each public module's macOS and Linux snapshots. A difference fails unless the exception file documents that module.

## Checked-in Artifacts

- `Configuration/review-policy.json` contains reviewed source decisions.
- `Configuration/compatibility-manifest.json` is generated from the policy and snapshot sets. Do not edit it manually.
- `Configuration/owners.json` associates included legacy APIs and TUIkit-only classifications with registered owner issues.
- `Configuration/contracts.json` associates included legacy APIs with compile contracts in `Configuration/CompileContracts/`.

Each reference symbol ID belongs to one inclusion or exclusion rule. Each TUIkit symbol ID requires an explicit decision unless it has one unique exact mapping.

## Review a Legacy Symbol Change

1. Generate Xcode 26.6 reference snapshots and Swift 6.0.3 TUIkit snapshots with the CI scripts.
2. Run `list-mapping-candidates` to inspect structural matches and surface differences.
3. Add each new reference ID to one reviewed policy rule.
4. Associate included symbols with a registered owner issue and compile contract.
5. Classify each new TUIkit ID as a reviewed mapping, TUIkit-specific API, or implementation leak.
6. Update positive and negative fixtures for changed compile-time contracts.
7. Generate the manifest and run the drift gate.

Run these commands from the repository root:

```bash
API_BUILD_PATH=".build/api-compatibility"
API_TOOL="$(swift build \
  --package-path Tools/APICompatibility \
  --build-path "$API_BUILD_PATH" \
  --show-bin-path)/TUIkitAPICheck"

"$API_TOOL" generate-manifest \
  --policy Tools/APICompatibility/Configuration/review-policy.json \
  --owner-registry Tools/APICompatibility/Configuration/owners.json \
  --reference-set /path/to/reference/snapshot-set.json \
  --tuikit-set /path/to/tuikit/snapshot-set.json \
  --output Tools/APICompatibility/Configuration/compatibility-manifest.json

./scripts/verify-compatibility-manifest.sh \
  --tool "$API_TOOL" \
  --policy Tools/APICompatibility/Configuration/review-policy.json \
  --owner-registry Tools/APICompatibility/Configuration/owners.json \
  --reference-set /path/to/reference/snapshot-set.json \
  --tuikit-set /path/to/tuikit/snapshot-set.json \
  --contracts Tools/APICompatibility/Configuration/contracts.json \
  --manifest Tools/APICompatibility/Configuration/compatibility-manifest.json
```

The quality gate type-checks the legacy contracts and validates the registry. CI also rejects missing decisions, stale generated output, invalid mappings, unregistered contracts, and undeclared differences.
