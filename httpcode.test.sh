#!/bin/bash
# httpcode.test.sh - Tests for httpcode
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/httpcode"

# --- shims ---

write_shims() {
    # jq shim: log args, return fake status info. httpcode invokes jq as
    # `jq -r --arg code NNN --arg src URL '...program...'`, so we key the
    # case on the `--arg code NNN` pair.
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/jq.args"
code=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "code" ]; then code="$arg"; break; fi
    prev="$arg"
done
case "$code" in
    418)
        cat <<'EOF'
418 I'm a teapot

The server refuses the attempt to brew coffee with a teapot.

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/418
EOF
        ;;
    200)
        cat <<'EOF'
200 OK

The request succeeded. The result and meaning of "success" depends on the HTTP method:

GET: The resource has been fetched and transmitted in the message body.
HEAD: Representation headers are included in the response without any message body.
PUT or POST: The resource describing the result of the action is transmitted in the message body.
TRACE: The message body contains the request as received by the server.

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/200
EOF
        ;;
    404)
        cat <<'EOF'
404 Not Found

The server cannot find the requested resource. In the browser, this means the URL is not recognized. In an API, this can also mean that the endpoint is valid but the resource itself does not exist. Servers may also send this response instead of 403 Forbidden to hide the existence of a resource from an unauthorized client. This response code is probably the most well known due to its frequent occurrence on the web.

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404
EOF
        ;;
    *)
        # Unknown status code
        echo "null"
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/jq"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has EXAMPLE" "EXAMPLE"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_missing_jq() {
    # Use empty PATH to simulate missing jq
    env TEST_DIR="$TEST_DIR" PATH="" \
        /bin/bash "$UNDER_TEST" 200 >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing jq exits 1" 1
    assert_stdout_contains "missing jq error" "[ERR] Missing dependency: jq"
    assert_stdout_contains "missing jq suggest install" "Recommend installing via Homebrew"
}

test_valid_status_418() {
    run_script 418
    assert_rc "418 exits 0" 0
    assert_stdout_contains "418 has code" "418"
    assert_stdout_contains "418 has name" "I'm a teapot"
    assert_stdout_contains "418 has message" "refuses the attempt to brew coffee"
    assert_stdout_contains "418 has URL" "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/418"
}

test_valid_status_200() {
    run_script 200
    assert_rc "200 exits 0" 0
    assert_stdout_contains "200 has code" "200"
    assert_stdout_contains "200 has name" "OK"
    assert_stdout_contains "200 has message" "request succeeded"
}

test_valid_status_404() {
    run_script 404
    assert_rc "404 exits 0" 0
    assert_stdout_contains "404 has code" "404"
    assert_stdout_contains "404 has name" "Not Found"
    assert_stdout_contains "404 has message" "cannot find the requested resource"
}

test_invalid_status_code() {
    run_script 999
    assert_rc "999 exits 2" 2
    # Unknown codes now fail loudly with an error to stderr
    assert_err_contains "999 error message" "unknown or unsupported HTTP status code"
}

test_no_arguments() {
    run_script
    assert_rc "no args exits 2" 2
    # No args now fails with a clear required-arg error
    assert_err_contains "no args error message" "status code is required"
}

test_source_mode_help() {
    # Test that script can be sourced and invoked with --help
    bash -c "source '$UNDER_TEST' --help" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "source help exits 0" 0
    assert_stdout_contains "source help has NAME" "NAME"
}

test_jq_receives_status_code() {
    run_script 418
    assert_rc "jq invoked" 0
    local args
    args="$(cat "$TEST_DIR/jq.args")"
    assert_contains "jq gets -r flag" "$args" "-r"
    assert_contains "jq gets --arg code" "$args" "--arg"
    assert_contains "jq gets status code" "$args" "418"
}

test_vendor_code_uses_vendor_url() {
    # Real jq must be available for this test; the shim can't exercise the
    # per-code source selection logic. Skip if the system doesn't have jq.
    command -v jq >/dev/null 2>&1 || { echo "# skip: system jq not present"; return 0; }
    # Clear the shim from PATH for this run so the real script/jq executes.
    env PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
        /bin/bash "$UNDER_TEST" 522 >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "522 exits 0" 0
    assert_stdout_contains "522 has Cloudflare URL" "developers.cloudflare.com"
    assert_stdout_not_contains "522 does not use MDN URL" "developer.mozilla.org"
}

# --- run ---

run_tests "$@"
