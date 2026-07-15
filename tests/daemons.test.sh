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

test_append_writes_valid_json() {
    run_script append reconcile trigger "watchpath fired"
    assert_rc "append exits 0" 0
    assert_file_exists "log created" "$TEST_DIR/log/reconcile.log"
    local line; line="$(cat "$TEST_DIR/log/reconcile.log")"
    assert_eq "one record" "1" "$(printf '%s\n' "$line" | grep -c .)"
    assert_eq "daemon field" "reconcile" "$(printf '%s' "$line" | jq -r .daemon)"
    assert_eq "event field" "trigger" "$(printf '%s' "$line" | jq -r .event)"
    assert_eq "detail field" "watchpath fired" "$(printf '%s' "$line" | jq -r .detail)"
    assert_contains "ts is ISO-UTC" "$(printf '%s' "$line" | jq -r .ts)" "T"
}

test_append_multiline_detail_roundtrips() {
    run_script append reconcile error "$(printf 'line1\nline2\twith tab')"
    assert_rc "append exits 0" 0
    local got; got="$(jq -r .detail "$TEST_DIR/log/reconcile.log")"
    assert_eq "newline+tab preserved" "$(printf 'line1\nline2\twith tab')" "$got"
    # The physical file is still ONE line (newline is inside the JSON string)
    assert_eq "still one physical line" "1" "$(grep -c . "$TEST_DIR/log/reconcile.log")"
}

test_append_appends_not_truncates() {
    run_script append reconcile trigger "first"
    run_script append reconcile noop "second"
    assert_eq "two records" "2" "$(grep -c . "$TEST_DIR/log/reconcile.log")"
}

test_append_empty_detail_ok() {
    run_script append reconcile trigger
    assert_rc "append without detail exits 0" 0
    assert_eq "detail empty string" "" "$(jq -r .detail "$TEST_DIR/log/reconcile.log")"
}

test_append_bad_event_rejected() {
    run_script append reconcile bogus "x"
    assert_rc "invalid event exits 2" 2
    assert_stderr_contains "names valid events" "trigger"
}

test_append_missing_args() {
    run_script append reconcile
    assert_rc "missing event exits 2" 2
}

test_append_detail_stdin() {
    printf 'big\nmultiline\npayload' | run_script append reconcile error --detail-stdin
    assert_rc "stdin detail exits 0" 0
    assert_eq "stdin detail captured" "$(printf 'big\nmultiline\npayload')" "$(jq -r .detail "$TEST_DIR/log/reconcile.log")"
}

run_tests "$@"
