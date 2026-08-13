#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$PROJECT_DIR/scripts/validate-api-snapshot-coverage.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

copy_fixture() {
    local root="$1"
    mkdir -p "$root/Tools/APICompatibility/Configuration"
    cp "$PROJECT_DIR/Package.swift" "$root/Package.swift"
    cp "$PROJECT_DIR/Tools/APICompatibility/Configuration/public-api-products.tsv" \
        "$root/Tools/APICompatibility/Configuration/public-api-products.tsv"
    cp "$PROJECT_DIR/Tools/APICompatibility/Configuration/api-platform-exceptions.tsv" \
        "$root/Tools/APICompatibility/Configuration/api-platform-exceptions.tsv"
    cp "$PROJECT_DIR/Tools/APICompatibility/Configuration/public-api-coverage.tsv" \
        "$root/Tools/APICompatibility/Configuration/public-api-coverage.tsv"
}

expect_failure() {
    local expected="$1"
    local root="$2"
    local error="$root/error"
    if "$VALIDATOR" "$root" 2> "$error"; then
        fail "validator accepted an invalid fixture"
    fi
    grep -Fq "$expected" "$error" || fail "missing diagnostic: $expected"
}

"$VALIDATOR" "$PROJECT_DIR"

missing_product="$TEMP_DIR/missing-product"
copy_fixture "$missing_product"
sed -i.bak '/TUIRichText/d' "$missing_product/Tools/APICompatibility/Configuration/public-api-products.tsv"
expect_failure "public library product 'TUIRichText' is missing" "$missing_product"

missing_platform="$TEMP_DIR/missing-platform"
copy_fixture "$missing_platform"
sed -i.bak '/^TUIRuntime.*Linux$/d' "$missing_platform/Tools/APICompatibility/Configuration/public-api-coverage.tsv"
expect_failure "module 'TUIRuntime' on Linux needs exactly one coverage row or platform exception" "$missing_platform"

wrong_mapping="$TEMP_DIR/wrong-mapping"
copy_fixture "$wrong_mapping"
sed -i.bak 's/^TUIRuntime.*TUIRuntime$/TUIRuntime\tTUIRenderer/' \
    "$wrong_mapping/Tools/APICompatibility/Configuration/public-api-products.tsv"
expect_failure "declared product 'TUIRuntime' and module 'TUIRenderer' do not match Package.swift" "$wrong_mapping"

bad_exception="$TEMP_DIR/bad-exception"
copy_fixture "$bad_exception"
printf 'Unknown\tLinux\tnot supported\n' > \
    "$bad_exception/Tools/APICompatibility/Configuration/api-platform-exceptions.tsv"
expect_failure "platform exception references unknown module 'Unknown'" "$bad_exception"

duplicate_declaration="$TEMP_DIR/duplicate-declaration"
copy_fixture "$duplicate_declaration"
printf 'TUIRuntime\tLinux\ttemporary exception\n' > \
    "$duplicate_declaration/Tools/APICompatibility/Configuration/api-platform-exceptions.tsv"
expect_failure "module 'TUIRuntime' on Linux needs exactly one coverage row or platform exception" "$duplicate_declaration"

echo "API snapshot coverage validator tests passed"
