#!/bin/bash
# curl-pipe.test.sh - Verify every script works when piped or process-substituted
#
# Three "no real filename" invocation shapes are covered:
#
#   1. Stdin pipe:   curl -s .../foo | bash
#        ${BASH_SOURCE[0]} is empty at top level, "bash" inside the function
#   2. Procsub exec: bash <(curl -s .../foo)
#        ${BASH_SOURCE[0]} is /dev/fd/N -- basename yields a digit
#   3. Procsub src:  . <(curl -s .../foo)   (prompt only: it must be sourced)
#        Same /dev/fd/N shape, different dispatch
#
# Guards against:
#   - Empty ${BASH_SOURCE[0]} at top level tripping the source-vs-execute
#     guard: `[ "${BASH_SOURCE[0]}" != "$0" ]` wrongly returns sourced,
#     firing `return` at top level ("return: can only `return' from a
#     function"). Covered by `[ -n "${BASH_SOURCE[0]}" ]`
#   - SCRIPT_NAME falling back to the interpreter ("bash") or a digit
#     ("63" from /dev/fd/63). Covered by the case pattern
#     `""|bash|sh|zsh|dash|[0-9]*`
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# Scripts to check. Excludes:
#   - render-md (doesn't use the wrapper-function boilerplate)
#   - snippets.sh (reference doc, not executable as-is)
#   - test-runner.sh (piping would recursively re-run the suite)
SCRIPTS=(
    bak cf-ddns cf-ips-subnets chrome-ua client-credentials
    colorize-url convert-size curl-timing dkim-pubkey dot-project
    dw-jwt explode find-zone-by-name gen-catalog generate-p12
    get git-add-nonsub git-backup httpcode inflate install-bash
    notify ods-usage pin-dns pkce progress
    prompt propfind-p12 pwa-prereqs genpw s
    screenshot-rename slow-server snippet spf-find-ip stats
    swap tsd unbak verify-p12
)

# Pipe a script's source into `bash -s -- -h`, capturing stdout/stderr/rc
# into $TEST_DIR. Simulates `curl -s URL | bash -s -- -h`
pipe_script() {
    local script="$1"
    cat "$SCRIPT_DIR/../$script" | /bin/bash -s -- -h \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Run a script via `bash <(cat script) -h`, capturing output. Simulates
# `bash <(curl -s URL) -h` -- BASH_SOURCE[0] is /dev/fd/N, not the filename
procsub_exec_script() {
    local script="$1"
    /bin/bash -c 'bash <(cat "$1") -h' bash "$SCRIPT_DIR/../$script" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Source a script via `cat script | bash -c '. /dev/stdin --help'`, capturing
# output. Exercises the "source path is a /dev/* pseudo-file, basename isn't
# a real filename" codepath -- the same class of SCRIPT_NAME fallback concern
# as `. <(curl ...)` but via /dev/stdin, which works on bash 3.2
#
# We deliberately avoid `. <(cat script) --help` here: bash 3.2 silently
# fails process substitution when invoked inside `bash -c '...'`, producing
# no output and rc 0. The user-facing form in the README (`. <(curl ...)`
# from an interactive shell) does work on 3.2 -- it's the `-c` wrapper that
# breaks, and that wrapper is a test-harness artifact
#
# Only meaningful for scripts that must be sourced (prompt). Every other
# script works sourced or executed via the source/execute exit handler, so
# the procsub-exec case already covers them
procsub_source_script() {
    local script="$1"
    cat "$SCRIPT_DIR/../$script" | /bin/bash -c '. /dev/stdin --help' \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Shared assertions: help exits 0, mentions the canonical name, and
# doesn't leak an interpreter name or digit in place of SCRIPT_NAME
assert_help_clean() {
    local s="$1"
    local label="$2"
    local combined
    assert_rc "$s: $label exits 0" 0
    assert_stderr_not_contains "$s: $label: no 'return: can only' error" "return: can only"
    combined="$(get_stdout)$(get_stderr)"
    assert_contains "$s: $label: help mentions '$s'" "$combined" "$s"
    assert_not_contains "$s: $label: help does not say 'bash'" "$combined" "  bash "
    # /dev/fd/N would leak as a digit-only token where SCRIPT_NAME should be
    # Grep for "NAME\n  <digit>" and "SYNOPSIS\n  <digit>" shapes
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  1'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  2'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  3'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  4'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  5'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  6'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  7'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  8'
    assert_not_contains "$s: $label: help name line is not a digit" "$combined" $'NAME\n  9'
}

test_all_scripts_pipe_cleanly() {
    local s
    for s in "${SCRIPTS[@]}"; do
        pipe_script "$s"
        assert_help_clean "$s" "stdin-pipe"
    done
}

test_all_scripts_procsub_exec_cleanly() {
    local s
    for s in "${SCRIPTS[@]}"; do
        procsub_exec_script "$s"
        assert_help_clean "$s" "procsub-exec"
    done
}

test_prompt_procsub_source_cleanly() {
    # prompt is the only script that must be sourced. The README advertises
    # `. <(curl ... | bash)` for one-shot use, so the procsub-source path
    # needs to preserve SCRIPT_NAME in --help output too
    procsub_source_script "prompt"
    assert_help_clean "prompt" "procsub-source"
}

run_tests "$@"
