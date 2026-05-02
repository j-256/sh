#!/bin/bash
# test-runner.sh - Run all .test.sh files in this directory
#
# Usage:
#   test-runner.sh [options] [name]...
#
# Options:
#   -v          Verbose (pass through to test files)
#   -h, --help  Show help message

_test_runner() {
    local SCRIPT_NAME
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    case "${BASH_SOURCE[0]}" in /dev/*|/proc/*) SCRIPT_NAME="" ;; esac
    case "$SCRIPT_NAME" in ""|bash|sh|zsh|dash) SCRIPT_NAME="test-runner.sh" ;; esac

    _show_help() {
        local s
        [ -t 1 ] && s="$(tput smul 2>/dev/null || echo '')"
        local r
        [ -t 1 ] && r="$(tput rmul 2>/dev/null || echo '')"
        echo "NAME"
        echo "  $SCRIPT_NAME - run all .test.sh files"
        echo "SYNOPSIS"
        echo "  $SCRIPT_NAME [${s}options${r}] [${s}name${r}]..."
        echo "DESCRIPTION"
        echo "  Finds and runs all .test.sh files in the same directory."
        echo "  If one or more names are given, only runs tests whose script name"
        echo "  (basename minus .test.sh) exactly matches one of them."
        echo "OPTIONS"
        echo "  -v          Pass -v (verbose) to each test file"
        echo "  -h, --help  Show this help message"
    }

    __unset() {
        unset -f __unset _show_help
    }
    trap '__unset || echo "'"$SCRIPT_NAME"' trap failed!" >&2; trap - RETURN' RETURN

    local verbose=""
    local names=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) _show_help; return 0 ;;
            -v) verbose="-v" ;;
            *) names+=("$1") ;;
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

        local filename
        filename="$(basename "$test_file")"

        # With one or more names, only run tests whose filename matches
        # <name>.test.sh. Exact match avoids the substring-glob footgun where
        # short inputs like `s` would match every file.
        if [ "${#names[@]}" -gt 0 ]; then
            local matched=0
            local n
            for n in "${names[@]}"; do
                if [ "$filename" = "$n.test.sh" ]; then matched=1; break; fi
            done
            [ "$matched" -eq 1 ] || continue
        fi

        echo "--- $filename ---"

        local rc=0
        /bin/bash "$test_file" $verbose || rc=$?

        if [ "$rc" -eq 0 ]; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
            failed_files="$failed_files  $filename"$'\n'
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
