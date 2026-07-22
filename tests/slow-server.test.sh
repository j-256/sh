#!/bin/bash
# slow-server.test.sh - Tests for slow-server
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../slow-server"

# --- helpers ---

get_socat_args() { cat "$TEST_DIR/socat.args" 2>/dev/null; }

# --- shims ---

write_shims() {
    # socat shim: log args, exit immediately (don't actually start server)
    cat > "$SHIM_DIR/socat" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/socat.args"
exit 0
SHIM
    chmod +x "$SHIM_DIR/socat"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has EXAMPLES" "EXAMPLES"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_short_help() {
    run_script -h
    assert_rc "short help exits 0" 0
    assert_stdout_contains "short help has NAME" "NAME"
}

test_default_port() {
    run_script
    assert_rc "default exits 0" 0
    assert_stdout_contains "starts on default port" "http://localhost:8080"
    assert_contains "socat listens on 8080" "$(get_socat_args)" "TCP-LISTEN:8080,fork,reuseaddr"
    assert_contains "socat uses SYSTEM" "$(get_socat_args)" "SYSTEM:_slow_response"
}

test_custom_port() {
    run_script 3000
    assert_rc "custom port exits 0" 0
    assert_stdout_contains "starts on custom port" "http://localhost:3000"
    assert_contains "socat listens on 3000" "$(get_socat_args)" "TCP-LISTEN:3000,fork,reuseaddr"
}

test_socat_missing() {
    # Remove socat shim that write_shims created
    rm -f "$SHIM_DIR/socat"
    # Use empty PATH (just shim dir) so socat is not found
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "socat missing exits 3" 3
    assert_stderr_contains "socat missing error" "socat is required"
}

test_socat_fork_and_reuseaddr() {
    run_script 8080
    assert_rc "fork and reuseaddr" 0
    local args; args="$(get_socat_args)"
    assert_contains "has fork" "$args" "fork"
    assert_contains "has reuseaddr" "$args" "reuseaddr"
}

test_exported_function() {
    run_script
    assert_rc "exports function" 0
    assert_contains "uses _slow_response" "$(get_socat_args)" "_slow_response"
}

test_non_numeric_port() {
    run_script abc
    assert_rc "non-numeric port exits 0" 0
    assert_stdout_contains "accepts non-numeric port" "http://localhost:abc"
    assert_contains "socat gets port" "$(get_socat_args)" "TCP-LISTEN:abc,fork,reuseaddr"
}

test_extra_args_ignored() {
    run_script 8080 extra args
    assert_rc "extra args exits 0" 0
    assert_stdout_contains "uses first arg" "http://localhost:8080"
    assert_contains "socat uses first port" "$(get_socat_args)" "TCP-LISTEN:8080,fork,reuseaddr"
}

test_socat_args_order() {
    run_script 9999
    assert_rc "args order" 0
    local args; args="$(get_socat_args)"
    local line1
    local line2
    line1="$(echo "$args" | head -n1)"
    line2="$(echo "$args" | tail -n1)"
    assert_eq "first arg is TCP-LISTEN" "$line1" "TCP-LISTEN:9999,fork,reuseaddr"
    assert_eq "second arg is SYSTEM" "$line2" "SYSTEM:_slow_response"
}

# --- run ---

run_tests "$@"
