#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
CONSUMER_DIR="$TEMP_DIR/Consumer"
TAGGED_VERSION=""
ALLOW_V_PREFIX="${SWIFTTUI_ALLOW_V_PREFIX:-0}"

if [[ "${1:-}" == "--tagged" && -n "${2:-}" && -z "${3:-}" ]]; then
    TAGGED_VERSION="$2"
elif [[ "$#" -ne 0 ]]; then
    echo "Usage: $0 [--tagged VERSION]" >&2
    exit 2
fi

cleanup() {
    find "$TEMP_DIR" -type f -delete
    find "$TEMP_DIR" -type l -delete
    find "$TEMP_DIR" -depth -type d -delete
}
trap cleanup EXIT

mkdir -p "$CONSUMER_DIR/Sources/Consumer"

DEPENDENCY='.package(name: "SwiftTUI", path: "'"$PROJECT_DIR"'"),'
GATE_NAME="Local"
if [[ -n "$TAGGED_VERSION" ]]; then
    NORMALIZED_VERSION="$TAGGED_VERSION"
    if [[ "$TAGGED_VERSION" == v* ]]; then
        [[ "$ALLOW_V_PREFIX" == "1" ]] || {
            echo "Tag release error: v-prefixed tags require SWIFTTUI_ALLOW_V_PREFIX=1" >&2
            exit 1
        }
        NORMALIZED_VERSION="${TAGGED_VERSION#v}"
    fi
    [[ "$NORMALIZED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z-]+)*$ ]] || {
        echo "Tag release error: invalid release version '$TAGGED_VERSION'" >&2
        exit 1
    }
    for required_file in Sources/SwiftTUI/VERSION CHANGELOG.md MIGRATION.md README.md; do
        [[ -f "$PROJECT_DIR/$required_file" ]] || {
            echo "Tag release error: missing $required_file" >&2
            exit 1
        }
    done
    FILE_VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/Sources/SwiftTUI/VERSION")"
    [[ "$FILE_VERSION" == "$NORMALIZED_VERSION" ]] || {
        echo "Tag release error: tag '$NORMALIZED_VERSION' does not equal Sources/SwiftTUI/VERSION '$FILE_VERSION'" >&2
        exit 1
    }
    [[ "$(grep -Fxc "## $NORMALIZED_VERSION" "$PROJECT_DIR/CHANGELOG.md")" == "1" ]] || {
        echo "Tag release error: CHANGELOG.md must contain exactly one '## $NORMALIZED_VERSION' section" >&2
        exit 1
    }
    [[ "$(grep -Fxc "## Release $NORMALIZED_VERSION" "$PROJECT_DIR/MIGRATION.md")" == "1" ]] || {
        echo "Tag release error: MIGRATION.md must contain exactly one '## Release $NORMALIZED_VERSION' section" >&2
        exit 1
    }
    if grep -Eq '<repository-url>|YOUR[_ -]?REPOSITORY|github[.]com/(owner|OWNER)/' "$PROJECT_DIR/README.md"; then
        echo "Tag release error: README.md contains a placeholder repository URL" >&2
        exit 1
    fi
    git -C "$PROJECT_DIR" rev-parse --verify HEAD >/dev/null
    git -C "$PROJECT_DIR" rev-parse --verify "refs/tags/$TAGGED_VERSION^{commit}" >/dev/null
    DEPENDENCY='.package(name: "SwiftTUI", url: "file://'"$PROJECT_DIR"'", exact: "'"$TAGGED_VERSION"'"),'
    GATE_NAME="Tagged"
fi

cat > "$CONSUMER_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftTUIConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        $DEPENDENCY
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "TUIFoundation", package: "SwiftTUI"),
                .product(name: "TUITerminal", package: "SwiftTUI"),
                .product(name: "TUIRenderer", package: "SwiftTUI"),
                .product(name: "TUIViewGraph", package: "SwiftTUI"),
                .product(name: "TUILayout", package: "SwiftTUI"),
                .product(name: "TUIAnimation", package: "SwiftTUI"),
                .product(name: "TUIControls", package: "SwiftTUI"),
                .product(name: "TUIDesign", package: "SwiftTUI"),
                .product(name: "TUIRichText", package: "SwiftTUI"),
                .product(name: "TUIAgentUI", package: "SwiftTUI"),
                .product(name: "TUIRuntime", package: "SwiftTUI"),
                .product(name: "SwiftTUI", package: "SwiftTUI"),
            ]
        ),
    ]
)
EOF

cat > "$CONSUMER_DIR/Sources/Consumer/main.swift" <<'EOF'
import TUIFoundation
import TUITerminal
import TUIRenderer
import TUIViewGraph
import TUILayout
import TUIAnimation
import TUIControls
import TUIDesign
import TUIRichText
import TUIAgentUI
import TUIRuntime
import SwiftTUI

let animation = Animation.easeInOut(duration: .milliseconds(150))
print("SwiftTUI consumer animation duration: \(animation.duration.seconds)")
EOF

swift package --package-path "$CONSUMER_DIR" resolve
swift build --package-path "$CONSUMER_DIR"

echo "$GATE_NAME SwiftPM consumer gate passed"
