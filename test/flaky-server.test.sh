#!/bin/bash
# flaky-server.test.sh - Tests for flaky-server
# shellcheck source-path=SCRIPTDIR disable=SC2329
# shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- assertions and request fixtures contain literal shell text

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../scripts/flaky-server"

write_shims() {
    cat > "$SHIM_DIR/socat" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/socat.args"
if [ -f "$TEST_DIR/listener-failure" ]; then exit 42; fi
if [ -f "$TEST_DIR/request" ]; then
    exec /bin/bash -c _flaky_response < "$TEST_DIR/request"
fi
SHIM
    cat > "$SHIM_DIR/sleep" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/sleep.args"
[ ! -f "$TEST_DIR/sleep-failure" ]
SHIM
    chmod +x "$SHIM_DIR/socat" "$SHIM_DIR/sleep"
}

request() {
    printf '%s %s HTTP/1.1\r\nHost: localhost\r\n\r\n' "${2:-GET}" "$1" > "$TEST_DIR/request"
    run_script
}

response_body() {
    local response; response="$(cat "$TEST_DIR/stdout"; printf .)"
    response="${response%.}"
    printf '%s' "${response#*$'\r\n\r\n'}"
}

assert_status() {
    assert_stdout_contains "$1" "HTTP/1.1 $2 "
}

test_help() {
    local flag
    for flag in -h --help -hh; do
        run_script "$flag"
        assert_rc "help succeeds" 0
        assert_stdout_contains "help names tool" "flaky-server"
        assert_stdout_contains "help documents drop" "/drop/<ms>"
        assert_stdout_contains "help documents rate" "/rate/<bps>"
        assert_stdout_contains "help documents stream defaults" "chunk=ceil(bytes/10)"
        assert_stdout_contains "help documents limits" "1 MiB"
        assert_stdout_contains "help documents stdin startup" "bash -s -- 9000"
        assert_eq "help has no diagnostics" "$(get_stderr)" ""
        [ ! -f "$TEST_DIR/socat.args" ] || assert_eq "help never starts listener" yes no
    done
}

test_help_color() {
    NO_COLOR=1 CLICOLOR_FORCE=1 run_script -h
    assert_stdout_not_contains "NO_COLOR wins" $'\033['
    NO_COLOR="" CLICOLOR_FORCE=1 run_script -h
    assert_stdout_contains "forced underline" $'\033[4m'
    NO_COLOR="" CLICOLOR_FORCE="" run_script -h
    assert_stdout_not_contains "redirected help is plain" $'\033['
}

test_ports_and_end_of_options() {
    run_script
    assert_rc "default listener exits cleanly" 0
    assert_contains "default IPv4 listener" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:8080,fork,reuseaddr"
    assert_contains "explicit Bash handler" "$(cat "$TEST_DIR/socat.args")" "EXEC:/bin/bash -c _flaky_response,nofork"
    assert_eq "no startup noise on stdout" "$(get_stdout)" ""
    assert_stderr_contains "startup on stderr" "http://localhost:8080"
    run_script -- 09000
    assert_rc "decimal port after --" 0
    assert_contains "leading zero is decimal" "$(cat "$TEST_DIR/socat.args")" "TCP4-LISTEN:9000,"
    run_script 0000000000009000
    assert_rc "leading zeroes do not count against numeric range" 0
    run_script 65535
    assert_rc "largest port" 0
    run_script 9000 -h
    assert_rc "help can follow positional" 0
    assert_stdout_contains "interleaved help" "SYNOPSIS"
}

test_invalid_arguments() {
    local value
    for value in "" 0 -1 65536 999999999999999999999 1.5 abc '80,fork' --port=9000 --unknown; do
        run_script "$value"
        assert_rc "invalid port or option rejected" 2
        assert_stderr_contains "usage hint" 'Run `flaky-server -h` for usage'
        assert_eq "usage errors keep stdout empty" "$(get_stdout)" ""
    done
    run_script 9000 extra
    assert_rc "extra argument rejected" 2
    run_script -- -h
    assert_rc "end of options treats -h as port" 2
    run_script drop 2000
    assert_rc "behaviors are request paths" 2
}

test_missing_dependencies() {
    ln -s /usr/bin/basename "$SHIM_DIR/basename"
    rm "$SHIM_DIR/socat"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing socat" 3
    assert_stderr_contains "names socat" "socat is required"
    write_shims
    rm "$SHIM_DIR/sleep"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing sleep" 3
    assert_stderr_contains "names sleep" "sleep is required"
}

test_listener_failure() {
    : > "$TEST_DIR/listener-failure"
    run_script 9000
    assert_rc "listener failure normalized" 1
    assert_stderr_contains "actionable port" "Failed to run listener on port 9000"
}

test_delay_precision_and_legacy_paths() {
    local value
    local expected
    for value in 0 1 10 100 2500 005 000000000000005 2147483647; do
        : > "$TEST_DIR/sleep.args"
        request "/delay/$value"
        assert_status "delay returns 200" 200
        assert_eq "echoes requested value" "$(response_body)" "$value"
        printf -v expected '%d.%03d' "$((10#$value / 1000))" "$((10#$value % 1000))"
        assert_eq "milliseconds are zero-padded" "$(cat "$TEST_DIR/sleep.args")" "$expected"
        assert_stdout_contains "framed response" "Content-Length: $((${#value} + 1))"
    done
    request /2500
    assert_status "bare number remains delay" 200
    assert_eq "legacy body" "$(response_body)" 2500
    request '/legacy/nested/005/?token=private'
    assert_status "numeric last segment remains delay" 200
    assert_eq "legacy leading zero body" "$(response_body)" 005
    assert_stderr_not_contains "query not logged" "private"
}

test_drop_is_a_short_xml_response() {
    request /drop/2005
    assert_rc "intentional failure does not fail listener" 0
    assert_status "drop starts HTTP 200" 200
    assert_stdout_contains "XML content type" "Content-Type: text/xml; charset=utf-8"
    assert_stdout_contains "promises a large body" "Content-Length: 100000"
    assert_eq "actual partial XML" "$(response_body)" '<?xml version="1.0"?><soapenv:Envelope><partial'
    assert_eq "delay before partial" "$(cat "$TEST_DIR/sleep.args")" 2.005
    assert_stderr_contains "reports sent bytes" "sent_bytes=47 advertised_bytes=100000"
    assert_stdout_contains "response correlation" "X-Request-ID:"
    assert_stderr_contains "log correlation" "id="
    assert_stderr_contains "log timing" "elapsed_s="
}

test_reset_needs_only_request_line() {
    printf 'GET /reset HTTP/1.1\r\n' > "$TEST_DIR/request"
    run_script
    assert_rc "reset handler succeeds" 0
    assert_eq "no response bytes" "$(get_stdout)" ""
    assert_stderr_contains "immediate close logged" "mode=reset response_bytes=0"
    [ ! -f "$TEST_DIR/sleep.args" ] || assert_eq "reset never sleeps" yes no
}

test_status_codes_and_no_body_statuses() {
    local code
    for code in 200 201 301 400 404 418 429 500 501 503 599; do
        request "/status/$code"
        assert_status "requested final status" "$code"
        assert_eq "status body" "$(response_body)" "$code"
        [ ! -f "$TEST_DIR/sleep.args" ] || assert_eq "status never sleeps" yes no
    done
    for code in 204 205 304; do
        request "/status/$code"
        assert_status "requested bodyless status" "$code"
        assert_eq "body forbidden" "$(response_body | wc -c | tr -d ' ')" 0
    done
    request /status/204
    assert_stdout_not_contains "204 has no length" "Content-Length:"
}

test_bad_routes_never_fall_back_to_delay() {
    local path
    for path in /delay /delay/no /delay/-1 /delay/1.5 /delay/2147483648 /delay/999999999999999999999 /drop/1/2 /status/100 /status/600 /status/abc /reset/50 /trickle/no /rate /rate/0 /rate/-1 /rate/1.5 /rate/1048577 /rate/1/2; do
        request "$path"
        assert_status "invalid route is 400" 400
        [ ! -f "$TEST_DIR/sleep.args" ] || assert_eq "invalid routes never sleep" yes no
    done
    request /
    assert_status "root is unknown" 404
    request /notanumber
    assert_status "unknown route is 404" 404
    request '/delay/$(touch%20unexpected)'
    assert_status "shell-like input is inert" 400
}

test_trickle_has_a_complete_body_and_exact_schedule() {
    request /trickle/1007
    assert_status "trickle starts 200" 200
    assert_stdout_contains "trickle length" "Content-Length: 10"
    assert_eq "trickle body complete" "$(response_body)" ".........."
    assert_eq "ten writes" "$(wc -l < "$TEST_DIR/sleep.args" | tr -d ' ')" 10
    assert_eq "intervals total requested duration" "$(awk '{s += $1} END {printf "%.3f", s}' "$TEST_DIR/sleep.args")" 1.007
}

test_rate_defaults_and_partial_final_chunk() {
    request /rate/1024
    assert_status "rate starts 200" 200
    assert_stdout_contains "default rate body length" "Content-Length: 10240"
    assert_eq "default rate actual size" "$(response_body | wc -c | tr -d ' ')" 10240
    assert_eq "default rate write count" "$(wc -l < "$TEST_DIR/sleep.args" | tr -d ' ')" 10
    assert_eq "default rate schedule" "$(sort -u "$TEST_DIR/sleep.args")" 1.000
    assert_stderr_contains "rate settings diagnosed" "bytes=10240 chunk_bytes=1024 type=text duration_ms=10000 rate_bytes_s=1024"
    : > "$TEST_DIR/sleep.args"
    request '/rate/001000?bytes=25&chunk=10'
    assert_status "rate values are decimal" 200
    assert_eq "short final write still completes body" "$(response_body | wc -c | tr -d ' ')" 25
    assert_eq "short final write has proportional interval" "$(cat "$TEST_DIR/sleep.args")" $'0.010\n0.010\n0.005'
}

test_stream_content_shapes_and_size_defaults() {
    request '/trickle/100?type=xml&bytes=15&chunk=15'
    assert_eq "complete XML payload" "$(response_body)" '<data>..</data>'
    assert_stdout_contains "XML MIME type" "Content-Type: application/xml; charset=utf-8"
    request '/trickle/100?type=json&bytes=13&chunk=13'
    assert_eq "complete JSON payload" "$(response_body)" '{"data":".."}'
    assert_stdout_contains "JSON MIME type" "Content-Type: application/json"
    request '/trickle/0?type=xml&bytes=13'
    assert_eq "minimum XML payload" "$(response_body)" '<data></data>'
    request '/trickle/0?type=json&bytes=11'
    assert_eq "minimum JSON payload" "$(response_body)" '{"data":""}'
    local type
    for type in xml json; do
        request "/trickle/0?type=$type"
        assert_status "format alone works" 200
        assert_eq "structured default size" "$(response_body | wc -c | tr -d ' ')" 1024
        request "/rate/1024?type=$type"
        assert_eq "rate default size independent of format" "$(response_body | wc -c | tr -d ' ')" 10240
    done
}

test_stream_chunk_shape_and_zero_duration() {
    request '/trickle/1000?bytes=10&chunk=4'
    assert_eq "chunk shape changes pauses" "$(cat "$TEST_DIR/sleep.args")" $'0.400\n0.400\n0.200'
    assert_eq "chunk shape keeps exact body" "$(response_body)" ".........."
    : > "$TEST_DIR/sleep.args"
    request '/trickle/1000?bytes=10&chunk=100'
    assert_eq "oversized chunk makes one write" "$(cat "$TEST_DIR/sleep.args")" 1.000
    : > "$TEST_DIR/sleep.args"
    request '/trickle/0?bytes=10&chunk=1'
    assert_eq "zero duration does not sleep" "$(cat "$TEST_DIR/sleep.args")" ""
    assert_eq "zero duration still completes" "$(response_body)" ".........."
    request '/trickle/0?bytes=1048576&chunk=1048576'
    assert_status "largest body allowed" 200
    assert_eq "largest body has exact size" "$(response_body | wc -c | tr -d ' ')" 1048576
    request '/rate/1048576?bytes=1'
    assert_status "maximum rate and minimum body allowed" 200
    assert_eq "fractional millisecond rounds up" "$(cat "$TEST_DIR/sleep.args")" 0.001
}

test_invalid_stream_controls_are_rejected_without_delay() {
    local query
    for query in bytes bytes= bytes=0 bytes=-1 bytes=1.5 bytes=1048577 bytes=999999999999999999999 chunk=0 chunk=1048577 chunk=abc type type= type=soap 'bytes=10&bytes=11' 'chunk=1&chunk=2' 'type=text&type=xml' 'type=xml&bytes=12' 'type=json&bytes=10' 'bytes=1025&chunk=1' 'type=$(touch%20unexpected)'; do
        request "/trickle/1000?$query"
        assert_status "invalid stream setting is 400" 400
        assert_eq "invalid stream has plain error body" "$(response_body)" 400
        assert_stderr_contains "stream validation diagnosed" "event=invalid_stream"
        [ ! -f "$TEST_DIR/sleep.args" ] || assert_eq "invalid stream never sleeps" yes no
    done
    assert_stderr_not_contains "raw invalid setting is not logged" "unexpected"
    request '/rate/100?bytes=10&bytes=10'
    assert_status "rate validates controls too" 400
    request '/trickle/0?bytes=0015&type=xml&trace=private'
    assert_status "decimal setting and unrelated query accepted" 200
    assert_eq "decimal setting controls size" "$(response_body)" '<data>..</data>'
    assert_stderr_not_contains "query value not logged" "private"
    request '/delay/0?bytes=bad&type=soap'
    assert_status "other behaviors ignore query controls" 200
}

test_head_never_sends_a_body() {
    local path
    for path in /delay/0 /drop/0 '/trickle/100?type=json' '/rate/100?bytes=15&type=xml' /status/503; do
        request "$path" HEAD
        assert_eq "HEAD has no body" "$(response_body | wc -c | tr -d ' ')" 0
        assert_stderr_contains "HEAD reports no sent bytes" "sent_bytes=0"
    done
    : > "$TEST_DIR/sleep.args"
    request '/rate/100?bytes=15&type=xml' HEAD
    assert_stdout_contains "HEAD keeps configured length" "Content-Length: 15"
    assert_stdout_contains "HEAD keeps configured format" "Content-Type: application/xml"
    assert_eq "HEAD skips stream duration" "$(cat "$TEST_DIR/sleep.args")" ""
}

test_soap_post_and_expect_continue() {
    printf 'POST /drop/5 HTTP/1.1\r\nHost: localhost\r\ncOnTeNt-LeNgTh: 11\r\nExpect: 100-continue\r\nAuthorization: secret\r\n\r\n<Envelope/>' > "$TEST_DIR/request"
    run_script
    assert_stdout_contains "continues before reading upload" $'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK'
    assert_stdout_contains "POST gets partial XML" "<partial"
    assert_stderr_contains "POST logged" "method=POST mode=drop"
    assert_stderr_not_contains "authorization not logged" "secret"
}

test_upload_bytes_and_error_status() {
    printf 'POST /status/501 HTTP/1.1\r\nContent-Length: 8\r\n\r\nab\ncd\000ef' > "$TEST_DIR/request"
    run_script
    assert_status "requested 501 still reads binary body" 501
    assert_stderr_not_contains "framed body consumed" "read_failed"
    printf 'POST /status/200 HTTP/1.1\r\nContent-Length: 12\r\n\r\nshort' > "$TEST_DIR/request"
    run_script
    assert_eq "truncated upload closes" "$(get_stdout)" ""
    assert_stderr_contains "truncated upload diagnosed" "phase=body remaining_bytes=12"
}

test_unsupported_upload_and_bad_framing() {
    printf 'POST /delay/50 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n' > "$TEST_DIR/request"
    run_script
    assert_status "chunked request explicitly rejected" 501
    printf 'POST /delay/50 HTTP/1.1\r\nExpect: magic\r\n\r\n' > "$TEST_DIR/request"
    run_script
    assert_status "unsupported expectation rejected" 417
    printf 'POST /rate/100?type=json HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n' > "$TEST_DIR/request"
    run_script
    assert_status "unsupported upload overrides streaming" 501
    assert_eq "upload error replaces generated body" "$(response_body)" 501
    assert_stdout_contains "upload error uses plain text" "Content-Type: text/plain"
    [ ! -f "$TEST_DIR/sleep.args" ] || assert_eq "upload errors never stream" yes no
    local length
    for length in nope -1 1048577 999999999999999999999; do
        printf 'POST /drop/0 HTTP/1.1\r\nContent-Length: %s\r\n\r\n' "$length" > "$TEST_DIR/request"
        run_script
        assert_eq "invalid length closes" "$(get_stdout)" ""
        assert_stderr_contains "length diagnosed" "event=invalid_length"
    done
    printf 'POST /delay/0 HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n' > "$TEST_DIR/request"
    run_script
    assert_stderr_contains "duplicate length rejected" "event=invalid_length"
}

test_read_failures_and_limits() {
    : > "$TEST_DIR/request"
    run_script
    assert_stderr_contains "empty connection diagnosed" "phase=request_line"
    printf 'GET /0 HTTP/1.1\r\nHost: localhost\r\n' > "$TEST_DIR/request"
    run_script
    assert_stderr_contains "incomplete headers diagnosed" "phase=headers"
    printf 'GET /0 HTTP/1.1\r\n' > "$TEST_DIR/request"
    local i=0
    while [ "$i" -lt 100 ]; do printf 'X: a\r\n' >> "$TEST_DIR/request"; i=$((i + 1)); done
    cp "$TEST_DIR/request" "$TEST_DIR/full-headers"
    printf '\r\n' >> "$TEST_DIR/request"
    run_script
    assert_status "documented header count accepted" 200
    cp "$TEST_DIR/full-headers" "$TEST_DIR/request"
    printf 'X: a\r\n' >> "$TEST_DIR/request"
    printf '\r\n' >> "$TEST_DIR/request"
    run_script
    assert_stderr_contains "header limit diagnosed" "event=limit"
    printf 'garbage\r\n\r\n' > "$TEST_DIR/request"
    run_script
    assert_status "malformed request is 400" 400
    assert_stderr_contains "malformed method is not echoed" "method=INVALID"
}

test_sleep_failure_is_diagnosable() {
    : > "$TEST_DIR/sleep-failure"
    request /delay/50
    assert_eq "failure sends no success response" "$(get_stdout)" ""
    assert_stderr_contains "failed delay logged" "event=sleep_failed"
    assert_stderr_contains "failed delay value" "delay_ms=50"
    request '/rate/100?type=xml'
    assert_status "stream failure happens after headers" 200
    assert_eq "failed stream sends no body" "$(response_body)" ""
    assert_stderr_contains "failed stream identifies progress" "sent_bytes=0 elapsed_s="
}

test_streamed_execution_serves_requests() {
    printf 'GET /drop/0 HTTP/1.1\r\nHost: localhost\r\n\r\n' > "$TEST_DIR/request"
    cat "$UNDER_TEST" | env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" /bin/bash -s -- 9000 > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "stdin script serves request" 0
    assert_status "stdin script sends partial" 200
    assert_stderr_contains "stdin script names itself" "[INF][flaky-server]"
    assert_stdout_contains "stdin script short body" "<partial"
}

run_tests "$@"
