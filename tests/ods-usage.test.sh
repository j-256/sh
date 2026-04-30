#!/bin/bash
# ods-usage.test.sh - Tests for ods-usage
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../ods-usage"

# --- helpers ---

get_jq_stdin() { cat "$TEST_DIR/jq.stdin" 2>/dev/null; }
get_pbpaste_calls() { cat "$TEST_DIR/pbpaste.calls" 2>/dev/null | wc -l | tr -d ' '; }

# --- shims ---

write_shims() {
    # cat shim: pass through to real cat
    cat > "$SHIM_DIR/cat" <<'SHIM'
#!/bin/bash
exec /bin/cat "$@"
SHIM
    chmod +x "$SHIM_DIR/cat"

    # head shim: pass through to real head
    cat > "$SHIM_DIR/head" <<'SHIM'
#!/bin/bash
exec /usr/bin/head "$@"
SHIM
    chmod +x "$SHIM_DIR/head"

    # cut shim: pass through to real cut
    cat > "$SHIM_DIR/cut" <<'SHIM'
#!/bin/bash
exec /usr/bin/cut "$@"
SHIM
    chmod +x "$SHIM_DIR/cut"

    # jq shim: logs stdin, behaves like real jq for empty/query operations
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/jq.stdin"
stdin=""
if [ ! -t 0 ]; then
    stdin="$(cat)"
    printf '%s\n' "$stdin" >> "$log"
fi
if [ "$1" = "empty" ]; then
    printf '%s' "$stdin" | /opt/homebrew/bin/jq empty 2>&1
    exit $?
fi
if [ "$1" = "-r" ]; then
    shift
    printf '%s' "$stdin" | /opt/homebrew/bin/jq -r "$@" 2>&1
    exit $?
fi
printf '%s' "$stdin" | /opt/homebrew/bin/jq "$@" 2>&1
exit $?
SHIM
    chmod +x "$SHIM_DIR/jq"

    # pbpaste shim: returns clipboard contents from test env
    cat > "$SHIM_DIR/pbpaste" <<'SHIM'
#!/bin/bash
printf '1\n' >> "$TEST_DIR/pbpaste.calls"
if [ -f "$TEST_DIR/clipboard.txt" ]; then
    cat "$TEST_DIR/clipboard.txt"
    exit 0
fi
printf '%s\n' "invalid json content"
exit 0
SHIM
    chmod +x "$SHIM_DIR/pbpaste"

    # tput shim: returns underline codes unless disabled
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
case "$1" in
    smul) [ -f "$TEST_DIR/tput.disable" ] && exit 1; printf '\033[4m' ;;
    rmul) [ -f "$TEST_DIR/tput.disable" ] && exit 1; printf '\033[24m' ;;
    cols) printf '80' ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"
}

# --- test data ---

make_valid_json() {
    cat > "$TEST_DIR/valid.json" <<'JSON'
{"data":{"createdSandboxes":9,"activeSandboxes":8,"deletedSandboxes":0,"minutesDown":194006,"minutesUp":1389,"minutesUpByProfile":[{"profile":"medium","minutes":1389}]}}
JSON
}

make_valid_json_all_profiles() {
    cat > "$TEST_DIR/valid_all.json" <<'JSON'
{"data":{"createdSandboxes":5,"activeSandboxes":4,"deletedSandboxes":1,"minutesDown":100000,"minutesUp":600,"minutesUpByProfile":[{"profile":"medium","minutes":200},{"profile":"large","minutes":300},{"profile":"xlarge","minutes":100}]}}
JSON
}

make_invalid_json() {
    printf '%s\n' "not valid json at all" > "$TEST_DIR/invalid.json"
}

# --- test cases ---

test_valid_json_argument() {
    make_valid_json
    run_script "$(cat "$TEST_DIR/valid.json")"
    assert_rc "exits 0" 0
    assert_stdout_contains "has Sandbox Counts" "Sandbox Counts"
    assert_stdout_contains "shows created count" "created: 9"
    assert_stdout_contains "shows active count" "active:  8"
    assert_stdout_contains "shows deleted count" "deleted: 0"
    assert_stdout_contains "has Uptime section" "Uptime & Downtime"
    assert_stdout_contains "shows min up" "min up:   1389"
    assert_stdout_contains "shows medium profile" "> medium: 1389"
    assert_stdout_contains "shows min down" "min down: 194006"
    assert_stdout_contains "has Credits section" "Credits Used"
    assert_stdout_contains "shows up credits" "up:    1389"
    assert_stdout_contains "shows down credits" "down:  58201"
    assert_stdout_contains "shows total credits" "total: 59590"
    assert_eq "pbpaste not called" "$(get_pbpaste_calls)" "0"
}

test_valid_json_all_profiles() {
    make_valid_json_all_profiles
    run_script "$(cat "$TEST_DIR/valid_all.json")"
    assert_rc "exits 0" 0
    assert_stdout_contains "shows created count" "created: 5"
    assert_stdout_contains "shows deleted count" "deleted: 1"
    assert_stdout_contains "shows medium profile" "> medium: 200"
    assert_stdout_contains "shows large profile" ">  large: 300"
    assert_stdout_contains "shows xlarge profile" "> xlarge: 100"
    assert_stdout_contains "shows up credits" "up:    1200"
    assert_stdout_contains "shows down credits" "down:  30000"
    assert_stdout_contains "shows total credits" "total: 31200"
}

test_invalid_json_argument() {
    make_invalid_json
    run_script "$(cat "$TEST_DIR/invalid.json")"
    assert_rc "exits 1" 1
    assert_err_contains "error message" "ERROR: Input is not valid JSON"
    assert_err_contains "shows preview" "not valid json at all"
}

test_long_json_argument_truncated() {
    local long_input
    long_input="$(printf 'x%.0s' {1..200})"
    run_script "$long_input"
    assert_rc "exits 1" 1
    assert_err_contains "error shown" "ERROR: Input is not valid JSON"
    local preview
    preview="$(get_stderr | grep -v ERROR | head -n 1)"
    local preview_len=${#preview}
    assert_eq "preview truncated to terminal width" "$preview_len" "80"
}

test_clipboard_valid_json() {
    make_valid_json
    cp "$TEST_DIR/valid.json" "$TEST_DIR/clipboard.txt"
    run_script
    assert_rc "exits 0" 0
    assert_stdout_contains "shows sandbox counts" "created: 9"
    local calls
    calls="$(get_pbpaste_calls)"
    assert_eq "pbpaste called" "$calls" "10"
}

test_clipboard_invalid_json() {
    make_invalid_json
    cp "$TEST_DIR/invalid.json" "$TEST_DIR/clipboard.txt"
    run_script
    assert_rc "exits 1" 1
    assert_err_contains "clipboard error" "ERROR: No arguments provided and clipboard does not contain valid JSON"
}

test_clipboard_default_when_no_args() {
    run_script
    assert_rc "exits 1" 1
    assert_err_contains "clipboard error" "ERROR: No arguments provided and clipboard does not contain valid JSON"
    local calls
    calls="$(get_pbpaste_calls)"
    assert_eq "pbpaste called" "$calls" "1"
}

test_terminal_formatting_enabled() {
    make_valid_json
    run_script "$(cat "$TEST_DIR/valid.json")"
    assert_rc "exits 0" 0
    local out
    out="$(get_stdout)"
    assert_not_contains "no underline codes when piped" "$out" "$(printf '\033')"
}

test_formatting_omitted_when_no_tty() {
    make_valid_json
    run_script "$(cat "$TEST_DIR/valid.json")"
    assert_rc "exits 0" 0
    local out
    out="$(get_stdout)"
    assert_not_contains "no underline codes" "$out" "$(printf '\033')"
}

test_tput_unavailable() {
    rm "$SHIM_DIR/tput"
    make_valid_json
    run_script "$(cat "$TEST_DIR/valid.json")"
    assert_rc "exits 0" 0
    local out
    out="$(get_stdout)"
    assert_not_contains "no underline codes" "$out" "$(printf '\033')"
}

test_jq_missing() {
    rm "$SHIM_DIR/jq"
    make_valid_json
    PATH="$SHIM_DIR" run_script "$(cat "$TEST_DIR/valid.json")"
    assert_rc "exits non-zero" 127
}

test_pbpaste_missing_with_no_args() {
    rm "$SHIM_DIR/pbpaste"
    PATH="$SHIM_DIR" run_script
    assert_rc "exits non-zero" 127
}

test_credits_calculation_medium_only() {
    local json='{"data":{"createdSandboxes":1,"activeSandboxes":1,"deletedSandboxes":0,"minutesDown":0,"minutesUp":100,"minutesUpByProfile":[{"profile":"medium","minutes":100}]}}'
    run_script "$json"
    assert_rc "exits 0" 0
    assert_stdout_contains "up credits" "up:    100"
    assert_stdout_contains "down credits" "down:  0"
    assert_stdout_contains "total" "total: 100"
}

test_credits_calculation_large_only() {
    local json='{"data":{"createdSandboxes":1,"activeSandboxes":1,"deletedSandboxes":0,"minutesDown":0,"minutesUp":50,"minutesUpByProfile":[{"profile":"large","minutes":50}]}}'
    run_script "$json"
    assert_rc "exits 0" 0
    assert_stdout_contains "up credits 50*2" "up:    100"
}

test_credits_calculation_xlarge_only() {
    local json='{"data":{"createdSandboxes":1,"activeSandboxes":1,"deletedSandboxes":0,"minutesDown":0,"minutesUp":25,"minutesUpByProfile":[{"profile":"xlarge","minutes":25}]}}'
    run_script "$json"
    assert_rc "exits 0" 0
    assert_stdout_contains "up credits 25*4" "up:    100"
}

test_credits_calculation_downtime() {
    local json='{"data":{"createdSandboxes":1,"activeSandboxes":1,"deletedSandboxes":0,"minutesDown":1000,"minutesUp":0,"minutesUpByProfile":[]}}'
    run_script "$json"
    assert_rc "exits 0" 0
    assert_stdout_contains "down credits 1000*0.3" "down:  300"
}

test_missing_profile_data() {
    local json='{"data":{"createdSandboxes":1,"activeSandboxes":1,"deletedSandboxes":0,"minutesDown":0,"minutesUp":100,"minutesUpByProfile":[]}}'
    run_script "$json"
    assert_rc "exits 0" 0
    assert_stdout_contains "min up shown" "min up:   100"
    assert_stdout_not_contains "no medium line" "> medium:"
    assert_stdout_contains "up credits zero" "up:    0"
}

test_zero_values() {
    local json='{"data":{"createdSandboxes":0,"activeSandboxes":0,"deletedSandboxes":0,"minutesDown":0,"minutesUp":0,"minutesUpByProfile":[]}}'
    run_script "$json"
    assert_rc "exits 0" 0
    assert_stdout_contains "created zero" "created: 0"
    assert_stdout_contains "active zero" "active:  0"
    assert_stdout_contains "deleted zero" "deleted: 0"
    assert_stdout_contains "min up zero" "min up:   0"
    assert_stdout_contains "min down zero" "min down: 0"
    assert_stdout_contains "up credits zero" "up:    0"
    assert_stdout_contains "down credits zero" "down:  0"
    assert_stdout_contains "total zero" "total: 0"
}

test_sourced_mode() {
    make_valid_json
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash -c "source '$UNDER_TEST' '$(cat "$TEST_DIR/valid.json")'; echo RC=\$?" > "$TEST_DIR/stdout" 2>&1
    printf '0\n' > "$TEST_DIR/rc"
    assert_rc "exits 0" 0
    assert_stdout_contains "shows output" "Sandbox Counts"
    assert_stdout_contains "returns via return" "RC=0"
}

test_sourced_mode_error() {
    make_invalid_json
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash -c "source '$UNDER_TEST' '$(cat "$TEST_DIR/invalid.json")' 2>&1; echo RC=\$?" > "$TEST_DIR/stdout" 2>&1
    printf '0\n' > "$TEST_DIR/rc"
    assert_rc "shell exits 0" 0
    assert_stdout_contains "error shown" "ERROR: Input is not valid JSON"
    assert_stdout_contains "returns via return" "RC=1"
}

# --- run ---

run_tests "$@"
