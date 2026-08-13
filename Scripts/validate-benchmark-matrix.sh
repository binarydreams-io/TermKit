#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MATRIX="$PROJECT_DIR/Tools/Performance/section-15-gates.tsv"
DOCUMENT="$PROJECT_DIR/docs/benchmarks.md"
TEST_LIST="${2:-}"
EXPECTED_GATES="bounded-frame-queue bounded-interner full-repaint idle-wakeup lazy-transcript local-tool-row localized-frame ordinary-write unchanged-frame"

fail() {
    echo "Benchmark matrix error: $1" >&2
    exit 1
}

[[ -f "$MATRIX" ]] || fail "section-15-gates.tsv is missing"
[[ -f "$DOCUMENT" ]] || fail "docs/benchmarks.md is missing"
awk -F '\t' 'NF != 3 || $1 == "" || $2 == "" || $3 == "" { invalid = 1 } END { exit invalid }' "$MATRIX" \
    || fail "section-15-gates.tsv must contain gate, test identifier, and budget or invariant"

actual_gates="$(cut -f 1 "$MATRIX" | sort -u | tr '\n' ' ' | sed 's/ $//')"
[[ "$actual_gates" == "$EXPECTED_GATES" ]] \
    || fail "section-15-gates.tsv does not contain exactly the nine section 15 gates"

while IFS=$'\t' read -r gate test_id invariant; do
    count="$(grep -Fc "| \`$gate\` | \`$test_id\` | $invariant |" "$DOCUMENT")"
    [[ "$count" == "1" ]] || fail "docs/benchmarks.md needs one exact row for '$test_id'"
    if [[ -n "$TEST_LIST" ]]; then
        grep -Fxq "$test_id" "$TEST_LIST" || fail "discovered performance test is missing: $test_id"
    fi
done < "$MATRIX"

document_rows="$(grep -Ec '^\| `[a-z-]+` \| `TUIPerformanceTests\.' "$DOCUMENT")"
matrix_rows="$(wc -l < "$MATRIX" | tr -d '[:space:]')"
[[ "$document_rows" == "$matrix_rows" ]] || fail "docs/benchmarks.md contains an incomplete or extra accepted matrix row"
