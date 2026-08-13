#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="${1:-}"
MACOS_ROOT="${2:-}"
LINUX_ROOT="${3:-}"
PRODUCTS="$PROJECT_DIR/Tools/APICompatibility/Configuration/public-api-products.tsv"
EXCEPTIONS="$PROJECT_DIR/Tools/APICompatibility/Configuration/api-platform-exceptions.tsv"

fail() {
    echo "Public API parity error: $1" >&2
    exit 1
}

[[ -x "$TOOL" ]] || fail "API comparison tool is not executable: $TOOL"
[[ -d "$MACOS_ROOT/snapshots" ]] || fail "macOS snapshot directory is missing"
[[ -d "$LINUX_ROOT/snapshots" ]] || fail "Linux snapshot directory is missing"

while IFS=$'\t' read -r product module; do
    if awk -F '\t' -v module="$module" '$1 == module { found = 1 } END { exit !found }' "$EXCEPTIONS"; then
        continue
    fi
    module_id="$(printf '%s' "$module" | tr '[:upper:]' '[:lower:]')"
    macos_snapshot=("$MACOS_ROOT/snapshots/$module_id-macos-swift-"*.json)
    linux_snapshot=("$LINUX_ROOT/snapshots/$module_id-linux-swift-"*.json)
    [[ ${#macos_snapshot[@]} -eq 1 && -f "${macos_snapshot[0]}" ]] \
        || fail "expected one macOS snapshot for $module"
    [[ ${#linux_snapshot[@]} -eq 1 && -f "${linux_snapshot[0]}" ]] \
        || fail "expected one Linux snapshot for $module"
    "$TOOL" compare --reference "${macos_snapshot[0]}" --current "${linux_snapshot[0]}" \
        || fail "$module differs between macOS and Linux without a platform exception"
done < "$PRODUCTS"
