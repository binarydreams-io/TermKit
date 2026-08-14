#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termkit-shape.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

swift package --package-path "$PROJECT_DIR" dump-package > "$TEMP_DIR/package.json"
swift package --package-path "$PROJECT_DIR" describe --type json > "$TEMP_DIR/description.json"

swift -warnings-as-errors - "$TEMP_DIR/package.json" "$TEMP_DIR/description.json" <<'SWIFT'
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Package shape error: \(message)\n".utf8))
    exit(1)
}

func object(at path: String) -> [String: Any] {
    guard let value = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))),
          let object = value as? [String: Any]
    else { fail("cannot parse \(path)") }
    return object
}

let package = object(at: CommandLine.arguments[1])
let description = object(at: CommandLine.arguments[2])
guard package["name"] as? String == "TermKit" else { fail("package name must be TermKit") }
guard ((package["toolsVersion"] as? [String: Any])?["_version"] as? String) == "6.3.0" else {
    fail("tools version must be 6.3")
}
let platforms = package["platforms"] as? [[String: Any]] ?? []
guard platforms.count == 1, platforms[0]["platformName"] as? String == "macos",
      platforms[0]["version"] as? String == "14.0"
else { fail("platform must be macOS 14.0") }
let products = package["products"] as? [[String: Any]] ?? []
guard products.count == 1, products[0]["name"] as? String == "TermKit",
      products[0]["targets"] as? [String] == ["TermKit"], products[0]["type"] != nil
else { fail("one TermKit library product is required") }
let targets = package["targets"] as? [[String: Any]] ?? []
guard targets.count == 2 else { fail("one regular target and one test target are required") }
guard targets.contains(where: { $0["name"] as? String == "TermKit" && $0["type"] as? String == "regular" }) else {
    fail("TermKit regular target is missing")
}
guard targets.contains(where: { $0["name"] as? String == "TermKitTests" && $0["type"] as? String == "test" }) else {
    fail("TermKitTests target is missing")
}
let dependencies = package["dependencies"] as? [[String: Any]] ?? []
guard dependencies.count == 2 else { fail("exactly two direct dependencies are required") }
var exact: [String: String] = [:]
for dependency in dependencies {
    guard let wrapper = (dependency["sourceControl"] as? [[String: Any]])?.first,
          let identity = wrapper["identity"] as? String,
          let requirement = wrapper["requirement"] as? [String: Any],
          let version = (requirement["exact"] as? [String])?.first
    else { fail("every dependency must use an exact version") }
    exact[identity] = version
}
guard exact == ["swift-png": "4.5.1", "swift-jpeg": "2.1.0"] else { fail("codec versions do not match policy") }
let describedTargets = description["targets"] as? [[String: Any]] ?? []
guard describedTargets.count == 2 else { fail("described target count does not match") }
guard describedTargets.contains(where: { $0["name"] as? String == "TermKit" && $0["path"] as? String == "Sources/TermKit" }) else {
    fail("TermKit source path is invalid")
}
guard describedTargets.contains(where: { $0["name"] as? String == "TermKitTests" && $0["path"] as? String == "Tests/TermKitTests" }) else {
    fail("TermKitTests source path is invalid")
}
SWIFT

SOURCE_ENTRIES="$(find "$PROJECT_DIR/Sources" -mindepth 1 -maxdepth 1 -type d -print)"
TEST_ENTRIES="$(find "$PROJECT_DIR/Tests" -mindepth 1 -maxdepth 1 -type d -print)"
[[ "$SOURCE_ENTRIES" == "$PROJECT_DIR/Sources/TermKit" ]] || { printf '%s\n' "Package shape error: Sources contains extra targets" >&2; exit 1; }
[[ "$TEST_ENTRIES" == "$PROJECT_DIR/Tests/TermKitTests" ]] || { printf '%s\n' "Package shape error: Tests contains extra directories" >&2; exit 1; }
[[ -f "$PROJECT_DIR/Examples/Package.swift" ]] || { printf '%s\n' "Package shape error: Examples package is missing" >&2; exit 1; }
printf '%s\n' "Package shape verified."
