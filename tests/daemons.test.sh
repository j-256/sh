#!/bin/bash
# daemons.test.sh - Tests for daemons
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../daemons"

# All tests point config at the temp dir so nothing real is touched.
# VISUAL is cleared so the dev's own $VISUAL (e.g. "code --wait") can't leak into
# `registry --edit` and win over a test's inline EDITOR -- editor tests set EDITOR
# explicitly, so the environment is deterministic regardless of the dev's setup
run_script() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" VISUAL="" \
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

# --- short options + _expand_short_opts (query: -e/--event, -s/--since, -j/--jq, -a/--all) ---

test_query_short_event() {
    # -e is the short for --event; spaced form must reach the same filter
    seed_log reconcile \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"trigger","detail":"a"}' \
        '{"ts":"2026-07-15T10:00:01Z","daemon":"reconcile","event":"error","detail":"boom"}'
    run_script query reconcile -e error
    assert_rc "-e is --event" 0
    assert_eq "one match" "1" "$(get_stdout | grep -c .)"
    assert_eq "-e matched the error record" "boom" "$(get_stdout | jq -r .detail)"
}

test_query_short_event_glued() {
    # Glued form (-eerror) must split via _expand_short_opts "esj"
    seed_log reconcile \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"trigger","detail":"a"}' \
        '{"ts":"2026-07-15T10:00:01Z","daemon":"reconcile","event":"error","detail":"boom"}'
    run_script query reconcile -eerror
    assert_rc "-eerror glued splits via preprocessor" 0
    assert_eq "one match" "1" "$(get_stdout | grep -c .)"
    assert_eq "-eerror matched the error record" "boom" "$(get_stdout | jq -r .detail)"
}

test_query_short_since() {
    # -s is the short for --since
    seed_log reconcile \
        '{"ts":"2026-07-14T10:00:00Z","daemon":"reconcile","event":"noop","detail":"old"}' \
        '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"noop","detail":"new"}'
    run_script query reconcile -s 2026-07-15
    assert_rc "-s is --since" 0
    assert_eq "-s keeps only the new record" "new" "$(get_stdout | jq -r .detail)"
}

test_query_short_jq() {
    # -j is the short for --jq; glued form too since -j takes a value
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"change","detail":"3 deltas"}'
    run_script query reconcile -j.detail
    assert_rc "-j.detail glued is --jq" 0
    assert_eq "-j applied the jq expr" "3 deltas" "$(get_stdout | tr -d '"')"
}

test_query_short_all() {
    # -a is the flag short for --all (NOT a value-taker); merges every daemon
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"noop","detail":"r"}'
    seed_log screenshot-rename '{"ts":"2026-07-15T11:00:00Z","daemon":"screenshot-rename","event":"change","detail":"s"}'
    run_script query -a
    assert_rc "-a is --all" 0
    assert_eq "-a merges both daemons" "2" "$(get_stdout | grep -c .)"
}

test_append_load_event_ok() {
    run_script append reconcile load "bootstrapped gui/501/usr.cc-settings-reconcile"
    assert_rc "append load exits 0" 0
    local line; line="$(cat "$TEST_DIR/log/reconcile.log")"
    assert_eq "event is load" "load" "$(printf '%s' "$line" | jq -r .event)"
}

test_append_unload_event_ok() {
    run_script append reconcile unload "booted out"
    assert_rc "append unload exits 0" 0
    assert_eq "event is unload" "unload" \
        "$(jq -r .event "$TEST_DIR/log/reconcile.log")"
}

test_append_still_rejects_bogus_event() {
    run_script append reconcile bogus "x"
    assert_rc "bogus event still rejected" 2
    assert_stderr_contains "names valid events incl load/unload" "load|unload"
}

test_query_short_bundled_flag_then_value() {
    # -ae error bundles the -a flag with the value-taking -e: -a stays a flag,
    # -e swallows the following "error". A stray letter in the value-opts string
    # (or -a wrongly listed) would break this
    seed_log reconcile '{"ts":"2026-07-15T10:00:00Z","daemon":"reconcile","event":"noop","detail":"r"}'
    seed_log screenshot-rename '{"ts":"2026-07-15T11:00:00Z","daemon":"screenshot-rename","event":"error","detail":"boom"}'
    run_script query -ae error
    assert_rc "-ae error bundles flag + value-opt" 0
    assert_eq "one error across all daemons" "1" "$(get_stdout | grep -c .)"
    assert_eq "-ae kept the error record" "boom" "$(get_stdout | jq -r .detail)"
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

test_log_short_all() {
    # -a is the flag short for --all in log too; merge-sorts every daemon
    seed_log reconcile '{"ts":"2026-07-15T11:00:00Z","daemon":"reconcile","event":"noop","detail":"later"}'
    seed_log screenshot-rename '{"ts":"2026-07-15T10:00:00Z","daemon":"screenshot-rename","event":"change","detail":"earlier"}'
    run_script log -a
    assert_rc "-a is --all in log too" 0
    assert_stdout_contains "-a merged reconcile" "later"
    assert_stdout_contains "-a merged screenshot-rename" "earlier"
}

write_shims() {
    # launchctl shim:
    #   print <domain>/<label>       -- loaded if $TEST_DIR/loaded lists the label;
    #                                   emits a fake "last exit code" line
    #   bootstrap <domain> <plist>   -- adds the plist's basename-label to loaded
    #   bootout <domain>/<label>     -- removes the label from loaded
    cat > "$SHIM_DIR/launchctl" <<'SHIM'
#!/bin/bash
loaded="$TEST_DIR/loaded"
case "$1" in
    print)
        label="${2##*/}"
        if [ -f "$loaded" ] && grep -qx "$label" "$loaded"; then
            ec=0; [ -f "$TEST_DIR/exit_$label" ] && ec="$(cat "$TEST_DIR/exit_$label")"
            printf '\tlast exit code = %s\n' "$ec"
            exit 0
        fi
        exit 1 ;;
    bootstrap)
        # args: bootstrap <domain> <plist-path>; label = plist basename minus .plist
        plist="$3"; base="${plist##*/}"; label="${base%.plist}"
        touch "$loaded"
        grep -qx "$label" "$loaded" || printf '%s\n' "$label" >> "$loaded"
        exit 0 ;;
    bootout)
        # args: bootout <domain>/<label>
        label="${2##*/}"
        if [ -f "$loaded" ]; then
            grep -vx "$label" "$loaded" > "$loaded.tmp" 2>/dev/null || :
            mv "$loaded.tmp" "$loaded"
        fi
        exit 0 ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/launchctl"

    # sudo shim: record that it was called, then exec the rest (drops privilege
    # elevation but runs the real command, so the code path is exercised)
    cat > "$SHIM_DIR/sudo" <<'SHIM'
#!/bin/bash
touch "$TEST_DIR/sudo_called"
exec "$@"
SHIM
    chmod +x "$SHIM_DIR/sudo"

    # fake editor + open: record argv so tests can assert what was invoked with
    cat > "$SHIM_DIR/fakeeditor" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/editor_args"
SHIM
    chmod +x "$SHIM_DIR/fakeeditor"

    cat > "$SHIM_DIR/open" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/open_args"
SHIM
    chmod +x "$SHIM_DIR/open"
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

# Registry with one daemon carrying an explicit 5th plist column
seed_registry_5col() {
    mkdir -p "$(dirname "$TEST_DIR/daemons.tsv")"
    cat > "$TEST_DIR/daemons.tsv" <<TSV
name	domain	label	script	plist
one	gui/\$UID/	usr.test.one	$TEST_DIR/one.sh	$TEST_DIR/usr.test.one.plist
TSV
    printf '#!/bin/bash\n' > "$TEST_DIR/one.sh"; chmod +x "$TEST_DIR/one.sh"
    printf 'usr.test.one\n' > "$TEST_DIR/loaded"
}

test_status_5col_registry_not_corrupted() {
    seed_registry_5col
    run_script status
    assert_rc "5-col status exits 0" 0
    assert_stdout_contains "5-col row still names daemon" "one"
    assert_stdout_contains "5-col row still shows loaded" "loaded"
}

test_check_5col_registry_script_intact() {
    # If the 5th column folded into $script, the missing-script check would
    # see "$TEST_DIR/one.sh<TAB>$TEST_DIR/usr.test.one.plist" and wrongly flag it
    seed_registry_5col
    run_script check
    assert_rc "5-col check healthy (script column not corrupted)" 0
    assert_stdout_not_contains "no missing-script alert" "missing script"
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

# A loadable 4-col registry whose derived plist path exists on disk.
# Derived path for a gui/ daemon is $HOME/Library/LaunchAgents/<label>.plist;
# override HOME via a --plist flag in tests instead of writing to real HOME
seed_loadable() {
    seed_registry                       # daemon "one", label usr.test.one, gui/$UID/
    : > "$TEST_DIR/loaded"              # start unloaded
    printf '<plist/>\n' > "$TEST_DIR/usr.test.one.plist"
}

test_load_bootstraps_with_flag_plist() {
    seed_loadable
    run_script load one --plist "$TEST_DIR/usr.test.one.plist"
    assert_rc "load exits 0" 0
    assert_contains "now loaded" "$(cat "$TEST_DIR/loaded")" "usr.test.one"
}

test_load_missing_name_is_usage_error() {
    seed_loadable
    run_script load
    assert_rc "load with no name exits 2" 2
}

test_load_unknown_name_is_usage_error() {
    seed_loadable
    run_script load nonesuch --plist "$TEST_DIR/usr.test.one.plist"
    assert_rc "unknown daemon exits 2" 2
    assert_stderr_contains "names the daemon" "nonesuch"
}

# Registry FILE absent is a RUNTIME error (rc 1), matching status/check and the
# tool's own EXIT STATUS. A present-file/no-matching-row case stays usage (rc 2,
# above): only the file-absent path is runtime
test_load_absent_registry_is_runtime_error() {
    # no seed_registry: DAEMONS_REGISTRY points at a nonexistent file
    run_script load one
    assert_rc "load with absent registry exits 1" 1
    assert_stderr_contains "names the missing registry" "daemons.tsv"
}

test_load_missing_plist_is_runtime_error() {
    seed_loadable
    rm -f "$TEST_DIR/usr.test.one.plist"
    run_script load one --plist "$TEST_DIR/usr.test.one.plist"
    assert_rc "missing plist exits 1" 1
    assert_stderr_contains "names the resolved path" "one.plist"
}

test_load_uses_tsv_plist_column() {
    seed_registry_5col                  # plist column = $TEST_DIR/usr.test.one.plist
    : > "$TEST_DIR/loaded"
    printf '<plist/>\n' > "$TEST_DIR/usr.test.one.plist"
    run_script load one
    assert_rc "load via tsv plist exits 0" 0
    assert_contains "loaded via tsv column" "$(cat "$TEST_DIR/loaded")" "usr.test.one"
}

test_load_reload_is_idempotent() {
    seed_loadable
    printf 'usr.test.one\n' > "$TEST_DIR/loaded"   # already loaded
    run_script load one --plist "$TEST_DIR/usr.test.one.plist"
    assert_rc "reload exits 0" 0
    # still loaded exactly once (bootout-then-bootstrap left one entry)
    assert_eq "one entry after reload" "1" \
        "$(grep -cx 'usr.test.one' "$TEST_DIR/loaded")"
}

test_load_appends_lifecycle_record() {
    seed_loadable
    run_script load one --plist "$TEST_DIR/usr.test.one.plist"
    assert_rc "load exits 0" 0
    assert_file_exists "log written" "$TEST_DIR/log/one.log"
    assert_eq "record event is load" "load" \
        "$(jq -rs 'last | .event' "$TEST_DIR/log/one.log")"
}

# A lifecycle-record APPEND failure must NOT change load's exit status: the
# launchctl action succeeded and the record is best-effort. Force the append to
# fail hermetically by pointing DAEMONS_LOG_DIR at a subpath UNDER a regular
# file, so both the `mkdir -p "$LOG_DIR"` and the `>>` redirect fail. run_script
# hardcodes DAEMONS_LOG_DIR, so this case invokes the script directly (same
# shape as run_script) with the blocking log dir
test_load_append_failure_still_succeeds() {
    seed_loadable
    printf 'x\n' > "$TEST_DIR/blocker"             # a regular file, not a dir
    local blocked_log="$TEST_DIR/blocker/sub"      # a subpath under a file: mkdir -p and >> both fail
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" VISUAL="" \
        DAEMONS_LOG_DIR="$blocked_log" \
        DAEMONS_REGISTRY="$TEST_DIR/daemons.tsv" \
        /bin/bash "$UNDER_TEST" load one --plist "$TEST_DIR/usr.test.one.plist" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "load rc 0 even when the lifecycle append fails" 0
    # the daemon still got loaded (launchctl bootstrap shim ran)
    assert_contains "loaded despite append failure" "$(cat "$TEST_DIR/loaded")" "usr.test.one"
    # confirm the append genuinely FAILED: no log file exists under the blocked dir
    if [ -f "$blocked_log/one.log" ]; then
        _fail "expected the lifecycle append to fail, but a log file was created"
    else
        _ok "lifecycle append failed as intended (no log file created)"
    fi
}

test_load_dry_run_no_side_effects() {
    seed_loadable
    run_script load one --plist "$TEST_DIR/usr.test.one.plist" --dry-run
    assert_rc "dry-run exits 0" 0
    assert_stdout_contains "prints resolved plist" "one.plist"
    assert_stdout_contains "prints bootstrap command" "bootstrap"
    assert_eq "not actually loaded" "" "$(cat "$TEST_DIR/loaded")"
    if [ -f "$TEST_DIR/log/one.log" ]; then
        _fail "dry-run must not append a record"
    else
        _ok "dry-run appended nothing"
    fi
}

# A system/ registry whose non-root load must route launchctl AND the record
# append through sudo. The test runs as the (non-root) test user, so the
# system* + non-root branch in _do_load fires
seed_system_daemon() {
    mkdir -p "$(dirname "$TEST_DIR/daemons.tsv")"
    cat > "$TEST_DIR/daemons.tsv" <<TSV
name	domain	label	script	plist
sys	system/	usr.test.sys	$TEST_DIR/sys.sh	$TEST_DIR/usr.test.sys.plist
TSV
    printf '#!/bin/bash\n' > "$TEST_DIR/sys.sh"; chmod +x "$TEST_DIR/sys.sh"
    printf '<plist/>\n' > "$TEST_DIR/usr.test.sys.plist"
    : > "$TEST_DIR/loaded"
}

test_load_system_target_uses_sudo_and_logs() {
    # Skip if the harness runs as root: the sudo branch is guarded by non-root,
    # and CI/dev normally runs as a user. If root, the branch legitimately won't fire
    if [ "$(id -u)" -eq 0 ]; then _ok "skipped: running as root"; return; fi
    seed_system_daemon
    run_script load sys
    assert_rc "system load exits 0" 0
    assert_file_exists "sudo was invoked for launchctl/append" "$TEST_DIR/sudo_called"
    # The record must land in the test log dir (composed pre-elevation), not
    # under some root XDG default -- proves DAEMONS_LOG_DIR survived the sudo path
    assert_file_exists "record in the test log dir" "$TEST_DIR/log/sys.log"
    assert_eq "record event is load" "load" \
        "$(jq -rs 'last | .event' "$TEST_DIR/log/sys.log")"
}

# Symmetric to the load test above: a system/ daemon booted out while not root
# must route launchctl AND the record append through sudo. Seed it LOADED so
# unload actually boots it out and reaches the sudo path
test_unload_system_target_uses_sudo() {
    # Skip if root: the sudo branch is guarded by non-root, and CI/dev runs as a user
    if [ "$(id -u)" -eq 0 ]; then _ok "skipped: running as root"; return; fi
    seed_system_daemon
    printf 'usr.test.sys\n' > "$TEST_DIR/loaded"   # loaded, so unload boots it out
    run_script unload sys
    assert_rc "system unload exits 0" 0
    assert_file_exists "sudo was invoked for launchctl/append" "$TEST_DIR/sudo_called"
    assert_file_exists "record in the test log dir" "$TEST_DIR/log/sys.log"
    assert_eq "record event is unload" "unload" \
        "$(jq -rs 'last | .event' "$TEST_DIR/log/sys.log")"
}

test_unload_boots_out_loaded_daemon() {
    seed_registry
    printf 'usr.test.one\n' > "$TEST_DIR/loaded"   # loaded
    run_script unload one
    assert_rc "unload exits 0" 0
    assert_eq "no longer loaded" "" "$(cat "$TEST_DIR/loaded")"
}

test_unload_appends_record() {
    seed_registry
    printf 'usr.test.one\n' > "$TEST_DIR/loaded"
    run_script unload one
    assert_eq "record event is unload" "unload" \
        "$(jq -rs 'last | .event' "$TEST_DIR/log/one.log")"
}

test_unload_already_unloaded_is_noop() {
    seed_registry
    : > "$TEST_DIR/loaded"                          # not loaded
    run_script unload one
    assert_rc "already-unloaded exits 0" 0
    assert_stdout_contains "reports already unloaded" "already unloaded"
    # no record appended when nothing changed
    if [ -f "$TEST_DIR/log/one.log" ]; then
        _fail "no-op unload must not append a record"
    else
        _ok "no-op unload appended nothing"
    fi
}

test_unload_unknown_name_usage_error() {
    seed_registry
    run_script unload nonesuch
    assert_rc "unknown daemon exits 2" 2
    assert_stderr_contains "names the daemon" "nonesuch"
}

# Registry FILE absent is runtime (rc 1), same as load above -- present-file/
# no-matching-row stays usage (rc 2, the test above)
test_unload_absent_registry_is_runtime_error() {
    # no seed_registry: DAEMONS_REGISTRY points at a nonexistent file
    run_script unload one
    assert_rc "unload with absent registry exits 1" 1
    assert_stderr_contains "names the missing registry" "daemons.tsv"
}

test_unload_dry_run_no_side_effects() {
    seed_registry
    printf 'usr.test.one\n' > "$TEST_DIR/loaded"
    run_script unload one --dry-run
    assert_rc "dry-run exits 0" 0
    assert_stdout_contains "prints bootout command" "bootout"
    assert_eq "still loaded after dry-run" "usr.test.one" "$(cat "$TEST_DIR/loaded")"
}

test_registry_prints_path() {
    seed_registry
    run_script registry
    assert_rc "registry exits 0" 0
    assert_stdout_contains "prints the resolved registry path" "daemons.tsv"
}

test_registry_prints_path_even_if_absent() {
    # no seed_registry: the file does not exist, but the path is still printed
    run_script registry
    assert_rc "registry exits 0 without file" 0
    assert_stdout_contains "prints where it would look" "daemons.tsv"
}

test_registry_edit_invokes_editor() {
    seed_registry
    EDITOR=fakeeditor run_script registry --edit
    assert_rc "registry --edit exits 0" 0
    assert_file_exists "editor was invoked" "$TEST_DIR/editor_args"
    assert_contains "editor got the registry path" "$(cat "$TEST_DIR/editor_args")" "daemons.tsv"
}

test_registry_edit_multiword_editor() {
    # A multi-word $EDITOR (e.g. "code --wait") must word-split so the editor
    # binary and its flag are separate argv words, with the registry path still
    # reaching it. Quoting the whole string into one command word gives rc 127
    seed_registry
    EDITOR="fakeeditor --wait" run_script registry --edit
    assert_rc "multi-word editor exits 0" 0
    assert_file_exists "editor was invoked" "$TEST_DIR/editor_args"
    assert_contains "leading flag reached the editor" "$(cat "$TEST_DIR/editor_args")" "--wait"
    assert_contains "registry path reached the editor" "$(cat "$TEST_DIR/editor_args")" "daemons.tsv"
}

test_registry_open_invokes_open() {
    seed_registry
    run_script registry --open
    assert_rc "registry --open exits 0" 0
    assert_file_exists "open was invoked" "$TEST_DIR/open_args"
    assert_contains "open got the registry path" "$(cat "$TEST_DIR/open_args")" "daemons.tsv"
}

test_registry_edit_and_open_conflict() {
    seed_registry
    run_script registry --edit --open
    assert_rc "edit+open is usage error" 2
}

test_registry_rejects_positional() {
    # registry takes no positional argument
    seed_registry
    run_script registry foo
    assert_rc "positional arg is usage error" 2
    assert_stderr_contains "names the bad argument" "foo"
}

test_registry_rejects_unknown_flag() {
    seed_registry
    run_script registry --bogus
    assert_rc "unknown flag is usage error" 2
    assert_stderr_contains "names the bad flag" "--bogus"
}

run_tests "$@"
