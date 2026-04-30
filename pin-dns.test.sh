#!/bin/bash
# pin-dns.test.sh - Tests for pin-dns
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/pin-dns"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }
get_dig_log() { cat "$TEST_DIR/dig.log" 2>/dev/null; }

assert_curl_arg_first() {
    local label="$1"
    local want="$2"
    local got
    got="$(head -n1 "$TEST_DIR/curl.args" 2>/dev/null)"
    assert_eq "$label" "$got" "$want"
}

assert_curl_arg_count() {
    local label="$1"
    local want_line="$2"
    local want_count="$3"
    local got_count=0
    local line
    if [ -f "$TEST_DIR/curl.args" ]; then
        while IFS= read -r line; do
            [ "$line" = "$want_line" ] && got_count=$((got_count + 1))
        done < "$TEST_DIR/curl.args"
    fi
    assert_eq "$label" "$got_count" "$want_count"
}

# --- shims ---

write_shims() {
    # curl shim: log args one-per-line
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
printf '%s\n' "CURL_OK"
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # dig shim: log invocations, return deterministic IPs
    # Query containing "noresult" returns nothing
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/dig.log"
printf 'dig' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
q=""
for a in "$@"; do
    case "$a" in +short|@*) ;; *) q="$a" ;; esac
done
case "$q" in *noresult*) exit 0 ;; esac
printf '%s\n' "192.0.2.10"
printf '%s\n' "192.0.2.11"
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"

    # defaults shim: return fake Chrome version
    cat > "$SHIM_DIR/defaults" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/defaults.log"
printf 'defaults' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
case "$*" in *badplist*) exit 0 ;; esac
printf '%s\n' "122.1.2.3"
exit 0
SHIM
    chmod +x "$SHIM_DIR/defaults"

    # Fake Chrome app directory
    mkdir -p "$TEST_DIR/Google_Chrome.app/Contents"
    : > "$TEST_DIR/Google_Chrome.app/Contents/Info.plist"
    export PIN_DNS_CHROME_APP="$TEST_DIR/Google_Chrome.app"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_err_contains "help has NAME" "NAME"
    assert_err_contains "help has ARGUMENT HANDLING" "ARGUMENT HANDLING"
}

test_drop_in_url_hostname_target() {
    run_script "https://ecom-dev.somesite.com/test" --target "edge.somesite.com"
    assert_rc "basic" 0
    assert_curl_arg_first "inject curl -q first" "-q"
    assert_contains "adds -sS" "$(get_curl_args)" "-sS"
    assert_contains "adds --resolve" "$(get_curl_args)" "--resolve"
    assert_contains "resolve value" "$(get_curl_args)" "ecom-dev.somesite.com:443:192.0.2.11"
    assert_contains "keeps URL" "$(get_curl_args)" "https://ecom-dev.somesite.com/test"
    assert_contains "dig called" "$(get_dig_log)" "dig"
}

test_useless_s_warning() {
    run_script -s "https://example.com" --target "edge.somesite.com"
    assert_rc "useless-s" 0
    assert_err_contains "warn about -s" "pin-dns already adds curl -sS"
}

test_no_silent() {
    run_script --no-silent -s "https://example.com" --target "edge.somesite.com"
    assert_rc "no-silent" 0
    assert_err_not_contains "no -s warning" "already adds curl -sS"
    assert_not_contains "no injected -sS" "$(get_curl_args)" "-sS"
}

test_quiet() {
    run_script --quiet -s "https://example.com" --target "edge.somesite.com"
    assert_rc "quiet" 0
    assert_err_not_contains "quiet hides warn" "[WRN]"
    assert_err_not_contains "quiet hides info" "[INF]"
}

test_curl_operand_warning() {
    run_script "https://example.com" -H --target "edge.somesite.com"
    assert_rc "operand-warn" 0
    assert_err_contains "operand warning" "looks like a pin-dns option but is being used as the operand to curl option '-H'"
    assert_contains "still pins" "$(get_curl_args)" "--resolve"
}

test_default_curlrc_strips_user_q() {
    run_script "https://example.com" --target "edge.somesite.com" -- -q -I
    assert_rc "strip-curl-q" 0
    assert_curl_arg_first "inject -q first" "-q"
    assert_curl_arg_count "only one -q" "-q" "1"
}

test_curlrc_user_q_first() {
    run_script --curlrc "https://example.com" --target "edge.somesite.com" -- -I -q
    assert_rc "curlrc-user-q" 0
    assert_curl_arg_first "first arg is user -q" "-q"
}

test_target_ip_literal() {
    run_script "https://example.com" --target "203.0.113.42"
    assert_rc "ip-target" 0
    assert_contains "resolve uses IP" "$(get_curl_args)" "example.com:443:203.0.113.42"
    assert_not_contains "dig not called" "$(get_dig_log)" "dig"
}

test_missing_host() {
    run_script --target "edge.somesite.com"
    assert_rc "missing-host" 2
}

test_missing_target_value() {
    run_script "https://example.com" --target
    assert_rc "missing-target" 2
}

test_dig_missing() {
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/sh
echo "dig: not found" >&2
exit 127
SHIM
    chmod +x "$SHIM_DIR/dig"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "dig-missing" 3
    assert_err_contains "dig missing error" "dig failed"
}

test_dig_no_results() {
    run_script "https://example.com" --target "noresult.example"
    assert_rc "dig-nores" 4
    assert_err_contains "dig no results" "dig returned no results"
}

test_user_supplies_a_flag() {
    run_script "https://example.com" --target "edge.somesite.com" -A "MyUA"
    assert_rc "user-A" 0
    assert_contains "user -A present" "$(get_curl_args)" "MyUA"
    assert_curl_arg_count "only one -A" "-A" "1"
}

test_user_supplies_ua_header() {
    run_script "https://example.com" --target "edge.somesite.com" -H "User-Agent: MyUA2"
    assert_rc "user-UA-header" 0
    assert_curl_arg_count "no wrapper -A" "-A" "0"
}

test_ua_fallback_chrome_missing() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "ua-fallback" 0
    assert_err_contains "warn about fallback" "falling back to 'sfcc-test'"
    assert_contains "UA is sfcc-test" "$(get_curl_args)" "sfcc-test"
}

test_url_host_mismatch() {
    run_script --host "override.example" "https://example.com/x" --target "edge.somesite.com"
    assert_rc "host-mismatch" 0
    assert_err_contains "warn mismatch" "URL host 'example.com' does not match --host 'override.example'"
    assert_contains "resolve uses override" "$(get_curl_args)" "override.example:443:192.0.2.11"
}

test_path_url_strip_mismatch() {
    run_script "ecom-dev.somesite.com" "edge.somesite.com" "https://third.example/some/path?q=1"
    assert_rc "path-url" 0
    assert_err_contains "PATH_OR_URL host mismatch" "PATH_OR_URL host 'third.example'"
    assert_contains "constructed url" "$(get_curl_args)" "https://ecom-dev.somesite.com/some/path?q=1"
}

test_path_normalization() {
    run_script "ecom-dev.somesite.com" "edge.somesite.com" "my/path"
    assert_rc "path-slash" 0
    assert_contains "adds leading slash" "$(get_curl_args)" "https://ecom-dev.somesite.com/my/path"
}

test_positional_mode() {
    run_script "ecom-dev.somesite.com" "edge.somesite.com" "/some/path" -I
    assert_rc "positional" 0
    assert_contains "constructed url" "$(get_curl_args)" "https://ecom-dev.somesite.com/some/path"
    assert_contains "curl flag" "$(get_curl_args)" "-I"
}

test_url_scheme_port() {
    run_script "http://example.com:8080/x" --target "edge.somesite.com"
    assert_rc "scheme-port" 0
    assert_contains "resolve uses port" "$(get_curl_args)" "example.com:8080:192.0.2.11"
}

test_resolver() {
    run_script "https://example.com" --target "edge.somesite.com" --resolver "8.8.8.8"
    assert_rc "resolver" 0
    assert_contains "dig @resolver" "$(get_dig_log)" "dig @8.8.8.8 +short edge.somesite.com"
}

test_double_dash_boundary() {
    run_script "https://example.com" -- --target "edge.somesite.com"
    assert_rc "double-dash" 0
    assert_not_contains "no resolve" "$(get_curl_args)" "--resolve"
}

test_curl_missing() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/sh
echo "curl: not found" >&2
exit 127
SHIM
    chmod +x "$SHIM_DIR/curl"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "curl-missing" 3
    assert_err_contains "curl missing" "curl failed to execute"
}

test_url_target_inference() {
    run_script "https://example.com/path" "edge.somesite.com"
    assert_rc "url-target" 0
    assert_contains "resolve from inferred" "$(get_curl_args)" "example.com:443:192.0.2.11"
    assert_not_contains "target not passed to curl" "$(get_curl_args)" "edge.somesite.com"
}

test_url_target_after_opts() {
    run_script "https://example.com" -H "X-Debug: 1" "edge.somesite.com"
    assert_rc "url-target-end" 0
    assert_contains "resolve present" "$(get_curl_args)" "--resolve"
    assert_contains "header preserved" "$(get_curl_args)" "X-Debug: 1"
}

test_url_target_ip_literal() {
    run_script "https://example.com" "203.0.113.42"
    assert_rc "url-ip-target" 0
    assert_contains "resolve uses IP" "$(get_curl_args)" "example.com:443:203.0.113.42"
}

test_url_target_ambiguous() {
    run_script "https://example.com" "edge1.somesite.com" "edge2.somesite.com"
    assert_rc "url-ambig" 0
    assert_not_contains "no resolve" "$(get_curl_args)" "--resolve"
}

test_url_target_explicit_wins() {
    run_script "https://example.com" "extra.host.com" --target "edge.somesite.com"
    assert_rc "url-explicit" 0
    assert_contains "resolve uses explicit" "$(get_curl_args)" "example.com:443:192.0.2.11"
    assert_contains "bare host passed through" "$(get_curl_args)" "extra.host.com"
}

# --- run ---

run_tests "$@"
