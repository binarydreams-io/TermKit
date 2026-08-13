#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PRODUCTS="$PROJECT_DIR/Tools/APICompatibility/Configuration/public-api-products.tsv"
EXCEPTIONS="$PROJECT_DIR/Tools/APICompatibility/Configuration/api-platform-exceptions.tsv"
PACKAGE="$PROJECT_DIR/Package.swift"
COVERAGE="$PROJECT_DIR/Tools/APICompatibility/Configuration/public-api-coverage.tsv"

fail() {
    echo "API snapshot coverage error: $1" >&2
    exit 1
}

[[ -f "$PACKAGE" ]] || fail "Package.swift is missing"
[[ -f "$PRODUCTS" ]] || fail "public-api-products.tsv is missing"
[[ -f "$EXCEPTIONS" ]] || fail "api-platform-exceptions.tsv is missing"
[[ -f "$COVERAGE" ]] || fail "public-api-coverage.tsv is missing"

awk -F '\t' '
    NF != 2 || $1 == "" || $2 == "" { invalid = 1 }
    $1 ~ /^[[:space:]]/ || $1 ~ /[[:space:]]$/ { invalid = 1 }
    $2 ~ /^[[:space:]]/ || $2 ~ /[[:space:]]$/ { invalid = 1 }
    END { exit invalid }
' "$PRODUCTS" || fail "public-api-products.tsv must contain nonempty product and module columns"
sort -c -u "$PRODUCTS" >/dev/null 2>&1 \
    || fail "public-api-products.tsv must be sorted and unique"

awk -F '\t' '
    NF != 3 || $1 == "" || ($2 != "macOS" && $2 != "Linux") || $3 == "" { invalid = 1 }
    $1 ~ /^[[:space:]]/ || $1 ~ /[[:space:]]$/ { invalid = 1 }
    $3 ~ /^[[:space:]]/ || $3 ~ /[[:space:]]$/ { invalid = 1 }
    END { exit invalid }
' "$EXCEPTIONS" || fail "api-platform-exceptions.tsv must contain module, platform, and reason columns"
sort -c -u "$EXCEPTIONS" >/dev/null 2>&1 \
    || fail "api-platform-exceptions.tsv must be sorted and unique"

while IFS=$'\t' read -r product module; do
    grep -Fq ".library(name: \"$product\", targets: [\"$module\"])," "$PACKAGE" \
        || fail "declared product '$product' and module '$module' do not match Package.swift"
done < "$PRODUCTS"

while IFS=$'\t' read -r module platform reason; do
    awk -F '\t' -v module="$module" '$2 == module { found = 1 } END { exit !found }' "$PRODUCTS" \
        || fail "platform exception references unknown module '$module'"
done < "$EXCEPTIONS"

while IFS=$'\t' read -r product module; do
    for platform in Linux macOS; do
        coverage_count="$(awk -F '\t' -v module="$module" -v platform="$platform" \
            '$1 == module && $2 == platform { count += 1 } END { print count + 0 }' "$COVERAGE")"
        exception_count="$(awk -F '\t' -v module="$module" -v platform="$platform" \
            '$1 == module && $2 == platform { count += 1 } END { print count + 0 }' "$EXCEPTIONS")"
        [[ $((coverage_count + exception_count)) -eq 1 ]] \
            || fail "module '$module' on $platform needs exactly one coverage row or platform exception"
    done
done < "$PRODUCTS"

while IFS= read -r declaration; do
    product="$(printf '%s\n' "$declaration" | sed -n 's/.*\.library(name: "\([^"]*\)".*/\1/p')"
    [[ -n "$product" ]] || continue
    awk -F '\t' -v product="$product" '$1 == product { found = 1 } END { exit !found }' "$PRODUCTS" \
        || fail "public library product '$product' is missing from public-api-products.tsv"
done < <(grep -F '.library(name:' "$PACKAGE")
