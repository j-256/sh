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

# Seed helper: write records directly (bypass append) with controlled timestamps
seed_log() {
    local name="$1"; shift
    mkdir -p "$TEST_DIR/log"
    printf '%s\n' "$@" >> "$TEST_DIR/log/$name.log"
}

test_query_filters_by_event() {
    seed_log reconcile \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"trigger","detail":"a"}' \
        '{"ts":"2026-07-15T10:00:01Z","daemon":"reconcile","event":"error","detail":"boom"}'
    run_script query reconcile --event error
    assert_rc "query exits 0" 0
    assert_eq "one match" "1" "$(get_stdout | grep -c .)"
    assert_eq "it's the error" "boom" "$(get_stdout | jq -r .detail)"
}

test_query_since() {
    seed_log reconcile \
        '{"ts":"2026-07-14T10:00:00Z","daemon":"reconcile","event":"noop","detail":"old"}' \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"noop","detail":"new"}'
    run_script query reconcile --since 2026-07-15
    assert_eq "only new" "new" "$(get_stdout | jq -r .detail)"
}

test_query_all_merges() {
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"noop","detail":"r"}'
    seed_log screenshot-rename '{"ts":"2026-07-15T11:00:00Z","daemon":"screenshot-rename","event":"change","detail":"s"}'
    run_script query --all
    assert_eq "two records across daemons" "2" "$(get_stdout | grep -c .)"
}

test_query_jq_expr() {
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"change","detail":"3 deltas"}'
    run_script query reconcile --jq '.detail'
    assert_eq "jq expr applied" "3 deltas" "$(get_stdout | tr -d '"')"
}

test_query_missing_log_empty() {
    run_script query reconcile
    assert_rc "absent log exits 0" 0
    assert_eq "no output" "" "$(get_stdout)"
}

test_query_missing_value_errors() {
    run_script query reconcile --event
    assert_rc "trailing --event with no value exits 2" 2
    run_script query reconcile --since
    assert_rc "trailing --since with no value exits 2" 2
    run_script query reconcile --jq
    assert_rc "trailing --jq with no value exits 2" 2
}

test_query_event_equals_form() {
    seed_log reconcile \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"trigger","detail":"a"}' \
        '{"ts":"2026-07-15T10:00:01Z","daemon":"reconcile","event":"error","detail":"boom"}'
    run_script query reconcile --event=error
    assert_rc "equals-form query exits 0" 0
    assert_eq "one match" "1" "$(get_stdout | grep -c .)"
    assert_eq "equals-form matches the error record" "boom" "$(get_stdout | jq -r .detail)"
}

test_log_renders_human() {
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"change","detail":"3 deltas"}'
    run_script log reconcile
    assert_rc "log exits 0" 0
    assert_stdout_contains "shows ts" "2026-07-15T10:00:00Z"
    assert_stdout_contains "shows event upper" "CHANGE"
    assert_stdout_contains "shows detail" "3 deltas"
}

test_log_multiline_detail_indented() {
    seed_log reconcile "$(jq -cn '{ts:"2026-07-15T10:00:00Z",daemon:"reconcile",event:"error",detail:"line1\nline2"}')"
    run_script log reconcile
    assert_stdout_contains "first detail line" "line1"
    assert_stdout_contains "second detail line indented" "  line2"
}

test_log_all_merge_sorts() {
    seed_log reconcile '{"ts":"2026-07-15T11:00:00Z","daemon":"reconcile","event":"noop","detail":"later"}'
    seed_log screenshot-rename '{"ts":"2026-07-15T10:00:00Z","daemon":"screenshot-rename","event":"change","detail":"earlier"}'
    run_script log --all
    # "earlier" (10:00) must render before "later" (11:00)
    local out; out="$(get_stdout)"
    local first; first="$(printf '%s\n' "$out" | grep -n 'earlier' | head -1 | cut -d: -f1)"
    local second; second="$(printf '%s\n' "$out" | grep -n 'later' | head -1 | cut -d: -f1)"
    assert_eq "earlier before later" "1" "$([ "$first" -lt "$second" ] && echo 1 || echo 0)"
}

test_log_absent_is_empty() {
    run_script log reconcile
    assert_rc "absent log exits 0" 0
    assert_eq "no output" "" "$(get_stdout)"
}

test_log_empty_detail_renders_blank() {
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"noop","detail":""}'
    run_script log reconcile
    assert_rc "log exits 0" 0
    assert_stdout_not_contains "no literal null" "null"
    assert_stdout_contains "shows event upper" "NOOP"
}

write_shims() {
    # launchctl shim: `print <domain>/<label>` -- loaded if $TEST_DIR/loaded lists the label,
    # emitting a fake block with a "last exit code" line taken from $TEST_DIR/exit_<label> (default 0)
    cat > "$SHIM_DIR/launchctl" <<'SHIM'
#!/bin/bash
if [ "$1" = "print" ]; then
    label="${2##*/}"
    if [ -f "$TEST_DIR/loaded" ] && grep -qx "$label" "$TEST_DIR/loaded"; then
        ec=0; [ -f "$TEST_DIR/exit_$label" ] && ec="$(cat "$TEST_DIR/exit_$label")"
        printf '\tlast exit code = %s\n' "$ec"
        exit 0
    fi
    exit 1
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/launchctl"
}

# Registry with one daemon whose label is "usr.test.one"
seed_registry() {
    mkdir -p "$(dirname "$TEST_DIR/daemons.tsv")"
    cat > "$TEST_DIR/daemons.tsv" <<TSV
name	domain	label	script
one	gui/\$UID/	usr.test.one	$TEST_DIR/one.sh
TSV
    printf '#!/bin/bash\n' > "$TEST_DIR/one.sh"; chmod +x "$TEST_DIR/one.sh"
    printf 'usr.test.one\n' > "$TEST_DIR/loaded"
}

test_status_missing_registry() {
    run_script status
    assert_rc "missing registry exits 1" 1
    assert_stderr_contains "names the registry" "daemons.tsv"
}

test_status_reports_never_fired() {
    seed_registry
    run_script status
    assert_rc "status exits 0" 0
    assert_stdout_contains "names the daemon" "one"
    assert_stdout_contains "never fired when no log" "never fired"
}

test_status_reports_last_activity() {
    seed_registry
    seed_log one \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"one","event":"trigger","detail":"fired"}' \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"one","event":"change","detail":"did work"}'
    run_script status
    assert_stdout_contains "shows last outcome" "change"
    assert_stdout_contains "shows a count" "1 change"
}

test_check_all_healthy() {
    seed_registry
    run_script check
    assert_rc "healthy exits 0" 0
}

test_check_not_loaded() {
    seed_registry
    : > "$TEST_DIR/loaded" # nothing loaded
    run_script check
    assert_rc "not loaded exits 1" 1
    assert_stdout_contains "alerts not loaded" "not loaded"
}

test_check_missing_script() {
    seed_registry
    rm "$TEST_DIR/one.sh" # script baked into registry no longer exists
    run_script check
    assert_rc "missing script exits 1" 1
    assert_stdout_contains "alerts missing script" "missing script"
}

test_check_last_exit_nonzero() {
    seed_registry
    printf '3\n' > "$TEST_DIR/exit_usr.test.one"
    run_script check
    assert_rc "nonzero last exit exits 1" 1
    assert_stdout_contains "alerts last run failed" "last run failed"
    # Message names the numeric code cleanly, e.g. "(exit 3)"
    assert_stdout_contains "names the exit code" "exit 3"
}

# launchd reports "last exit code = (never exited)" for a loaded service that
# has not run yet this boot -- the state every WatchPaths daemon is in right
# after a restart, before its trigger first fires. That is NOT a failure, and
# the value is not an integer: parsing it as one must not fabricate an alert
test_check_never_exited_is_not_failure() {
    seed_registry
    printf '(never exited)\n' > "$TEST_DIR/exit_usr.test.one"
    run_script check
    assert_rc "never-exited is healthy" 0
    assert_stdout_not_contains "never-exited is not a failure" "last run failed"
}

run_tests "$@"
