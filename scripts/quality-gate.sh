#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/toolchain.env"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termkit-quality.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

ACTUAL_SWIFT="$(swift --version | sed -n '1s/.*version \([0-9][0-9.]*\).*/\1/p')"
[[ "$ACTUAL_SWIFT" == "$SWIFT_VERSION" ]] || { printf 'Quality error: expected Swift %s, found %s\n' "$SWIFT_VERSION" "$ACTUAL_SWIFT" >&2; exit 1; }
[[ "$(tr -d '[:space:]' < "$PROJECT_DIR/.swift-version")" == "$SWIFT_VERSION" ]]

"$SCRIPT_DIR/verify-package-shape.sh"

for script in quality-gate.sh test-linux.sh generate-documentation.sh run-benchmarks.sh verify-consumer.sh verify-package-shape.sh verify-release.sh; do
    [[ -x "$SCRIPT_DIR/$script" ]] || { printf 'Quality error: scripts/%s is not executable\n' "$script" >&2; exit 1; }
done
if git -C "$PROJECT_DIR" ls-files | grep -E '(^|/)\.DS_Store$'; then
    printf '%s\n' "Quality error: tracked .DS_Store found" >&2
    exit 1
fi
PLACEHOLDER_MARKER='<repository''-url>'
PLACEHOLDER_REPOSITORY='YOUR[_-]''REPOSITORY'
PLACEHOLDER_OWNER='github\.com/(''owner|OWNER)/'
PLACEHOLDER_DOMAIN='example''\.com'
PLACEHOLDER_URLS="$PLACEHOLDER_MARKER|$PLACEHOLDER_REPOSITORY|$PLACEHOLDER_OWNER|$PLACEHOLDER_DOMAIN"
if git -C "$PROJECT_DIR" grep -I -E "$PLACEHOLDER_URLS" -- \
    ':!Documentation/Plans/*' ':!Tests/TermKitTests/Image/RasterImageTests.swift'; then
    printf '%s\n' "Quality error: placeholder URL found" >&2
    exit 1
fi
FORBIDDEN_ATTRIBUTION='Open''Code'
if git -C "$PROJECT_DIR" grep -i -I -E "$FORBIDDEN_ATTRIBUTION" -- ':!Documentation/Plans/ROADMAP-2.1.md'; then
    printf '%s\n' "Quality error: forbidden attribution found" >&2
    exit 1
fi
STALE_NAMES='Swift''TUI|Swift''TUIRelease|SWIFT''TUI_|TUI''Foundation|TUI''Terminal|TUI''Renderer|TUI''ViewGraph|TUI''Layout|TUI''Animation|TUI''Controls|TUI''Design|TUI''RichText|TUI''AgentUI|TUI''Runtime|TUI''Duration'
if git -C "$PROJECT_DIR" grep -I -E "$STALE_NAMES" -- \
    ':!Documentation/Plans/*' ':!MIGRATION.md' ':!Sources/TermKit/TermKit.docc/Migration.md' ':!CompileFixtures/RemovedModules/*'; then
    printf '%s\n' "Quality error: stale project name found" >&2
    exit 1
fi
TUIKIT_NAME='TUI''kit'
TUIKIT_PATHS="$(git -C "$PROJECT_DIR" grep -I -l "$TUIKIT_NAME" || true)"
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    case "$path" in
        CREDITS.md|LIMITATIONS.md|MIGRATION.md|NOTICE.md|PROVENANCE.md|Documentation/design-origin.md|Documentation/Plans/*) ;;
        *) printf 'Quality error: unexpected legacy-project reference in %s\n' "$path" >&2; exit 1 ;;
    esac
done <<< "$TUIKIT_PATHS"

if command -v swift-format >/dev/null; then
    swift-format lint --strict --recursive "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests" "$PROJECT_DIR/Examples/Sources" "$PROJECT_DIR/Examples/Tests"
else
    swift format lint --strict --recursive "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests" "$PROJECT_DIR/Examples/Sources" "$PROJECT_DIR/Examples/Tests"
fi
command -v swiftlint >/dev/null || { printf '%s\n' "Quality error: swiftlint is not installed" >&2; exit 1; }
command -v actionlint >/dev/null || { printf '%s\n' "Quality error: actionlint is not installed" >&2; exit 1; }
[[ "$(swiftlint version)" == "$SWIFTLINT_VERSION" ]] || { printf '%s\n' "Quality error: SwiftLint version mismatch" >&2; exit 1; }
[[ "$(actionlint -version 2>&1 | sed -n '1p')" == "$ACTIONLINT_VERSION" ]] || { printf '%s\n' "Quality error: actionlint version mismatch" >&2; exit 1; }
swiftlint lint --strict --no-cache --config "$PROJECT_DIR/.swiftlint.yml"
actionlint "$PROJECT_DIR"/.github/workflows/*.yml

swift build --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/debug" -Xswiftc -warnings-as-errors
swift build --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/release" -c release -Xswiftc -warnings-as-errors
swift test --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/tests"
swift build --package-path "$PROJECT_DIR/Examples" --scratch-path "$TEMP_DIR/examples-build" -Xswiftc -warnings-as-errors
swift test --package-path "$PROJECT_DIR/Examples" --scratch-path "$TEMP_DIR/examples-tests"
"$SCRIPT_DIR/generate-documentation.sh" "$TEMP_DIR/documentation"
"$SCRIPT_DIR/verify-consumer.sh"
printf '%s\n' "Quality gate passed."
