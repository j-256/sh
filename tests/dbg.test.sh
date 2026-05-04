#!/bin/bash
# dbg.test.sh - Tests for dbg
# shellcheck source-path=SCRIPTDIR disable=SC2329,SC2016
#
# dbg must be sourced (not executed) to do its job -- reading the caller's
# shell variables. Tests use run_script_sourced to source it in a subshell
# and capture its stderr output (dbg writes all of its output to stderr
# since the script itself is the debug tool).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../dbg"

# Run dbg via a sourced wrapper that first sets up caller-shell state,
# then sources dbg. $1 is a bash snippet defining caller-shell state;
# remaining args are passed to dbg. stderr is captured in $TEST_DIR/stderr.
run_dbg() {
    local setup="$1"; shift
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" SETUP="$setup" \
        /bin/bash -c '
            eval "$SETUP"
            script="$1"; shift
            . "$script" "$@"
        ' bash "$UNDER_TEST" "$@" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# --- test cases ---

test_help_long() {
    run_script_sourced --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has ENVIRONMENT" "ENVIRONMENT"
    assert_stdout_contains "help mentions sourcing" "sourced"
    assert_stdout_contains "help mentions __DBG_STRICT" "__DBG_STRICT"
}

test_help_short() {
    run_script_sourced -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_executed_rejected() {
    run_script VAR
    assert_rc "executed exits 2" 2
    assert_stderr_contains "explains requirement" "Must be sourced"
    assert_stderr_contains "refers to help" "Run \`dbg -h\` for usage"
}

test_executed_help_long() {
    run_script --help
    assert_rc "executed --help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help states sourced requirement" "sourced"
}

test_executed_help_short() {
    run_script -h
    assert_rc "executed -h exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
}

test_scalar() {
    run_dbg 'name="alice"' name
    assert_rc "scalar exits 0" 0
    assert_stderr_contains "scalar prints assignment" 'name="alice"'
}

test_scalar_exported() {
    run_dbg 'export foo="bar"' foo
    assert_rc "exported exits 0" 0
    assert_stderr_contains "exported scalar prefixed with export" 'export foo="bar"'
}

test_unset_variable() {
    run_dbg '' missing
    assert_rc "unset exits 0" 0
    assert_stderr_contains "unset prints 'unset name'" "unset missing"
}

test_value_with_dollar_and_backtick() {
    # Values containing $ and ` must be escaped so the output line could be
    # safely re-sourced without invoking expansion.
    run_dbg 'v1="hello \$USER"; v2="cmd \`date\`"' v1 v2
    assert_rc "special chars exit 0" 0
    assert_stderr_contains "dollar escaped" 'v1="hello \$USER"'
    assert_stderr_contains "backtick escaped" 'v2="cmd \`date\`"'
}

test_value_with_esc_at() {
    # ESC bytes in arr[@] go through __dbg__q, which falls back to %q for
    # terminal safety
    run_dbg 'arr=($'"'"'\x1bred'"'"' "normal")' 'arr[@]'
    assert_rc "arr[@] with ESC exits 0" 0
    assert_stderr_contains "%q form used for ESC-containing element" "\$'\\Ered'"
    assert_stderr_contains "normal element still double-quoted" '"normal"'
}

test_value_with_newline_at() {
    # Newline is detected by `case [[:cntrl:]]` (unlike grep [[:cntrl:]], which
    # treats input as newline-separated records). The element must render as
    # $'line1\nline2' on one line, not as a literal multi-line double-quoted form
    run_dbg 'arr=($'"'"'line1\nline2'"'"' "normal")' 'arr[@]'
    assert_rc "arr[@] with newline exits 0" 0
    assert_stderr_contains "%q form used for newline-containing element" "\$'line1\\nline2'"
    assert_stderr_not_contains "no raw multi-line fragment" '"line1
line2"'
}

test_indexed_array_whole() {
    run_dbg 'arr=(a b "c d")' arr
    assert_rc "whole array exits 0" 0
    assert_stderr_contains "prints declare-p-derived form" '[0]="a"'
    assert_stderr_contains "includes spaced element" '[2]="c d"'
}

test_indexed_array_at() {
    # arr[@]: one quoted token per element, boundaries preserved.
    run_dbg 'arr=(a b "c d")' 'arr[@]'
    assert_rc "arr[@] exits 0" 0
    assert_stderr_contains "arr[@] tokens" 'arr[@]="a" "b" "c d"'
}

test_indexed_array_star() {
    # arr[*]: single joined value reflecting IFS.
    run_dbg 'arr=(a b c)' 'arr[*]'
    assert_rc "arr[*] exits 0" 0
    assert_stderr_contains "arr[*] single joined token" 'arr[*]="a b c"'
}

test_indexed_array_element() {
    run_dbg 'arr=(a b "c d")' 'arr[2]'
    assert_rc "element ref exits 0" 0
    assert_stderr_contains "element value quoted" 'arr[2]="c d"'
}

test_indexed_array_missing_element() {
    run_dbg 'arr=(a b c)' 'arr[99]'
    assert_rc "missing element exits 0" 0
    assert_stderr_contains "missing element reports unset" "unset arr[99]"
}

# Note: associative-array handling (declare -A, map[key] element refs) is
# implemented in dbg but not tested here because the test harness invokes
# /bin/bash (typically 3.2 on macOS) which doesn't support `declare -A`.
# The assoc-array code paths are structurally identical to the indexed-array
# paths tested above; they diverge only on the `-A` vs `-a` declare flag
# check that sets `__dbg__is_assoc_array`, which is purely classificatory.

test_subscript_on_non_array() {
    run_dbg 'scalar=x' 'scalar[0]'
    assert_rc "non-array subscript exits 0" 0
    assert_stderr_contains "rejects subscript on non-array" "is not an array"
}

test_malformed_brackets_only_open() {
    run_dbg 'arr=(a b)' 'arr['
    assert_rc "malformed exits 0" 0
    assert_stderr_contains "reports malformed" "malformed brackets"
}

test_malformed_brackets_only_close() {
    run_dbg 'arr=(a b)' 'arr]'
    assert_rc "malformed exits 0" 0
    assert_stderr_contains "reports malformed" "malformed brackets"
}

test_strict_rejects_command_substitution() {
    run_dbg 'export __DBG_STRICT=true' 'bad$(echo hi)'
    assert_rc "strict reject exits 0" 0
    assert_stderr_contains "strict rejects command sub" "Unsupported reference"
}

test_strict_rejects_backticks() {
    run_dbg 'export __DBG_STRICT=true' 'bad`x`'
    assert_rc "strict reject exits 0" 0
    assert_stderr_contains "strict rejects backticks" "Unsupported reference"
}

test_strict_allows_simple_ref() {
    run_dbg 'export __DBG_STRICT=true; name=ok' name
    assert_rc "strict allow exits 0" 0
    assert_stderr_contains "strict allows simple name" 'name="ok"'
}

test_multiple_refs_one_call() {
    run_dbg 'a=1; b=2; c=3' a b c
    assert_rc "multiple refs exit 0" 0
    assert_stderr_contains "first ref" 'a="1"'
    assert_stderr_contains "second ref" 'b="2"'
    assert_stderr_contains "third ref" 'c="3"'
}

test_no_args_sourced() {
    # Sourcing with no args is a no-op (empty loop); exit 0.
    run_script_sourced
    assert_rc "no args exits 0" 0
}

# --- run ---

run_tests "$@"
