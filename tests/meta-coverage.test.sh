#!/bin/bash
# meta-coverage.test.sh - Verify the tests/ directory is well-formed
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
#
# Checks the script<->test bijection in both directions, so neither a new
# script nor a new test can slip in unpaired:
#   1. Every bash script in the repo has a tests/<name>.test.sh
#   2. Every non-meta tests/<name>.test.sh has a matching bash script
#
# A test named meta-*.test.sh is exempt from direction 2: it is cross-cutting
# and intentionally has no eponymous script. That exemption is the whole reason
# these files are named meta-* rather than masquerading as tests for scripts
# called "coverage", "cleanup-on-source", or "curl-pipe".
#
# Also checks the executable-bit convention: test files are execute-only and
# carry +x; test-runner.sh (the entry point) is +x; test-helpers.sh (sourced,
# never run) is -x. This mirrors the repo-wide rule that -x marks a source-only
# file (dbg, prompt).
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Test bash scripts only: shebang must be /bin/bash or /usr/bin/env bash.
# Skips render-md (node), the .md/.sh/.json files at the repo root, and any
# subdirectories. Identical to the filter in meta-cleanup-on-source.test.sh
_is_bash_script() {
    local file="$1"
    [ -f "$file" ] || return 1
    case "$(basename "$file")" in *.md|*.sh|*.json) return 1 ;; esac
    local first_line
    first_line="$(head -1 "$file")"
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash') return 0 ;;
        *) return 1 ;;
    esac
}

# --- test cases ---

test_every_script_has_a_test() {
    # Walk every bash script in the repo; each must have tests/<name>.test.sh.
    # One assertion per script keeps a missing test's failure message specific
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local name
        name="$(basename "$script")"
        assert_file_exists "$name: has a test" "$SCRIPT_DIR/$name.test.sh"
    done
}

test_every_test_has_a_script() {
    # Walk every test file; each must correspond to a bash script of the same
    # name -- except meta-*.test.sh, which are cross-cutting by design
    local test_file
    for test_file in "$SCRIPT_DIR"/*.test.sh; do
        [ -f "$test_file" ] || continue
        local name
        name="$(basename "$test_file" .test.sh)"
        case "$name" in meta-*) continue ;; esac
        if _is_bash_script "$REPO_DIR/$name"; then
            _ok "$name.test.sh: has a script"
        else
            _fail "$name.test.sh: no matching bash script (../$name) -- rename to meta-$name.test.sh if cross-cutting"
        fi
    done
}

test_test_files_are_executable() {
    # Test files are execute-only (run via test-runner.sh or `bash <file>`) and
    # must not be sourced -- run_tests refuses a sourced file. They carry +x so
    # the bit does not falsely signal "source me" the way -x does elsewhere
    local test_file
    for test_file in "$SCRIPT_DIR"/*.test.sh; do
        [ -f "$test_file" ] || continue
        local name
        name="$(basename "$test_file")"
        if [ -x "$test_file" ]; then
            _ok "$name: executable"
        else
            _fail "$name: not executable -- run: chmod +x tests/$name"
        fi
    done
}

test_infra_perms_match_role() {
    # The two non-test infra files encode the repo's +x=execute / -x=source rule:
    # test-runner.sh is the entry point (+x); test-helpers.sh is sourced (-x)
    if [ -x "$SCRIPT_DIR/test-runner.sh" ]; then
        _ok "test-runner.sh: executable (entry point)"
    else
        _fail "test-runner.sh: not executable -- run: chmod +x tests/test-runner.sh"
    fi
    if [ -x "$SCRIPT_DIR/test-helpers.sh" ]; then
        _fail "test-helpers.sh: executable -- it is sourced, not run; run: chmod -x tests/test-helpers.sh"
    else
        _ok "test-helpers.sh: not executable (sourced)"
    fi
}

# --- run ---

run_tests "$@"
