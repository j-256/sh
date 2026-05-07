#!/bin/bash
# test-helpers.sh - Shared test infrastructure
#
# Source this at the top of every .test.sh file
# See TESTING.md for full documentation
# shellcheck disable=SC2016 # single-quoted inline bash scripts are intentional

_VERBOSE=0
_PASS=0
_FAIL=0

# --- output helpers ---

get_stdout() { cat "$TEST_DIR/stdout" 2>/dev/null; }
get_stderr() { cat "$TEST_DIR/stderr" 2>/dev/null; }
get_rc() { cat "$TEST_DIR/rc" 2>/dev/null; }

# --- assertions ---

_ok() {
    _PASS=$((_PASS + 1))
    [ "$_VERBOSE" -eq 1 ] && echo "[OK] $1"
    return 0
}

_fail() {
    _FAIL=$((_FAIL + 1))
    echo "[FAIL] $1" >&2
    return 1
}

assert_eq() {
    local label="$1"
    local got="$2"
    local want="$3"
    if [ "$got" = "$want" ]; then
        _ok "$label"
    else
        _fail "$label: expected '$want', got '$got'"
    fi
}

assert_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    case "$haystack" in
        *"$needle"*) _ok "$label" ;;
        *) _fail "$label: expected to contain '$needle'" ;;
    esac
}

assert_not_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    case "$haystack" in
        *"$needle"*) _fail "$label: expected NOT to contain '$needle'" ;;
        *) _ok "$label" ;;
    esac
}

assert_rc() {
    local label="$1"
    local want="$2"
    assert_eq "$label" "$(get_rc)" "$want"
}

assert_stdout_contains() {
    local label="$1"
    local needle="$2"
    assert_contains "$label" "$(get_stdout)" "$needle"
}

assert_stdout_not_contains() {
    local label="$1"
    local needle="$2"
    assert_not_contains "$label" "$(get_stdout)" "$needle"
}

assert_stderr_contains() {
    local label="$1"
    local needle="$2"
    assert_contains "$label" "$(get_stderr)" "$needle"
}

assert_stderr_not_contains() {
    local label="$1"
    local needle="$2"
    assert_not_contains "$label" "$(get_stderr)" "$needle"
}

assert_file_exists() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        _ok "$label"
    else
        _fail "$label: file not found: $path"
    fi
}

# --- script runner ---

run_script() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Source the script under test (instead of executing it). Use for scripts that
# must be sourced to mutate caller-shell state. Sets $0 to "bash" inside the
# subshell so the script's sourced-vs-executed check (typically $0 != bash)
# passes. stdout/stderr/rc captured the same way as run_script
run_script_sourced() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash -c 'script="$1"; shift; . "$script" "$@"' bash "$UNDER_TEST" "$@" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Source the script and capture one or more variable values that the script set
# in the caller's shell. Captured values land in $TEST_DIR/captured as NAME=VALUE
# lines (one per variable, in the order given)
# Usage: run_script_sourced_capture "VAR1 VAR2 ..." [args...]
run_script_sourced_capture() {
    local vars="$1"; shift
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" VARS="$vars" \
        /bin/bash -c '
            script="$1"; shift
            . "$script" "$@"
            rc=$?
            : > "$TEST_DIR/captured"
            for v in $VARS; do printf "%s=%s\n" "$v" "${!v}" >> "$TEST_DIR/captured"; done
            exit $rc
        ' bash "$UNDER_TEST" "$@" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

assert_captured() {
    local label="$1"
    local var="$2"
    local want="$3"
    local got
    got="$(grep "^${var}=" "$TEST_DIR/captured" 2>/dev/null | head -1 | cut -d= -f2-)"
    assert_eq "$label" "$got" "$want"
}

# --- test runner ---

run_tests() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -v) _VERBOSE=1 ;;
        esac
        shift
    done

    local root
    root="$(mktemp -d 2>/dev/null)" || root="$(mktemp -d -t test 2>/dev/null)"
    if [ ! -d "$root" ]; then
        echo "[ERR][test-helpers] Failed to create temp directory" >&2
        exit 1
    fi

    # Filter to non-exported test_ functions only (avoids picking up
    # exported test_* functions from the user's environment)
    local tests
    tests="$(declare -F | awk '$2 == "-f" && $3 ~ /^test_/ {print $3}')"
    if [ -z "$tests" ]; then
        echo "[ERR][test-helpers] No test_ functions found" >&2
        rm -rf "$root"
        exit 1
    fi

    # Use fd 3 so scripts that check [ -t 0 ] or read from stdin
    # don't consume the test name list
    local test_name
    while IFS= read -r test_name <&3; do
        TEST_DIR="$root/$test_name"
        SHIM_DIR="$TEST_DIR/shims"
        mkdir -p "$TEST_DIR" "$SHIM_DIR"

        if declare -f write_shims >/dev/null 2>&1; then
            write_shims
        fi

        "$test_name"
    done 3<<< "$tests"

    rm -rf "$root"

    local total=$((_PASS + _FAIL))
    echo ""
    echo "$total assertions: $_PASS passed, $_FAIL failed"

    if [ "$_FAIL" -ne 0 ]; then
        exit 1
    fi
    exit 0
}
