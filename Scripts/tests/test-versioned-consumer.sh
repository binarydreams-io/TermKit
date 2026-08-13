#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEMP_DIR="$(mktemp -d)"

cleanup() {
    find "$TEMP_DIR" -type f -delete
    find "$TEMP_DIR" -depth -type d -delete
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

TEST_ROOT="$TEMP_DIR/workspace with spaces/SwiftTUI"
BIN_DIR="$TEMP_DIR/bin"
mkdir -p "$TEST_ROOT/scripts" "$BIN_DIR"
cp "$PROJECT_DIR/scripts/verify-versioned-consumer.sh" "$TEST_ROOT/scripts/"

cat > "$BIN_DIR/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "$1" == "package" || "$1" == "build" ]] || exit 10
[[ "$2" == "--package-path" ]] || exit 11
consumer_dir="$3"
manifest="$consumer_dir/Package.swift"
source="$consumer_dir/Sources/Consumer/main.swift"

if [[ -n "${EXPECTED_TAG:-}" ]]; then
    grep -Fq '.package(name: "SwiftTUI", url: "file://'"$EXPECTED_PACKAGE_PATH"'", exact: "'"$EXPECTED_TAG"'"),' "$manifest" || exit 12
else
    grep -Fq '.package(name: "SwiftTUI", path: "'"$EXPECTED_PACKAGE_PATH"'"),' "$manifest" || exit 12
fi
grep -Fq '.product(name: "SwiftTUI", package: "SwiftTUI")' "$manifest" || exit 13
grep -Fq 'import SwiftTUI' "$source" || exit 14
grep -Fq 'Animation.easeInOut(duration: .milliseconds(150))' "$source" || exit 15
for product in TUIFoundation TUITerminal TUIRenderer TUIViewGraph TUILayout TUIAnimation TUIControls TUIDesign TUIRichText TUIAgentUI TUIRuntime; do
    grep -Fq ".product(name: \"$product\", package: \"SwiftTUI\")" "$manifest" || exit 16
    grep -Fq "import $product" "$source" || exit 17
done
printf '%s\n' "$1 $2 $3 ${4:-}" >> "$SWIFT_INVOCATION_LOG"
EOF
chmod +x "$BIN_DIR/swift" "$TEST_ROOT/scripts/verify-versioned-consumer.sh"

OUTPUT="$TEST_ROOT/output.log"
env \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    EXPECTED_PACKAGE_PATH="$TEST_ROOT" \
    SWIFT_INVOCATION_LOG="$TEST_ROOT/swift.log" \
    "$TEST_ROOT/scripts/verify-versioned-consumer.sh" > "$OUTPUT"

[[ ! -e "$TEST_ROOT/.git" ]] || fail "test workspace unexpectedly contains Git metadata"
[[ "$(wc -l < "$TEST_ROOT/swift.log" | tr -d '[:space:]')" == "2" ]] || fail "expected resolve and build invocations"
grep -Fq "Local SwiftPM consumer gate passed" "$OUTPUT" || fail "local consumer gate did not pass"

TAGGED_ROOT="$TEMP_DIR/tagged/SwiftTUI"
mkdir -p "$TAGGED_ROOT/scripts"
cp "$PROJECT_DIR/scripts/verify-versioned-consumer.sh" "$TAGGED_ROOT/scripts/"
cp "$PROJECT_DIR/CHANGELOG.md" "$PROJECT_DIR/MIGRATION.md" "$PROJECT_DIR/README.md" "$TAGGED_ROOT/"
mkdir -p "$TAGGED_ROOT/Sources/SwiftTUI"
cp "$PROJECT_DIR/Sources/SwiftTUI/VERSION" "$TAGGED_ROOT/Sources/SwiftTUI/"
perl -0pi -e 's#<repository-url>#https://github.com/example/SwiftTUI.git#g' "$TAGGED_ROOT/README.md"
chmod +x "$TAGGED_ROOT/scripts/verify-versioned-consumer.sh"
git -C "$TAGGED_ROOT" init -q
git -C "$TAGGED_ROOT" add .
git -C "$TAGGED_ROOT" -c user.name=Fixture -c user.email=fixture@example.test commit -qm fixture
git -C "$TAGGED_ROOT" tag 0.1.0-preview

TAGGED_OUTPUT="$TAGGED_ROOT/output.log"
env \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    EXPECTED_PACKAGE_PATH="$TAGGED_ROOT" \
    EXPECTED_TAG="0.1.0-preview" \
    SWIFT_INVOCATION_LOG="$TAGGED_ROOT/swift.log" \
    "$TAGGED_ROOT/scripts/verify-versioned-consumer.sh" --tagged 0.1.0-preview > "$TAGGED_OUTPUT"

grep -Fq "Tagged SwiftPM consumer gate passed" "$TAGGED_OUTPUT" || fail "tagged consumer gate did not pass"

expect_tag_failure() {
    local expected="$1"
    local tag="$2"
    shift 2
    local error_file="$TEMP_DIR/tag-error.log"
    local status=0
    env PATH="$BIN_DIR:/usr/bin:/bin" "$@" \
        "$TAGGED_ROOT/scripts/verify-versioned-consumer.sh" --tagged "$tag" 2> "$error_file" || status=$?
    [[ "$status" -ne 0 ]] || fail "tag validation unexpectedly succeeded for $tag"
    grep -Fq "$expected" "$error_file" || fail "missing tag diagnostic: $expected"
}

expect_tag_failure "v-prefixed tags require SWIFTTUI_ALLOW_V_PREFIX=1" v0.1.0-preview
printf '%s\n' '9.9.9' > "$TAGGED_ROOT/Sources/SwiftTUI/VERSION"
expect_tag_failure "does not equal Sources/SwiftTUI/VERSION" 0.1.0-preview
printf '%s\n' '0.1.0-preview' > "$TAGGED_ROOT/Sources/SwiftTUI/VERSION"
perl -0pi -e 's/## 0[.]1[.]0-preview/## 9.9.9/' "$TAGGED_ROOT/CHANGELOG.md"
expect_tag_failure "CHANGELOG.md must contain exactly one" 0.1.0-preview
cp "$PROJECT_DIR/CHANGELOG.md" "$TAGGED_ROOT/CHANGELOG.md"
perl -0pi -e 's/## Release 0[.]1[.]0-preview/## Release 9.9.9/' "$TAGGED_ROOT/MIGRATION.md"
expect_tag_failure "MIGRATION.md must contain exactly one" 0.1.0-preview
cp "$PROJECT_DIR/MIGRATION.md" "$TAGGED_ROOT/MIGRATION.md"
perl -0pi -e 's#https://github.com/example/SwiftTUI.git#<repository-url>#g' "$TAGGED_ROOT/README.md"
expect_tag_failure "README.md contains a placeholder repository URL" 0.1.0-preview

cp "$PROJECT_DIR/README.md" "$TAGGED_ROOT/README.md"
perl -0pi -e 's#<repository-url>#https://github.com/example/SwiftTUI.git#g' "$TAGGED_ROOT/README.md"
git -C "$TAGGED_ROOT" tag v0.1.0-preview
env \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    EXPECTED_PACKAGE_PATH="$TAGGED_ROOT" \
    EXPECTED_TAG="v0.1.0-preview" \
    SWIFTTUI_ALLOW_V_PREFIX=1 \
    SWIFT_INVOCATION_LOG="$TAGGED_ROOT/swift-v.log" \
    "$TAGGED_ROOT/scripts/verify-versioned-consumer.sh" --tagged v0.1.0-preview > /dev/null

echo "Versioned consumer shell tests passed"
