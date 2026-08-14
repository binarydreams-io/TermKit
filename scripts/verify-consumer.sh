#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="${TERMKIT_PACKAGE_PATH:-$PROJECT_DIR}"
PACKAGE_VERSION="${TERMKIT_PACKAGE_VERSION:-}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termkit-consumer.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
mkdir -p "$TEMP_DIR/Consumer/Sources/TermKitConsumer"

if [[ -n "$PACKAGE_VERSION" ]]; then
    [[ "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf '%s\n' "Consumer error: invalid package version" >&2; exit 1; }
    DEPENDENCY='.package(url: "file://'"$PACKAGE_DIR"'", exact: "'"$PACKAGE_VERSION"'")'
else
    DEPENDENCY='.package(path: "'"$PACKAGE_DIR"'")'
fi

cat > "$TEMP_DIR/Consumer/Package.swift" <<EOF
// swift-tools-version: 6.3
import PackageDescription
let package = Package(
    name: "TermKitConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [$DEPENDENCY],
    targets: [.executableTarget(name: "TermKitConsumer", dependencies: [.product(name: "TermKit", package: "TermKit")])]
)
EOF
cp "$PACKAGE_DIR/CompileFixtures/Consumer/Sources/TermKitConsumer/main.swift" \
    "$TEMP_DIR/Consumer/Sources/TermKitConsumer/main.swift"

swift build --package-path "$TEMP_DIR/Consumer" --scratch-path "$TEMP_DIR/build" -Xswiftc -warnings-as-errors
OUTPUT="$(swift run --package-path "$TEMP_DIR/Consumer" --scratch-path "$TEMP_DIR/build" TermKitConsumer)"
VERSION="$(tr -d '[:space:]' < "$PACKAGE_DIR/Sources/TermKit/VERSION")"
[[ -z "$PACKAGE_VERSION" || "$PACKAGE_VERSION" == "$VERSION" ]] || { printf '%s\n' "Consumer error: requested version does not match VERSION" >&2; exit 1; }
printf '%s\n' "$OUTPUT" | grep -Fq "TermKit consumer"
printf '%s\n' "$OUTPUT" | grep -Fq "$VERSION"

MODULE_DIR="$(find "$TEMP_DIR/build" -type d -path '*/debug/Modules' -print -quit)"
[[ -n "$MODULE_DIR" ]] || { printf '%s\n' "Consumer error: module directory is missing" >&2; exit 1; }
for fixture in "$PACKAGE_DIR"/CompileFixtures/RemovedModules/*.swift; do
    error_file="$TEMP_DIR/$(basename "$fixture").error"
    if swiftc -typecheck -module-name RemovedModuleCheck -I "$MODULE_DIR" "$fixture" 2> "$error_file"; then
        printf 'Consumer error: removed module fixture compiled: %s\n' "$fixture" >&2
        exit 1
    fi
    grep -Fq "no such module" "$error_file" || { printf 'Consumer error: unexpected failure for %s\n' "$fixture" >&2; exit 1; }
done
printf '%s\n' "Consumer and removed-module checks passed."
