#!/usr/bin/env bash
#
# Generates the deployable SwiftTUI DocC archive.
#
# Usage:
#   ./scripts/generate-documentation.sh [output-path]
#
# The output path defaults to docc-output in the repository root.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-docc-output}"
SYMBOL_GRAPH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swifttui-docc-symbols.XXXXXX")"

cleanup() {
    find "$SYMBOL_GRAPH_DIR" -type f -delete
    find "$SYMBOL_GRAPH_DIR" -depth -type d -delete
}
trap cleanup EXIT

cd "$PROJECT_DIR"

SWIFT_BUILD_ARGUMENTS=(--package-path "$PROJECT_DIR")
if [[ -n "${TUIKIT_BUILD_PATH:-}" ]]; then
    SWIFT_BUILD_ARGUMENTS+=(--build-path "$TUIKIT_BUILD_PATH")
fi

swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --target SwiftTUI -Xswiftc -warnings-as-errors
BIN_PATH="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
if [[ -e "$BIN_PATH/Modules/SwiftTUI.swiftmodule" ]]; then
    MODULES_PATH="$BIN_PATH/Modules"
elif [[ -e "$BIN_PATH/SwiftTUI.swiftmodule" ]]; then
    MODULES_PATH="$BIN_PATH"
else
    echo "Unable to find the built SwiftTUI module below $BIN_PATH" >&2
    exit 1
fi

TARGET_TRIPLE="$(swift -print-target-info | awk -F'"' '/"triple"/ { print $4; exit }')"
if [[ -z "$TARGET_TRIPLE" ]]; then
    echo "Unable to determine the Swift target triple" >&2
    exit 1
fi

SYMBOLGRAPH_EXTRACT=(swift-symbolgraph-extract)
DOCC=(docc)
SDK_ARGUMENTS=()
if [[ "$(uname -s)" == "Darwin" ]]; then
    SYMBOLGRAPH_EXTRACT=(xcrun swift-symbolgraph-extract)
    DOCC=(xcrun docc)
    SDK_ARGUMENTS=(-sdk "$(xcrun --show-sdk-path)")
fi

"${SYMBOLGRAPH_EXTRACT[@]}" \
    -module-name SwiftTUI \
    -I "$MODULES_PATH" \
    -target "$TARGET_TRIPLE" \
    -output-dir "$SYMBOL_GRAPH_DIR" \
    -minimum-access-level public \
    -experimental-allowed-reexported-modules=TUIFoundation,TUITerminal,TUIRenderer,TUIViewGraph,TUILayout,TUIAnimation,TUIControls,TUIDesign,TUIRichText,TUIAgentUI,TUIRuntime \
    "${SDK_ARGUMENTS[@]}"

"${DOCC[@]}" convert Sources/SwiftTUI/SwiftTUI.docc \
    --additional-symbol-graph-dir "$SYMBOL_GRAPH_DIR" \
    --output-path "$OUTPUT_PATH" \
    --transform-for-static-hosting \
    --warnings-as-errors

swift -warnings-as-errors - "$OUTPUT_PATH" <<'SWIFT'
import Foundation

let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let indexURL = outputURL.appendingPathComponent("index.html")
let fallbackURL = outputURL.appendingPathComponent("404.html")
if fileManager.fileExists(atPath: fallbackURL.path) {
    try fileManager.removeItem(at: fallbackURL)
}
try fileManager.copyItem(at: indexURL, to: fallbackURL)

let redirect = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=/documentation/swifttui/">
  <link rel="canonical" href="/documentation/swifttui/">
  <title>Redirecting to SwiftTUI Documentation</title>
</head>
<body>
  <p>Redirecting to <a href="/documentation/swifttui/">SwiftTUI Documentation</a>...</p>
</body>
</html>
"""
try redirect.write(to: indexURL, atomically: true, encoding: .utf8)
SWIFT
