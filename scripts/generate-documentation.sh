#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_PATH="${1:-$PROJECT_DIR/docc-output}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/Sources/TermKit/VERSION")"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termkit-docc.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

mkdir -p "$OUTPUT_PATH" "$TEMP_DIR/graphs"
swift build --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/build" --target TermKit -Xswiftc -warnings-as-errors
MODULE_DIR="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$TEMP_DIR/build" --show-bin-path)/Modules"
swift -print-target-info > "$TEMP_DIR/target-info.json"
TARGET="$(swift -warnings-as-errors - "$TEMP_DIR/target-info.json" <<'SWIFT'
import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let target = object["target"] as! [String: Any]
print(target["triple"] as! String)
SWIFT
)"

if [[ "$(uname -s)" == "Darwin" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    xcrun swift-symbolgraph-extract -module-name TermKit -I "$MODULE_DIR" -sdk "$SDK_PATH" \
        -output-dir "$TEMP_DIR/graphs" -target "$TARGET" -minimum-access-level public
    xcrun docc convert "$PROJECT_DIR/Sources/TermKit/TermKit.docc" \
        --additional-symbol-graph-dir "$TEMP_DIR/graphs" --output-path "$OUTPUT_PATH" \
        --fallback-display-name TermKit --fallback-bundle-identifier io.binarydreams.termkit \
        --fallback-bundle-version "$VERSION" --transform-for-static-hosting --hosting-base-path termkit --warnings-as-errors
else
    swift-symbolgraph-extract -module-name TermKit -I "$MODULE_DIR" -output-dir "$TEMP_DIR/graphs" \
        -target "$TARGET" -minimum-access-level public
    docc convert "$PROJECT_DIR/Sources/TermKit/TermKit.docc" \
        --additional-symbol-graph-dir "$TEMP_DIR/graphs" --output-path "$OUTPUT_PATH" \
        --fallback-display-name TermKit --fallback-bundle-identifier io.binarydreams.termkit \
        --fallback-bundle-version "$VERSION" --transform-for-static-hosting --hosting-base-path termkit --warnings-as-errors
fi

[[ -f "$OUTPUT_PATH/index.html" ]] || { printf '%s\n' "Documentation error: index.html is missing" >&2; exit 1; }
cp "$OUTPUT_PATH/index.html" "$OUTPUT_PATH/404.html"

swift -warnings-as-errors - "$PROJECT_DIR" <<'SWIFT'
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let manager = FileManager.default
let expression = try NSRegularExpression(pattern: #"\]\(([^)]+)\)"#)
let skippedDirectories: Set<String> = [".build", ".git", ".swiftpm"]
var failures: [String] = []
let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys)!

while let url = enumerator.nextObject() as? URL {
    let values = try url.resourceValues(forKeys: Set(keys))
    if values.isDirectory == true, skippedDirectories.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
    }
    guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
    let text = try String(contentsOf: url, encoding: .utf8)
    let range = NSRange(text.startIndex..., in: text)
    for match in expression.matches(in: text, range: range) {
        var destination = String(text[Range(match.range(at: 1), in: text)!])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if destination.hasPrefix("<"), destination.hasSuffix(">") {
            destination.removeFirst()
            destination.removeLast()
        } else {
            destination = String(destination.split(whereSeparator: { $0.isWhitespace }).first ?? "")
        }
        guard destination.isEmpty == false,
              destination.hasPrefix("#") == false,
              destination.hasPrefix("http://") == false,
              destination.hasPrefix("https://") == false,
              destination.hasPrefix("mailto:") == false
        else { continue }
        destination = String(destination.split(separator: "#", maxSplits: 1).first ?? "")
        destination = destination.removingPercentEncoding ?? destination
        let target = destination.hasPrefix("/")
            ? root.appendingPathComponent(String(destination.dropFirst()))
            : url.deletingLastPathComponent().appendingPathComponent(destination)
        if manager.fileExists(atPath: target.standardizedFileURL.path) == false {
            let source = url.path.replacingOccurrences(of: root.path + "/", with: "")
            failures.append("\(source): \(destination)")
        }
    }
}

guard failures.isEmpty else {
    for failure in failures.sorted() {
        FileHandle.standardError.write(Data("Documentation link error: \(failure)\n".utf8))
    }
    exit(1)
}
SWIFT
printf 'Documentation generated at %s\n' "$OUTPUT_PATH"
