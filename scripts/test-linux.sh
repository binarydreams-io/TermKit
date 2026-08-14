#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/toolchain.env"
command -v docker >/dev/null || { printf '%s\n' "Linux test error: docker is not installed" >&2; exit 1; }

if [[ "${1:-}" == "shell" ]]; then
    exec docker run --rm -it --platform linux/amd64 -v "$PROJECT_DIR:/workspace:ro" "$SWIFT_LINUX_IMAGE" bash
fi
[[ $# -eq 0 ]] || { printf 'Usage: %s [shell]\n' "$0" >&2; exit 2; }

docker run --rm --platform linux/amd64 -v "$PROJECT_DIR:/source:ro" "$SWIFT_LINUX_IMAGE" bash -lc '
set -euo pipefail
cp -R /source /tmp/TermKit
rm -rf /tmp/TermKit/.git /tmp/TermKit/.build /tmp/TermKit/Examples/.build
cd /tmp/TermKit
swift --version
./scripts/verify-package-shape.sh
swift build --scratch-path /tmp/termkit-debug -Xswiftc -warnings-as-errors
swift build --scratch-path /tmp/termkit-release -c release -Xswiftc -warnings-as-errors
swift test --scratch-path /tmp/termkit-tests
swift build --package-path Examples --scratch-path /tmp/termkit-examples-build -Xswiftc -warnings-as-errors
swift test --package-path Examples --scratch-path /tmp/termkit-examples-tests
./scripts/verify-consumer.sh
'
