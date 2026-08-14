#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Usage: %s VERSION\n' "$0" >&2; exit 2; }
OUTPUT_DIR="${TERMKIT_RELEASE_OUTPUT:-$PROJECT_DIR/release-output}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termkit-release.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

FILE_VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/Sources/TermKit/VERSION")"
[[ "$VERSION" == "$FILE_VERSION" ]] || { printf '%s\n' "Release error: VERSION does not match" >&2; exit 1; }
if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" != "$VERSION" ]]; then
    printf '%s\n' "Release error: tag does not match VERSION" >&2
    exit 1
fi
grep -Eq "^## $VERSION - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$PROJECT_DIR/CHANGELOG.md"
grep -Eq "^version: ['\"]?${VERSION}['\"]?$" "$PROJECT_DIR/CITATION.cff"
grep -Fq "Version \`$VERSION\`" "$PROJECT_DIR/README.md"
grep -Fq 'SWIFT_VERSION="6.3.3"' "$SCRIPT_DIR/toolchain.env"
[[ "$(tr -d '[:space:]' < "$PROJECT_DIR/.swift-version")" == "6.3.3" ]]

PLACEHOLDER_MARKER='<repository''-url>'
PLACEHOLDER_REPOSITORY='YOUR[_-]''REPOSITORY'
PLACEHOLDER_OWNER='github\.com/(''owner|OWNER)/'
PLACEHOLDER_DOMAIN='example''\.com'
PLACEHOLDER_URLS="$PLACEHOLDER_MARKER|$PLACEHOLDER_REPOSITORY|$PLACEHOLDER_OWNER|$PLACEHOLDER_DOMAIN"
if git -C "$PROJECT_DIR" grep -I -E "$PLACEHOLDER_URLS" -- \
    ':!Documentation/Plans/*' ':!Tests/TermKitTests/Image/RasterImageTests.swift'; then
    printf '%s\n' "Release error: placeholder URL found" >&2
    exit 1
fi
swift package --package-path "$PROJECT_DIR" show-dependencies --format json > "$TEMP_DIR/dependencies.json"
if grep -Fiq 'dollup' "$TEMP_DIR/dependencies.json" "$PROJECT_DIR/Package.resolved" "$PROJECT_DIR/Examples/Package.resolved"; then
    printf '%s\n' "Release error: dollup entered the resolved graph" >&2
    exit 1
fi

"$SCRIPT_DIR/verify-package-shape.sh"
mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/TermKit-$VERSION.tar.gz"
git -C "$PROJECT_DIR" archive --format=tar.gz --prefix="TermKit-$VERSION/" --output="$ARCHIVE" HEAD
for path in LICENSE NOTICE.md CREDITS.md PROVENANCE.md Licenses/Apache-2.0.txt README.md CHANGELOG.md CITATION.cff SECURITY.md SUPPORT.md Package.swift Package.resolved Sources/TermKit/VERSION; do
    tar -tzf "$ARCHIVE" "TermKit-$VERSION/$path" >/dev/null || { printf 'Release error: archive missing %s\n' "$path" >&2; exit 1; }
done
mkdir -p "$TEMP_DIR/versioned"
tar -xzf "$ARCHIVE" -C "$TEMP_DIR/versioned"
mv "$TEMP_DIR/versioned/TermKit-$VERSION" "$TEMP_DIR/versioned/TermKit"
git -C "$TEMP_DIR/versioned/TermKit" init --quiet
git -C "$TEMP_DIR/versioned/TermKit" add .
git -C "$TEMP_DIR/versioned/TermKit" -c user.name=TermKit -c user.email=release@localhost commit --quiet -m "TermKit $VERSION"
git -C "$TEMP_DIR/versioned/TermKit" tag "$VERSION"
TERMKIT_PACKAGE_PATH="$TEMP_DIR/versioned/TermKit" TERMKIT_PACKAGE_VERSION="$VERSION" "$SCRIPT_DIR/verify-consumer.sh"
if command -v sha256sum >/dev/null; then
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$ARCHIVE")") > "$ARCHIVE.sha256"
else
    (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE")") > "$ARCHIVE.sha256"
fi
printf 'Release archive verified at %s\n' "$ARCHIVE"
