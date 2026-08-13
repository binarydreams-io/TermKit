#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

emit_baseline_record=0
expected_performance_test_count=13
swift_arguments=()
for argument in "$@"; do
    case "$argument" in
        --emit-baseline-record)
            emit_baseline_record=1
            ;;
        *)
            swift_arguments+=("$argument")
            ;;
    esac
done
swift_argument_text=""
if (( ${#swift_arguments[@]} > 0 )); then
    swift_argument_text="${swift_arguments[*]}"
fi

swift_version="$(swift --version 2>&1 | tr '\n' ' ')"
kernel="$(uname -a)"
model="unknown"
cpu="$(uname -m)"
logical_cpus="unknown"
memory_bytes="unknown"
if [[ "$(uname -s)" == "Darwin" ]]; then
    model="$(sysctl -n hw.model)"
    cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
    logical_cpus="$(sysctl -n hw.logicalcpu)"
    memory_bytes="$(sysctl -n hw.memsize)"
elif [[ "$(uname -s)" == "Linux" ]]; then
    logical_cpus="$(getconf _NPROCESSORS_ONLN)"
fi

if (( emit_baseline_record )); then
    SWIFT_VERSION="$swift_version" KERNEL="$kernel" MODEL="$model" CPU="$cpu" \
        LOGICAL_CPUS="$logical_cpus" MEMORY_BYTES="$memory_bytes" \
        TERM_PROGRAM_VALUE="${TERM_PROGRAM:-not set}" \
        TERM_PROGRAM_VERSION_VALUE="${TERM_PROGRAM_VERSION:-not set}" \
        SWIFT_ARGUMENTS="$swift_argument_text" \
        python3 - <<'PY'
import json
import os

print(json.dumps({
    "schemaVersion": 1,
    "swiftVersion": os.environ["SWIFT_VERSION"].strip(),
    "kernel": os.environ["KERNEL"],
    "hardware": {
        "model": os.environ["MODEL"],
        "cpu": os.environ["CPU"],
        "logicalCPUs": os.environ["LOGICAL_CPUS"],
        "memoryBytes": os.environ["MEMORY_BYTES"],
    },
    "terminal": {
        "program": os.environ["TERM_PROGRAM_VALUE"],
        "version": os.environ["TERM_PROGRAM_VERSION_VALUE"],
    },
    "configuration": "release",
    "environment": {"SWIFTTUI_RUN_PERFORMANCE_TESTS": "1"},
    "command": "swift test -c release --filter TUIPerformanceTests " + os.environ["SWIFT_ARGUMENTS"],
}, sort_keys=True))
PY
    exit 0
fi

printf '%s\n' "SwiftTUI section 15 benchmark environment"
printf '%s\n' "Command: SWIFTTUI_RUN_PERFORMANCE_TESTS=1 swift test -c release --filter TUIPerformanceTests $swift_argument_text"
printf '\n%s\n' "Swift"
printf '%s\n' "$swift_version"

printf '\n%s\n' "Hardware"
printf 'Kernel: %s\n' "$kernel"
case "$(uname -s)" in
    Darwin)
        printf 'Model: %s\n' "$(sysctl -n hw.model)"
        printf 'CPU: %s\n' "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
        printf 'Logical CPUs: %s\n' "$(sysctl -n hw.logicalcpu)"
        printf 'Memory bytes: %s\n' "$(sysctl -n hw.memsize)"
        ;;
    Linux)
        if command -v lscpu >/dev/null 2>&1; then
            lscpu
        else
            printf 'Architecture: %s\n' "$(uname -m)"
            printf 'Logical CPUs: %s\n' "$(getconf _NPROCESSORS_ONLN)"
        fi
        ;;
esac

printf '\n%s\n' "Ghostty"
printf 'TERM_PROGRAM: %s\n' "${TERM_PROGRAM:-not set}"
printf 'TERM_PROGRAM_VERSION: %s\n' "${TERM_PROGRAM_VERSION:-not set}"
if command -v ghostty >/dev/null 2>&1; then
    ghostty +version 2>/dev/null || ghostty --version 2>/dev/null || printf '%s\n' "Version command unavailable"
else
    printf '%s\n' "Executable not found"
fi

printf '\n%s\n' "Benchmark"
discovered_tests="$(swift test list -c release ${swift_arguments[@]+"${swift_arguments[@]}"})"
test_list_file="$(mktemp)"
trap 'rm -f "$test_list_file"' EXIT
printf '%s\n' "$discovered_tests" > "$test_list_file"
discovered_performance_test_count=0
while IFS= read -r discovered_test; do
    if [[ "$discovered_test" == TUIPerformanceTests.* ]]; then
        discovered_performance_test_count=$((discovered_performance_test_count + 1))
    fi
done <<< "$discovered_tests"
if (( discovered_performance_test_count != expected_performance_test_count )); then
    printf 'Expected %d TUIPerformanceTests, discovered %d.\n' \
        "$expected_performance_test_count" "$discovered_performance_test_count" >&2
    exit 1
fi
./scripts/validate-benchmark-matrix.sh "$PROJECT_DIR" "$test_list_file"
SWIFTTUI_RUN_PERFORMANCE_TESTS=1 swift test -c release --filter TUIPerformanceTests \
    ${swift_arguments[@]+"${swift_arguments[@]}"}
