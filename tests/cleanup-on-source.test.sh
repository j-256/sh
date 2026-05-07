#!/bin/bash
# cleanup-on-source.test.sh - Verify scripts don't leak functions or variables
# when sourced
# shellcheck source-path=SCRIPTDIR disable=SC2329,SC2016
#
# Every script in /repo/sh is designed to be either executed or sourced --
# sourcing must not pollute the caller's shell with inner functions or
# top-level variables. This test sources each bash script with --help
# (the only universally safe arg) and asserts that the set of defined
# functions and variables before and after sourcing is identical
#
# Pre-flight: each script is grepped for a --help case branch before being
# sourced. Scripts without --help are reported as failures rather than
# silently skipped -- the convention requires --help, and falling through
# to a script's real logic during a test run could spawn subprocesses,
# write files, or hit the network

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Test bash scripts only: shebang must be /bin/bash or /usr/bin/env bash
# Skips render-md (node), the .md/.sh/.json/.bak files at the repo root,
# and any subdirectories
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

# Pre-flight: confirm the script handles --help via a case-branch. The closing
# `)` distinguishes a real handler from a help-text echo line. Both `-h|--help)`
# and `--help|-h)` orderings are accepted, plus a bare `--help)`
_has_help_handler() {
    grep -qE '(^|[^a-zA-Z0-9_-])(-h|--help)([| ]+(-h|--help))?\)' "$1"
}

# Source $script with --help in a clean subshell, diff the function and
# variable namespaces before/after, and emit any leaks on stdout. One
# leak line per category, prefixed FUNCS: or VARS:
_collect_leaks() {
    local script="$1"
    /bin/bash <<EOF
funcs_before=\$(declare -F | awk '{print \$3}' | sort)
vars_before=\$(compgen -v | sort)
. '$script' --help >/dev/null 2>&1
funcs_after=\$(declare -F | awk '{print \$3}' | sort)
vars_after=\$(compgen -v | sort)
echo "FUNCS:"
comm -13 <(echo "\$funcs_before") <(echo "\$funcs_after")
echo "VARS:"
comm -13 <(echo "\$vars_before") <(echo "\$vars_after")
EOF
}

# --- test cases ---

test_no_leaks_on_source() {
    # Single sweeping test: walk every bash script in the repo, source it
    # with --help, and assert nothing leaks. One assertion per script keeps
    # failure messages specific
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue

        local name
        name="$(basename "$script")"

        if ! _has_help_handler "$script"; then
            _fail "$name: missing --help handler"
            continue
        fi

        local result
        local funcs
        local vars
        result="$(_collect_leaks "$script")"
        # Filter out the helper's own variables that get recorded as "after"
        # because they were declared inside the EOF heredoc subshell
        funcs="$(echo "$result" | sed -n '/^FUNCS:/,/^VARS:/p' | sed '1d;$d')"
        vars="$(echo "$result" | sed -n '/^VARS:/,$p' | sed '1d' | grep -vE '^(funcs_before|funcs_after|vars_before|vars_after)$')"

        if [ -z "$funcs" ] && [ -z "$vars" ]; then
            _ok "$name: no leaks on source"
        else
            local msg="$name leaked:"
            [ -n "$funcs" ] && msg="$msg funcs=[$(printf '%s' "$funcs" | tr '\n' ' ')]"
            [ -n "$vars" ] && msg="$msg vars=[$(printf '%s' "$vars" | tr '\n' ' ')]"
            _fail "$msg"
        fi
    done
}

# --- run ---

run_tests "$@"
