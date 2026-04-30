#!/bin/bash
# test-runner.sh - Run all .test.sh files in this directory
#
# Usage:
#   test-runner.sh [options] [pattern]
#
# Options:
#   -v          Verbose (pass through to test files)
#   -h, --help  Show help message

_test_runner() {
    local SCRIPT_NAME
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    case "$SCRIPT_NAME" in ""|bash|sh|zsh|dash) SCRIPT_NAME="test-runner.sh" ;; esac

    _show_help() {
        local s
        [ -t 1 ] && s="$(tput smul 2>/dev/null || echo '')"
        local r
        [ -t 1 ] && r="$(tput rmul 2>/dev/null || echo '')"
        echo "NAME"
        echo "  $SCRIPT_NAME - run all .test.sh files"
        echo "SYNOPSIS"
        echo "  $SCRIPT_NAME [${s}options${r}] [${s}pattern${r}]"
        echo "DESCRIPTION"
        echo "  Finds and runs all .test.sh files in the same directory."
        echo "  If a pattern is given, only runs files matching *pattern*.test.sh."
        echo "OPTIONS"
        echo "  -v          Pass -v (verbose) to each test file"
        echo "  -h, --help  Show this help message"
    }

    __unset() {
        unset -f __unset _show_help
    }
    trap '__unset || echo "'"$SCRIPT_NAME"' trap failed!" >&2; trap - RETURN' RETURN

    local verbose=""
    local patterns=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) _show_help; return 0 ;;
            -v) verbose="-v" ;;
            *) patterns+=("$1") ;;
        esac
        shift
    done

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local pass=0
    local fail=0
    local failed_files=""

    local test_file
    for test_file in "$script_dir"/*.test.sh; do
        [ -f "$test_file" ] || continue

        # With one or more patterns, run a test iff its script name (basename
        # minus .test.sh) matches one of them exactly. Exact match avoids the
        # substring-glob footgun where short patterns like `s` match every file.
        if [ "${#patterns[@]}" -gt 0 ]; then
            local name
            local matched=0
            local p
            name="$(basename "$test_file" .test.sh)"
            for p in "${patterns[@]}"; do
                if [ "$name" = "$p" ]; then matched=1; break; fi
            done
            [ "$matched" -eq 1 ] || continue
        fi

        local name
        name="$(basename "$test_file")"
        echo "--- $name ---"

        local rc=0
        /bin/bash "$test_file" $verbose || rc=$?

        if [ "$rc" -eq 0 ]; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
            failed_files="$failed_files  $name"$'\n'
        fi
    done

    local total=$((pass + fail))
    echo ""
    echo "=== $SCRIPT_NAME ==="
    echo "$total files: $pass passed, $fail failed"

    if [ "$fail" -ne 0 ]; then
        echo ""
        echo "Failed:"
        printf '%s' "$failed_files"
        return 1
    fi

    return 0
}

_test_runner "$@"
__test_runner_rc=$?
unset -f _test_runner
if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
    eval "unset __test_runner_rc; return $__test_runner_rc"
fi
eval "unset __test_runner_rc; exit $__test_runner_rc"
