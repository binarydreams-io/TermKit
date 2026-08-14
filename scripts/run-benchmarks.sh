#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/benchmark-output}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termkit-benchmarks.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
mkdir -p "$OUTPUT_DIR"

LIST="$(swift test --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/list" list)"
COUNT="$(printf '%s\n' "$LIST" | grep -E -c 'The real event source has no periodic idle wake|RenderPipelinePerformanceTests|SchedulerPerformanceTests|ScalabilityPerformanceTests')"
[[ "$COUNT" -eq 13 ]] || { printf 'Benchmark error: expected 13 tests, found %s\n' "$COUNT" >&2; exit 1; }

LOG="$OUTPUT_DIR/benchmarks.log"
TERMKIT_RUN_PERFORMANCE_TESTS=1 swift test --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/run" -c release \
    --filter 'The real event source has no periodic idle wake|RenderPipelinePerformanceTests|SchedulerPerformanceTests|ScalabilityPerformanceTests' | tee "$LOG"

swift -warnings-as-errors - "$LOG" "$OUTPUT_DIR/results.json" <<'SWIFT'
import Foundation

struct Result: Codable {
    let name: String
    let medianMilliseconds: Double
    let percentile95Milliseconds: Double
    let maximumMilliseconds: Double
    let budgetMilliseconds: Double
    let sampleCount: Int
    let warmupCount: Int
    let iterationsPerSample: Int
}

let log = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let pattern = #"^(.+): p50=([0-9.]+) ms, p95=([0-9.]+) ms, max=([0-9.]+) ms, budget<([0-9.]+) ms, samples=([0-9]+), warmups=([0-9]+), iterations/sample=([0-9]+)$"#
let expression = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
let range = NSRange(log.startIndex..., in: log)
let results = expression.matches(in: log, range: range).map { match in
    func value(_ index: Int) -> String {
        String(log[Range(match.range(at: index), in: log)!])
    }
    return Result(
        name: value(1),
        medianMilliseconds: Double(value(2))!,
        percentile95Milliseconds: Double(value(3))!,
        maximumMilliseconds: Double(value(4))!,
        budgetMilliseconds: Double(value(5))!,
        sampleCount: Int(value(6))!,
        warmupCount: Int(value(7))!,
        iterationsPerSample: Int(value(8))!
    )
}.sorted { $0.name < $1.name }
guard results.isEmpty == false else {
    FileHandle.standardError.write(Data("Benchmark error: no timing results found\n".utf8))
    exit(1)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
var data = try encoder.encode(results)
data.append(0x0A)
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT

REVISION="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
DIRTY=false
if [[ -n "$(git -C "$PROJECT_DIR" status --short)" ]]; then DIRTY=true; fi
SWIFT_VERSION="$(swift --version | tr '\n' ' ')"
PLATFORM="$(uname -s)-$(uname -m)"
cat > "$OUTPUT_DIR/metadata.json" <<EOF
{
  "schemaVersion": 1,
  "revision": "$REVISION",
  "dirty": $DIRTY,
  "swiftVersion": "$SWIFT_VERSION",
  "platform": "$PLATFORM",
  "configuration": "release",
  "environment": {"TERMKIT_RUN_PERFORMANCE_TESTS": "1"},
  "testsDiscovered": 13,
  "command": "./scripts/run-benchmarks.sh",
  "results": "results.json",
  "log": "benchmarks.log"
}
EOF
printf 'Benchmark output written to %s\n' "$OUTPUT_DIR"
