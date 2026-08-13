#!/usr/bin/env bash

# GitHub expressions and inspected shell snippets must remain literal.
# shellcheck disable=SC2016

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_DIR="$PROJECT_DIR/.github/workflows"
TOOLCHAIN_FILE="$PROJECT_DIR/scripts/toolchain.env"
QUALITY_GATE="$PROJECT_DIR/scripts/quality-gate.sh"
DOCC_SCRIPT="$PROJECT_DIR/scripts/generate-documentation.sh"

fail() {
    echo "CI configuration error: $1" >&2
    exit 1
}

extract_top_level_mapping() {
    local workflow="$1"
    local target="$2"

    awk -v target="$target" '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            significant = normalized != ""
            current_indent = indentation($0)
            if (capturing) {
                if (significant && current_indent <= mapping_indent) {
                    exit
                }
                if (significant) {
                    print normalized
                }
                next
            }
            if (significant && current_indent == 0 && normalized == target ":") {
                capturing = 1
                mapping_indent = current_indent
                print normalized
            }
        }
    ' "$workflow"
}

count_job_blocks() {
    local workflow="$1"
    local target="$2"

    awk -v target="$target" '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            significant = normalized != ""
            current_indent = indentation($0)
            if (!in_jobs && significant && current_indent == 0 && normalized == "jobs:") {
                in_jobs = 1
                jobs_indent = current_indent
                next
            }
            if (!in_jobs) {
                next
            }
            if (significant && current_indent <= jobs_indent) {
                in_jobs = 0
                next
            }
            if (significant && job_indent == 0) {
                job_indent = current_indent
            }
            if (significant && current_indent == job_indent && normalized == target ":") {
                count += 1
            }
        }
        END { print count + 0 }
    ' "$workflow"
}

extract_job_block() {
    local workflow="$1"
    local target="$2"

    awk -v target="$target" '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            significant = normalized != ""
            current_indent = indentation($0)
            if (capturing) {
                if (significant && current_indent <= target_indent) {
                    exit
                }
                print
                next
            }
            if (!in_jobs && significant && current_indent == 0 && normalized == "jobs:") {
                in_jobs = 1
                jobs_indent = current_indent
                next
            }
            if (!in_jobs) {
                next
            }
            if (significant && current_indent <= jobs_indent) {
                in_jobs = 0
                next
            }
            if (significant && job_indent == 0) {
                job_indent = current_indent
            }
            if (significant && current_indent == job_indent && normalized == target ":") {
                capturing = 1
                target_indent = current_indent
                print
            }
        }
    ' "$workflow"
}

exclude_job_block() {
    local workflow="$1"
    local target="$2"

    awk -v target="$target" '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            significant = normalized != ""
            current_indent = indentation($0)
            if (skipping) {
                if (!significant || current_indent > target_indent) {
                    next
                }
                skipping = 0
            }
            if (!in_jobs && significant && current_indent == 0 && normalized == "jobs:") {
                in_jobs = 1
                jobs_indent = current_indent
            } else if (in_jobs && significant && current_indent <= jobs_indent) {
                in_jobs = 0
            } else if (in_jobs && significant && job_indent == 0) {
                job_indent = current_indent
            }
            if (in_jobs && significant && current_indent == job_indent && normalized == target ":") {
                skipping = 1
                target_indent = current_indent
                next
            }
            print
        }
    ' "$workflow"
}

extract_direct_child_mapping() {
    local target="$1"

    awk -v target="$target" '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            significant = normalized != ""
            current_indent = indentation($0)
            if (!parent_seen && significant) {
                parent_seen = 1
                parent_indent = current_indent
                next
            }
            if (!parent_seen || !significant) {
                next
            }
            if (capturing) {
                if (current_indent <= mapping_indent) {
                    exit
                }
                print normalized
                next
            }
            if (child_indent == 0) {
                child_indent = current_indent
            }
            if (current_indent == child_indent && normalized == target ":") {
                capturing = 1
                mapping_indent = current_indent
                print normalized
            }
        }
    '
}

has_contents_write_permission() {
    awk '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            semantic = normalized
            gsub(/"/, "", semantic)
            single_quote = sprintf("%c", 39)
            gsub(single_quote, "", semantic)
            gsub(/[[:space:]]/, "", semantic)
            significant = normalized != ""
            current_indent = indentation($0)
            if (!significant) {
                next
            }
            if (in_permissions && current_indent <= permissions_indent) {
                in_permissions = 0
            }
            if (!in_jobs && current_indent == 0 && normalized == "jobs:") {
                in_jobs = 1
                jobs_indent = current_indent
                next
            }
            if (in_jobs && current_indent <= jobs_indent) {
                in_jobs = 0
                job_indent = 0
                child_indent = 0
            } else if (in_jobs) {
                if (job_indent == 0) {
                    job_indent = current_indent
                }
                if (current_indent == job_indent) {
                    child_indent = 0
                } else if (child_indent == 0) {
                    child_indent = current_indent
                }
            }
            is_permission_key = current_indent == 0 || \
                (in_jobs && child_indent != 0 && current_indent == child_indent)
            if (is_permission_key && semantic == "permissions:write-all") {
                found = 1
            }
            if (is_permission_key && semantic ~ /^permissions:[{][^}]*contents:write([,}]|$)/) {
                found = 1
            }
            if (is_permission_key && semantic == "permissions:") {
                in_permissions = 1
                permissions_indent = current_indent
                next
            }
            if (in_permissions && semantic == "contents:write") {
                found = 1
            }
        }
        END { exit found ? 0 : 1 }
    '
}

has_top_level_permissions_declaration() {
    awk '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function normalize(line) {
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/[[:space:]]*$/, "", line)
            return line
        }
        {
            normalized = normalize($0)
            if (indentation($0) == 0 && normalized ~ /^permissions:/) {
                found = 1
            }
        }
        END { exit found ? 0 : 1 }
    '
}

has_yaml_anchor_or_alias() {
    local inspection_status=0

    awk '
        function indentation(line, stripped) {
            stripped = line
            sub(/^[[:space:]]*/, "", stripped)
            return length(line) - length(stripped)
        }
        function structural_text(line, output, position, character, next_character) {
            output = ""
            single_quote = sprintf("%c", 39)
            for (position = 1; position <= length(line); position += 1) {
                character = substr(line, position, 1)
                next_character = substr(line, position + 1, 1)
                if (in_single_quote) {
                    if (character == single_quote && next_character == single_quote) {
                        position += 1
                    } else if (character == single_quote) {
                        in_single_quote = 0
                    }
                    continue
                }
                if (in_double_quote) {
                    if (character == "\\") {
                        position += 1
                    } else if (character == "\"") {
                        in_double_quote = 0
                    }
                    continue
                }
                if (character == "#") {
                    break
                }
                if (character == single_quote) {
                    in_single_quote = 1
                    continue
                }
                if (character == "\"") {
                    in_double_quote = 1
                    continue
                }
                output = output character
            }
            in_single_quote = 0
            in_double_quote = 0
            return output
        }
        {
            current_indent = indentation($0)
            structural = structural_text($0)
            significant = structural ~ /[^[:space:]]/

            if (in_block_scalar) {
                if (significant && current_indent <= block_indent) {
                    in_block_scalar = 0
                } else {
                    next
                }
            }

            if (structural ~ /(^|[[:space:][\]{},:-])[&*][[:alnum:]_-]+([[:space:][\]{},#]|$)/) {
                found = 1
            }
            if (structural ~ /:[[:space:]]*[|>][-+0-9]*[[:space:]]*$/) {
                in_block_scalar = 1
                block_indent = current_indent
            }
        }
        END { exit found ? 0 : 1 }
    ' || inspection_status=$?

    (( inspection_status <= 1 )) || fail "unable to inspect workflow YAML anchors and aliases"
    return "$inspection_status"
}

has_git_push() {
    local inspection_status=0

    awk '
        function normalized_token(token) {
            gsub(/^["'"'"'`([{]+/, "", token)
            gsub(/["'"'"'`),;]}]+$/, "", token)
            return token
        }
        function is_git_command(token) {
            return token == "git" || \
                (length(token) >= 4 && substr(token, length(token) - 3) == "/git")
        }
        function option_requires_value(token) {
            return token == "-C" || token == "-c" || \
                token == "--git-dir" || token == "--work-tree" || \
                token == "--namespace" || token == "--super-prefix" || \
                token == "--config-env" || token == "--exec-path"
        }
        function inspect_command(line, token_count, tokens, token_index, token, candidate_index, candidate) {
            token_count = split(line, tokens, /[[:space:]]+/)
            for (token_index = 1; token_index <= token_count; token_index += 1) {
                token = normalized_token(tokens[token_index])
                if (!is_git_command(token)) {
                    continue
                }

                candidate_index = token_index + 1
                while (candidate_index <= token_count) {
                    candidate = normalized_token(tokens[candidate_index])
                    if (candidate == "push") {
                        found = 1
                        break
                    }
                    if (candidate == "\\") {
                        candidate_index += 1
                        continue
                    }
                    if (option_requires_value(candidate)) {
                        candidate_index += 2
                        continue
                    }
                    if (candidate ~ /^-/) {
                        candidate_index += 1
                        continue
                    }
                    break
                }
            }
        }
        /^[[:space:]]*#/ && !continuing { next }
        {
            physical_line = $0
            sub(/[[:space:]]+$/, "", physical_line)
            if (continuing) {
                logical_line = logical_line " " physical_line
            } else {
                logical_line = physical_line
            }

            if (logical_line ~ /\\$/) {
                sub(/\\$/, "", logical_line)
                continuing = 1
                next
            }

            continuing = 0
            inspect_command(logical_line)
            logical_line = ""
        }
        END {
            if (logical_line != "") {
                inspect_command(logical_line)
            }
            exit found ? 0 : 1
        }
    ' || inspection_status=$?

    (( inspection_status <= 1 )) || fail "unable to inspect workflow git commands"
    return "$inspection_status"
}

has_direct_readme_count_edit() {
    awk '
        /^[[:space:]]*#/ { next }
        {
            line = tolower($0)
            if (line ~ /readme([.]md)?/ && \
                (line ~ /(^|[;&|[:space:]])(sed|perl|awk|ruby|python|python3|mv|cp|tee|printf|echo)([[:space:]]|$)/ || \
                    line ~ /git[[:space:]]+add[[:space:]]+[^#]*readme/ || \
                    line ~ />[[:space:]]*readme([.]md)?/)) {
                readme_mutation = 1
            }
            if (line ~ /tests-|test[_ -]?count|tests run|tuikittests|test badge/) {
                test_count_hint = 1
            }
        }
        END { exit readme_mutation && test_count_hint ? 0 : 1 }
    '
}

normalized_line_count() {
    local text="$1"
    local expected="$2"

    printf '%s\n' "$text" | awk -v expected="$expected" '$0 == expected { count += 1 } END { print count + 0 }'
}

nonempty_line_count() {
    local text="$1"

    printf '%s\n' "$text" | awk 'NF { count += 1 } END { print count + 0 }'
}

for required_file in "$PROJECT_DIR/.swift-version" "$TOOLCHAIN_FILE" "$QUALITY_GATE" "$DOCC_SCRIPT"; do
    [[ -f "$required_file" ]] || fail "missing ${required_file#"$PROJECT_DIR"/}"
done
[[ -d "$WORKFLOW_DIR" ]] || fail "missing .github/workflows"

# shellcheck source=scripts/toolchain.env
# PROJECT_DIR may point at a validation fixture.
# shellcheck disable=SC1091
source "$TOOLCHAIN_FILE"

PINNED_SWIFT_VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/.swift-version")"
[[ "$PINNED_SWIFT_VERSION" =~ ^6\.0\.[0-9]+$ ]] || fail ".swift-version must pin one Swift 6.0 patch"
[[ "$PINNED_SWIFT_VERSION" == "$SWIFT_VERSION" ]] || fail ".swift-version and toolchain.env disagree"
[[ "$SWIFT_LINUX_IMAGE" == *"swift:${SWIFT_VERSION}-"*"@sha256:"* ]] || fail "Linux Swift image must match Swift $SWIFT_VERSION and include a digest"
[[ "${SWIFT_LINUX_IMAGE##*@sha256:}" =~ ^[0-9a-f]{64}$ ]] || fail "Linux Swift image digest must be a full SHA-256"
[[ "$SWIFTLINT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "SwiftLint must use an exact version"
[[ "$SWIFTLINT_MACOS_URL" == *"/$SWIFTLINT_VERSION/"* ]] || fail "macOS SwiftLint URL must contain its exact version"
[[ "$SWIFTLINT_LINUX_AMD64_URL" == *"/$SWIFTLINT_VERSION/"* ]] || fail "Linux SwiftLint URL must contain its exact version"
[[ "$SWIFTLINT_MACOS_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "macOS SwiftLint checksum must be SHA-256"
[[ "$SWIFTLINT_LINUX_AMD64_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "Linux SwiftLint checksum must be SHA-256"
[[ "${SWIFTLINT_MACOS_BINARY_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail "macOS SwiftLint binary checksum must be SHA-256"
[[ "${SWIFTLINT_LINUX_AMD64_BINARY_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail "Linux SwiftLint binary checksum must be SHA-256"
[[ "$ACTIONLINT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "actionlint must use an exact version"
[[ "$ACTIONLINT_MACOS_AMD64_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "macOS amd64 actionlint checksum must be SHA-256"
[[ "$ACTIONLINT_MACOS_ARM64_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "macOS arm64 actionlint checksum must be SHA-256"
[[ "$ACTIONLINT_LINUX_AMD64_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "Linux actionlint checksum must be SHA-256"
[[ "${ACTIONLINT_MACOS_AMD64_BINARY_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail "macOS amd64 actionlint binary checksum must be SHA-256"
[[ "${ACTIONLINT_MACOS_ARM64_BINARY_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail "macOS arm64 actionlint binary checksum must be SHA-256"
[[ "${ACTIONLINT_LINUX_AMD64_BINARY_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail "Linux actionlint binary checksum must be SHA-256"
[[ "${SWIFTUI_REFERENCE_RUNNER:-}" == "macos-26" ]] || fail "SwiftUI reference runner must be macos-26"
[[ "${SWIFTUI_REFERENCE_XCODE_VERSION:-}" == "26.6" ]] || fail "SwiftUI reference Xcode must be 26.6"
[[ "${SWIFTUI_REFERENCE_XCODE_BUILD:-}" == "17F113" ]] || fail "SwiftUI reference Xcode build must be 17F113"
[[ "${SWIFTUI_REFERENCE_XCODE_PATH:-}" == "/Applications/Xcode_26.6.app/Contents/Developer" ]] \
    || fail "SwiftUI reference Xcode path must select Xcode 26.6"

WORKFLOW_FILES=()
while IFS= read -r workflow; do
    WORKFLOW_FILES+=("$workflow")
done < <(find "$WORKFLOW_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)
[[ "${#WORKFLOW_FILES[@]}" -gt 0 ]] || fail "no workflow files found"

if [[ -z "${ACTIONLINT_BIN:-}" ]]; then
    case "$(uname -s)" in
        Darwin)
            ACTIONLINT_BIN="$("$SCRIPT_PROJECT_DIR"/scripts/install-actionlint.sh macos)"
            ;;
        Linux)
            ACTIONLINT_BIN="$("$SCRIPT_PROJECT_DIR"/scripts/install-actionlint.sh linux-amd64)"
            ;;
        *)
            fail "unsupported actionlint platform: $(uname -s)"
            ;;
    esac
fi
[[ -x "$ACTIONLINT_BIN" ]] || fail "ACTIONLINT_BIN is not executable"
if ! "$ACTIONLINT_BIN" "${WORKFLOW_FILES[@]}"; then
    fail "workflow syntax validation failed"
fi

for workflow in "${WORKFLOW_FILES[@]}"; do
    while IFS= read -r uses_line; do
        action_ref="${uses_line##*@}"
        action_ref="${action_ref%%[[:space:]#]*}"
        [[ "$action_ref" =~ ^[0-9a-f]{40}$ ]] || fail "${workflow#"$PROJECT_DIR"/} contains a moving external uses ref: $action_ref"
    done < <(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^.]' "$workflow" || true)
done

grep -R -Eq 'brew install swiftlint|swift:6\.0([^.]|$)|ubuntu-latest|macos-latest' "$WORKFLOW_DIR" \
    && fail "workflow contains an unpinned tool or runner"
grep -R -Fq '@Test' "$WORKFLOW_DIR" && fail "workflow must not count source annotations"

for workflow in "${WORKFLOW_FILES[@]}"; do
    grep -Fq 'scripts/update-test-count.sh' "$workflow" \
        && fail "${workflow#"$PROJECT_DIR"/} invokes the retired README test-count writer"
done

CI_WORKFLOW="$WORKFLOW_DIR/ci.yml"
[[ -f "$CI_WORKFLOW" ]] || fail "missing .github/workflows/ci.yml"

[[ "$(count_job_blocks "$CI_WORKFLOW" "update-badge")" == "0" ]] \
    || fail "CI must not define the retired update-badge job"
[[ "$(count_job_blocks "$CI_WORKFLOW" "deploy-docs")" == "0" ]] \
    || fail "CI must not deploy documentation without an approved destination"

for workflow in "${WORKFLOW_FILES[@]}"; do
    relative_workflow="${workflow#"$PROJECT_DIR"/}"
    if has_yaml_anchor_or_alias < "$workflow"; then
        fail "$relative_workflow uses unsupported YAML anchors or aliases"
    fi
    workflow_contents="$(< "$workflow")"

    if printf '%s\n' "$workflow_contents" | has_contents_write_permission; then
        fail "$relative_workflow grants contents: write"
    fi
    if [[ "$workflow" != "$CI_WORKFLOW" ]] \
        && ! printf '%s\n' "$workflow_contents" | has_top_level_permissions_declaration; then
        fail "$relative_workflow must explicitly default contents to read-only"
    fi
    if printf '%s\n' "$workflow_contents" | has_direct_readme_count_edit; then
        fail "$relative_workflow contains a retired README test-count writer"
    fi
    if printf '%s\n' "$workflow_contents" | has_git_push; then
        fail "$relative_workflow contains git push"
    fi
done

CI_PERMISSIONS="$(extract_top_level_mapping "$CI_WORKFLOW" "permissions")"
[[ "$CI_PERMISSIONS" == $'permissions:\ncontents: read' ]] \
    || fail "CI must default workflow permissions to contents: read"

CI_CONCURRENCY="$(extract_top_level_mapping "$CI_WORKFLOW" "concurrency")"
if [[ "$(nonempty_line_count "$CI_CONCURRENCY")" != "3" ]] \
    || [[ "$(normalized_line_count "$CI_CONCURRENCY" "concurrency:")" != "1" ]] \
    || [[ "$(normalized_line_count "$CI_CONCURRENCY" 'group: ci-${{ github.ref }}')" != "1" ]] \
    || [[ "$(normalized_line_count "$CI_CONCURRENCY" "cancel-in-progress: \${{ github.event_name == 'pull_request' }}")" != "1" ]]; then
    fail "CI must define the ref-scoped concurrency guard"
fi

grep -Fq './scripts/test-linux.sh macos' "$CI_WORKFLOW" || fail "CI must use the local macOS gate path"
grep -Fq './scripts/test-linux.sh linux' "$CI_WORKFLOW" || fail "CI must use the local Linux gate path"
grep -Fq "$SWIFT_MACOS_XCODE_PATH" "$CI_WORKFLOW" || fail "CI must select the pinned macOS Swift toolchain"
grep -Eq 'phranck/tuikit-docs|docs[.]tuikit[.]dev|DOCS_DEPLOY_KEY|peaceiris/actions-gh-pages' "$CI_WORKFLOW" \
    && fail "CI contains the retired TUIkit documentation destination"

REFERENCE_JOB_COUNT="$(count_job_blocks "$CI_WORKFLOW" "reference-snapshots")"
[[ "$REFERENCE_JOB_COUNT" == "1" ]] || fail "CI must define exactly one reference-snapshots job"
REFERENCE_JOB_BLOCK="$(extract_job_block "$CI_WORKFLOW" "reference-snapshots")"
grep -Fq 'name: "Legacy TUIkit regression: SwiftUI reference snapshots"' <<< "$REFERENCE_JOB_BLOCK" \
    || fail "reference snapshots must be named as legacy TUIkit regression evidence"
grep -Fq "runs-on: $SWIFTUI_REFERENCE_RUNNER" <<< "$REFERENCE_JOB_BLOCK" \
    || fail "reference snapshots must run on $SWIFTUI_REFERENCE_RUNNER"
grep -Fq "$SWIFTUI_REFERENCE_XCODE_PATH" <<< "$REFERENCE_JOB_BLOCK" \
    || fail "reference snapshots must select the pinned Xcode"
grep -Fq 'generate-swiftui-reference-snapshots.sh' <<< "$REFERENCE_JOB_BLOCK" \
    || fail "reference snapshots must use the reviewed orchestrator"
grep -Fq 'name: swiftui-reference-snapshots' <<< "$REFERENCE_JOB_BLOCK" \
    || fail "reference snapshots must upload the stable artifact"
grep -Fq '${{ runner.temp }}' <<< "$REFERENCE_JOB_BLOCK" \
    || fail "reference snapshots must use runner.temp for artifact output"

MACOS_JOB_BLOCK="$(extract_job_block "$CI_WORKFLOW" "macos")"
LINUX_JOB_BLOCK="$(extract_job_block "$CI_WORKFLOW" "linux")"
grep -Fq 'name: SwiftTUI macOS and legacy TUIkit regression' <<< "$MACOS_JOB_BLOCK" \
    || fail "macOS CI must distinguish SwiftTUI from legacy TUIkit regression evidence"
grep -Fq 'name: SwiftTUI Linux and legacy TUIkit regression' <<< "$LINUX_JOB_BLOCK" \
    || fail "Linux CI must distinguish SwiftTUI from legacy TUIkit regression evidence"
grep -Fq 'TUIKIT_API_SNAPSHOT_OUTPUT: ${{ runner.temp }}/tuikit-macos-snapshots' \
    <<< "$MACOS_JOB_BLOCK" || fail "macOS CI must export TUIkit API snapshots"
grep -Fq 'name: tuikit-macos-snapshots' <<< "$MACOS_JOB_BLOCK" \
    || fail "macOS CI must upload TUIkit API snapshots"
grep -Fq "SWIFTTUI_TAGGED_VERSION: \${{ startsWith(github.ref, 'refs/tags/') && github.ref_name || '' }}" \
    <<< "$MACOS_JOB_BLOCK" || fail "macOS CI must verify tagged SwiftPM consumers on tag builds"
grep -Fq 'tar -czf "$RUNNER_TEMP/docc-output.tar.gz" -C docc-output .' <<< "$MACOS_JOB_BLOCK" \
    || fail "macOS CI must archive DocC output before artifact upload"
grep -Fq 'path: ${{ runner.temp }}/docc-output.tar.gz' <<< "$MACOS_JOB_BLOCK" \
    || fail "macOS CI must upload the portable DocC archive"
grep -Fq 'name: swifttui-docc-output' <<< "$MACOS_JOB_BLOCK" \
    || fail "macOS CI must identify the DocC artifact as SwiftTUI output"
grep -Fq 'if-no-files-found: error' <<< "$MACOS_JOB_BLOCK" \
    || fail "macOS CI must fail when a required artifact is missing"
grep -Fq 'TUIKIT_API_SNAPSHOT_OUTPUT: ${{ runner.temp }}/tuikit-linux-snapshots' \
    <<< "$LINUX_JOB_BLOCK" || fail "Linux CI must export TUIkit API snapshots"
grep -Fq 'name: tuikit-linux-snapshots' <<< "$LINUX_JOB_BLOCK" \
    || fail "Linux CI must upload TUIkit API snapshots"
grep -Fq "SWIFTTUI_TAGGED_VERSION: \${{ startsWith(github.ref, 'refs/tags/') && github.ref_name || '' }}" \
    <<< "$LINUX_JOB_BLOCK" || fail "Linux CI must verify tagged SwiftPM consumers on tag builds"

API_JOB_COUNT="$(count_job_blocks "$CI_WORKFLOW" "api-compatibility")"
[[ "$API_JOB_COUNT" == "1" ]] || fail "CI must define exactly one api-compatibility job"
API_JOB_BLOCK="$(extract_job_block "$CI_WORKFLOW" "api-compatibility")"
grep -Fq 'name: Legacy TUIkit API compatibility regression' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must be named as legacy TUIkit regression evidence"
grep -Fq 'needs: [reference-snapshots, macos, linux, performance]' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must require all snapshot producers and SwiftTUI performance"
grep -Fq 'name: swiftui-reference-snapshots' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must download the reference snapshots"
grep -Fq 'name: tuikit-macos-snapshots' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must download the macOS snapshots"
grep -Fq 'name: tuikit-linux-snapshots' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must download the Linux snapshots"
grep -Fq 'assemble-api-snapshot-set.sh' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must assemble the cross-platform TUIkit set"
grep -Fq 'verify-compatibility-owner-registry.sh' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must verify owner issue metadata"
grep -Fq 'name: api-compatibility-inputs' <<< "$API_JOB_BLOCK" \
    || fail "API compatibility must upload the assembled inputs"

PERFORMANCE_JOB_COUNT="$(count_job_blocks "$CI_WORKFLOW" "performance")"
[[ "$PERFORMANCE_JOB_COUNT" == "1" ]] || fail "CI must define exactly one performance job"
PERFORMANCE_JOB_BLOCK="$(extract_job_block "$CI_WORKFLOW" "performance")"
grep -Fq 'name: SwiftTUI release performance gate' <<< "$PERFORMANCE_JOB_BLOCK" \
    || fail "performance CI must use the SwiftTUI release identity"
grep -Fq 'source scripts/toolchain.env' <<< "$PERFORMANCE_JOB_BLOCK" \
    || fail "performance CI must load the pinned toolchain configuration"
grep -Fq 'sudo xcode-select --switch "$SWIFT_MACOS_XCODE_PATH"' <<< "$PERFORMANCE_JOB_BLOCK" \
    || fail "performance CI must select the pinned macOS Swift toolchain"
grep -Fq 'swift --version | grep -F "Swift version $SWIFT_VERSION"' <<< "$PERFORMANCE_JOB_BLOCK" \
    || fail "performance CI must assert the pinned Swift version"
grep -Fq './scripts/swifttui-benchmark.sh' <<< "$PERFORMANCE_JOB_BLOCK" \
    || fail "performance CI must run the SwiftTUI benchmark gate"
grep -Eq '^[[:space:]]+(if|continue-on-error):' <<< "$PERFORMANCE_JOB_BLOCK" \
    && fail "SwiftTUI performance CI must be unconditional and mandatory"

grep -Fq 'lint --strict --no-cache' "$QUALITY_GATE" || fail "SwiftLint must be strict with caching disabled"
grep -Fq -- '-warnings-as-errors' "$QUALITY_GATE" || fail "compiler warnings must be fatal"
grep -Fq 'generate-documentation.sh' "$QUALITY_GATE" || fail "quality gate must include DocC"
grep -Fq -- '--warnings-as-errors' "$DOCC_SCRIPT" || fail "DocC warnings must be fatal"
grep -Fq 'swift-symbolgraph-extract' "$DOCC_SCRIPT" || fail "DocC must use the pinned toolchain symbol extractor"
grep -Fq -- '-experimental-allowed-reexported-modules=TUIFoundation,TUITerminal,TUIRenderer,TUIViewGraph,TUILayout,TUIAnimation,TUIControls,TUIDesign,TUIRichText,TUIAgentUI,TUIRuntime' \
    "$DOCC_SCRIPT" || fail "DocC must include the public re-exported modules"
grep -Fq -- '--target SwiftTUI' "$DOCC_SCRIPT" || fail "DocC must build the SwiftTUI target"
grep -Fq -- '-module-name SwiftTUI' "$DOCC_SCRIPT" || fail "DocC must extract the SwiftTUI module"
grep -Fq 'convert Sources/SwiftTUI/SwiftTUI.docc' "$DOCC_SCRIPT" || fail "DocC must compile the authoritative catalog"
grep -Fq '/documentation/swifttui/' "$DOCC_SCRIPT" || fail "DocC must redirect to the SwiftTUI documentation route"
grep -Fq -- '-Xswiftc -warnings-as-errors' "$DOCC_SCRIPT" || fail "DocC's module build must reject compiler warnings"
grep -Fq 'python3' "$DOCC_SCRIPT" && fail "DocC must not require tools absent from the pinned Linux image"

echo "CI configuration is deterministic"
