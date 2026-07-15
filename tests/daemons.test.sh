#!/bin/bash
# daemons.test.sh - Tests for daemons
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../daemons"

# All tests point config at the temp dir so nothing real is touched
run_script() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        DAEMONS_LOG_DIR="$TEST_DIR/log" \
        DAEMONS_REGISTRY="$TEST_DIR/daemons.tsv" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

test_help_exits_0() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help lists append" "append"
}

test_unknown_subcommand() {
    run_script bogus
    assert_rc "unknown subcommand exits 2" 2
    assert_stderr_contains "names the bad subcommand" "bogus"
}

test_no_subcommand() {
    run_script
    assert_rc "no subcommand exits 2" 2
}

run_tests "$@"
