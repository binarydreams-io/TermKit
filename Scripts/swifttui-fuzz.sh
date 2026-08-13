#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Four deterministic corpora run 1,024 Unicode, layer, resize, and diff-replay cases.
swift test "$@" --filter RendererPropertyTests
