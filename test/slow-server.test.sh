#!/bin/bash
# slow-server.test.sh - Tests for the slow-server compatibility launcher
# shellcheck source-path=SCRIPTDIR disable=SC2329
# shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- assertions and download fixtures contain literal shell text

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../scripts/slow-server"

write_shims() {
    cp "$SCRIPT_DIR/../scripts/flaky-server" "$TEST_DIR/download"
    cat > "$SHIM_DIR/socat" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/socat.args"
if [ -f "$TEST_DIR/request" ]; then
    exec /bin/bash -c _flaky_response < "$TEST_DIR/request"
fi
SHIM
    cat > "$SHIM_DIR/sleep" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/sleep.args"
SHIM
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
cat "$TEST_DIR/download"
[ ! -f "$TEST_DIR/download-failure" ]
SHIM
    chmod +x "$SHIM_DIR/socat" "$SHIM_DIR/sleep" "$SHIM_DIR/curl"
}

standalone_script() {
    mkdir -p "$TEST_DIR/standalone"
    cp "$UNDER_TEST" "$TEST_DIR/standalone/slow-server"
}

run_standalone() {
    local UNDER_TEST="$TEST_DIR/standalone/slow-server"
    run_script "$@"
}

test_help_offline() {
    local flag
    for flag in -h --help -hh; do
        run_script "$flag"
        assert_rc "help succeeds" 0
        assert_stdout_contains "help keeps legacy name" "slow-server"
        assert_stdout_contains "explains replacement" "flaky-server"
        assert_stdout_contains "offline requirements" "offline server startup"
        assert_stdout_contains "curl-pipe example" "bash -s -- 9000"
        [ ! -f "$TEST_DIR/curl.args" ] || assert_eq "help never fetches" yes no
        [ ! -f "$TEST_DIR/socat.args" ] || assert_eq "help never starts server" yes no
    done
}

test_default_and_custom_port() {
    run_script
    assert_rc "default succeeds" 0
    assert_contains "default port passed" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:8080,"
    run_script 9000
    assert_rc "custom succeeds" 0
    assert_contains "custom port passed" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:9000,"
    assert_stderr_contains "startup diagnostic" "http://localhost:9000"
    assert_eq "stdout clean" "$(get_stdout)" ""
    run_script 0000000000009000
    assert_rc "leading zeroes do not count against port range" 0
    [ ! -f "$TEST_DIR/curl.args" ] || assert_eq "sibling avoids download" yes no
}

test_legacy_delay_paths() {
    local path
    for path in /2500 /legacy/nested/2500/; do
        printf 'GET %s HTTP/1.1\r\nHost: localhost\r\n\r\n' "$path" > "$TEST_DIR/request"
        run_script 9000
        assert_stdout_contains "legacy route still returns 200" "HTTP/1.1 200 OK"
        assert_stdout_contains "legacy body still echoes delay" $'\r\n\r\n2500'
        assert_contains "delay preserved" "$(cat "$TEST_DIR/sleep.args")" "2.500"
    done
    printf 'GET /notanumber HTTP/1.1\r\nHost: localhost\r\n\r\n' > "$TEST_DIR/request"
    run_script
    assert_stdout_contains "unknown path still 404" "HTTP/1.1 404 Not Found"
}

test_sibling_in_a_directory_with_spaces() {
    mkdir "$TEST_DIR/with spaces"
    cp "$UNDER_TEST" "$TEST_DIR/with spaces/slow-server"
    cp "$TEST_DIR/download" "$TEST_DIR/with spaces/flaky-server"
    local UNDER_TEST="$TEST_DIR/with spaces/slow-server"
    run_script -- 09000
    assert_rc "sibling path quoted" 0
    assert_contains "port delegated" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:9000,"
}

test_installed_tool_on_path() {
    standalone_script
    cp "$TEST_DIR/download" "$SHIM_DIR/flaky-server"
    chmod +x "$SHIM_DIR/flaky-server"
    run_standalone 9000
    assert_rc "PATH implementation works" 0
    assert_contains "PATH implementation port" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:9000,"
    [ ! -f "$TEST_DIR/curl.args" ] || assert_eq "PATH avoids download" yes no
}

test_standalone_download() {
    standalone_script
    run_standalone 9000
    assert_rc "standalone download succeeds" 0
    assert_contains "fetches canonical replacement" "$(cat "$TEST_DIR/curl.args")" "https://toolio.sh/flaky-server"
    assert_contains "download gets port" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:9000,"
}

test_download_failure_never_executes_partial_content() {
    standalone_script
    printf 'touch "$TEST_DIR/executed"\n' > "$TEST_DIR/download"
    : > "$TEST_DIR/download-failure"
    run_standalone
    assert_rc "download failure" 1
    assert_stderr_contains "download failure diagnosed" "Failed to download flaky-server"
    [ ! -f "$TEST_DIR/executed" ] || assert_eq "partial download not executed" yes no
    rm "$TEST_DIR/download-failure"
    : > "$TEST_DIR/download"
    run_standalone
    assert_rc "empty download fails" 1
}

test_missing_curl_and_socat() {
    standalone_script
    rm "$SHIM_DIR/curl"
    ln -s /usr/bin/basename "$SHIM_DIR/basename"
    ln -s /usr/bin/dirname "$SHIM_DIR/dirname"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$TEST_DIR/standalone/slow-server" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing fetch dependency" 3
    assert_stderr_contains "names missing curl" "curl is required"
    rm "$SHIM_DIR/socat"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing delegated dependency" 3
    assert_stderr_contains "names missing socat" "socat is required"
}

test_invalid_arguments_are_rejected() {
    standalone_script
    run_standalone 65536
    assert_rc "standalone validates before download" 2
    [ ! -f "$TEST_DIR/curl.args" ] || assert_eq "invalid invocation never downloads" yes no
    run_script abc
    assert_rc "invalid port" 2
    run_script 9000 extra
    assert_rc "extra args" 2
    run_script --unknown
    assert_rc "unknown flag" 2
    assert_stderr_contains "legacy name in hint" 'Run `slow-server -h` for usage'
    run_script -- -h
    assert_rc "option terminator" 2
    run_script 9000 -h
    assert_rc "help after positional" 0
}

test_streamed_launcher_fetches_replacement() {
    printf 'GET /2500 HTTP/1.1\r\nHost: localhost\r\n\r\n' > "$TEST_DIR/request"
    cat "$UNDER_TEST" | env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" /bin/bash -s -- 9000 > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "streamed launcher succeeds" 0
    assert_stdout_contains "streamed legacy response" $'\r\n\r\n2500'
    assert_contains "streamed fetch" "$(cat "$TEST_DIR/curl.args")" "https://toolio.sh/flaky-server"
    assert_contains "streamed port" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:9000,"
}

run_tests "$@"
