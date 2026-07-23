#!/bin/bash
# meta-curl-pipe.test.sh - Verify every script works when piped or process-substituted
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
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
#   - SCRIPT_NAME falling back to the interpreter ("bash"), a digit ("63"
#     from /dev/fd/63), or a bash-internal source sentinel ("main" for stdin
#     on bash 5.2+, "environment" under bash -c). Covered by the case pattern
#     `""|bash|sh|zsh|dash|[0-9]*` plus the path-based /dev/* pre-check, and
#     regression-checked here by pinning the -h NAME line to the script name
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Test bash scripts only: shebang must be /bin/bash or /usr/bin/env bash.
# Skips render-md (node), the .md/.sh/.json files at the repo root, and any
# subdirectories. Identical to the filter in meta-coverage.test.sh
_is_bash_script() {
    local file="$1"
    [ -f "$file" ] || return 1
    case "$(basename "$file")" in *.md|*.sh|*.json) return 1 ;; esac
    local first_line; first_line="$(head -1 "$file")"
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash') return 0 ;;
        *) return 1 ;;
    esac
}

# Bash scripts to skip these checks, as a space-padded membership string
# (e.g. " foo bar "). Empty today: every bash script in the repo survives
# `<src> | bash -- -h` in all three shapes below. The historical exclusions are
# now filtered structurally rather than hand-listed:
#   - render-md      node shebang, not bash -- _is_bash_script rejects it
#   - snippets.sh    .sh extension -- _is_bash_script rejects it
#   - test-runner.sh lives in tests/, never reached by the repo-root walk
# Add a name here only if a real bash script genuinely cannot be -h-piped
EXCLUDE=" "
_is_excluded() { case "$EXCLUDE" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

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

# Extract the word following the NAME heading in a help block: the line under
# NAME is "  <script> - description", so strip the indent and take the first
# field. Empty if there is no NAME section (tsd/snippet use a Usage-first
# format and have no NAME heading)
_help_name_word() {
    awk 'p { sub(/^[[:space:]]+/, ""); print $1; exit } /^NAME$/ { p = 1 }'
}

# Shared assertions: help exits 0, names the script, and doesn't leak an
# interpreter name, a /dev/fd digit, or a BASH_SOURCE sentinel (main,
# environment) in place of SCRIPT_NAME
assert_help_clean() {
    local s="$1"
    local label="$2"
    local combined
    local name_word
    assert_rc "$s: $label exits 0" 0
    assert_stderr_not_contains "$s: $label: no 'return: can only' error" "return: can only"
    combined="$(get_stdout)$(get_stderr)"
    assert_contains "$s: $label: help mentions '$s'" "$combined" "$s"
    # Positively pin the NAME line to the script's own name. This subsumes the
    # old not-a-digit guards and also catches interpreter names ("bash"), the
    # /dev/fd/N digit, and the BASH_SOURCE sentinels ("main" on bash 5.2 stdin,
    # "environment" from bash -c) that a broken SCRIPT_NAME fallback would emit.
    # Scripts whose help has no NAME heading (tsd, snippet use a Usage-first
    # printf format) yield an empty word and rely on the "mentions" check above
    name_word="$(printf '%s' "$combined" | _help_name_word)"
    if [ -n "$name_word" ]; then
        assert_eq "$s: $label: NAME line names the script" "$name_word" "$s"
    fi
}

test_all_scripts_pipe_cleanly() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        pipe_script "$s"
        assert_help_clean "$s" "stdin-pipe"
    done
}

test_all_scripts_procsub_exec_cleanly() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
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
