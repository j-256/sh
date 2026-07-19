#!/bin/bash
# pin-dns.test.sh - Tests for pin-dns
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../pin-dns"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }
get_dig_log() { cat "$TEST_DIR/dig.log" 2>/dev/null; }
get_impersonate_args() { cat "$TEST_DIR/curl-impersonate.args" 2>/dev/null; }

# Install a recording curl-impersonate stub on this test's PATH. Only some tests
# want it present (auto-detect must NOT see it in most tests), so it is opt-in
# per-test rather than part of write_shims
_install_impersonate_stub() {
    cat > "$SHIM_DIR/curl-impersonate" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl-impersonate.args"
printf '%s\n' "IMPERSONATE_OK"
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl-impersonate"
}

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

# Assert needleB appears on a line after needleA in curl.args (wire order),
# matching each needle as a substring of a line rather than the whole line
# (the UA and Accept values are long, so callers pass a recognizable prefix)
assert_curl_arg_order() {
    local label="$1"
    local first="$2"
    local second="$3"
    local li=0
    local si=0
    local n=0
    local line
    while IFS= read -r line; do
        n=$((n + 1))
        case "$line" in *"$first"*) [ "$li" -eq 0 ] && li="$n" ;; esac
        case "$line" in *"$second"*) [ "$si" -eq 0 ] && si="$n" ;; esac
    done < "$TEST_DIR/curl.args"
    if [ "$li" -gt 0 ] && [ "$si" -gt "$li" ]; then
        _ok "$label"
    else
        _fail "$label: '$first'(@$li) should precede '$second'(@$si)"
    fi
}

# --- shims ---

write_shims() {
    # Reset UA-resolver overrides between tests: the runner calls each test in
    # the same shell, so an `export` in one test would otherwise leak forward
    unset PIN_DNS_CHROME_MAJOR PIN_DNS_UA_OFFLINE PIN_DNS_VERSION_API_URL PIN_DNS_UA_CACHE_TTL
    export XDG_CACHE_HOME="$TEST_DIR/cache"

    # curl shim: log args one-per-line
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
# Version-fetch calls: any arg is a file:// URL under apiroot -> emit fixture
for a in "$@"; do
    case "$a" in
        file://*/channels/stable/versions*|https://versionhistory*)
            cat "$TEST_DIR/api.json" 2>/dev/null
            exit 0
            ;;
    esac
done
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

    # jq shim: extract .versions[0].version from stdin JSON fixtures
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
in="$(cat)"
case "$*" in
    *versions*) printf '%s\n' "$in" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -1 ;;
    *) printf '%s\n' "$in" ;;
esac
SHIM
    chmod +x "$SHIM_DIR/jq"

    # Fake Chrome app directory
    mkdir -p "$TEST_DIR/Google_Chrome.app/Contents"
    : > "$TEST_DIR/Google_Chrome.app/Contents/Info.plist"
    export PIN_DNS_CHROME_APP="$TEST_DIR/Google_Chrome.app"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stderr_contains "help has NAME" "NAME"
    assert_stderr_contains "help has ARGUMENT HANDLING" "ARGUMENT HANDLING"
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
    assert_stderr_contains "warn about -s" "pin-dns already adds curl -sS"
}

test_no_silent() {
    run_script --no-silent -s "https://example.com" --target "edge.somesite.com"
    assert_rc "no-silent" 0
    assert_stderr_not_contains "no -s warning" "already adds curl -sS"
    assert_not_contains "no injected -sS" "$(get_curl_args)" "-sS"
}

test_quiet() {
    run_script --quiet -s "https://example.com" --target "edge.somesite.com"
    assert_rc "quiet" 0
    assert_stderr_not_contains "quiet hides warn" "[WRN]"
    assert_stderr_not_contains "quiet hides info" "[INF]"
}

test_curl_operand_warning() {
    run_script "https://example.com" -H --target "edge.somesite.com"
    assert_rc "operand-warn" 0
    assert_stderr_contains "operand warning" "looks like a pin-dns option but is being used as the operand to curl option '-H'"
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
    assert_stderr_contains "dig missing error" "dig failed"
}

test_dig_no_results() {
    run_script "https://example.com" --target "noresult.example"
    assert_rc "dig-nores" 4
    assert_stderr_contains "dig no results" "dig returned no results"
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
    assert_not_contains "no sfcc-test fallback" "$(get_curl_args)" "sfcc-test"
    assert_contains "pinned UA" "$(get_curl_args)" "Chrome/148.0.0.0"
}

test_url_host_mismatch() {
    run_script --host "override.example" "https://example.com/x" --target "edge.somesite.com"
    assert_rc "host-mismatch" 0
    assert_stderr_contains "warn mismatch" "URL host 'example.com' does not match --host 'override.example'"
    assert_contains "resolve uses override" "$(get_curl_args)" "override.example:443:192.0.2.11"
}

test_path_url_strip_mismatch() {
    run_script "ecom-dev.somesite.com" "edge.somesite.com" "https://third.example/some/path?q=1"
    assert_rc "path-url" 0
    assert_stderr_contains "PATH_OR_URL host mismatch" "PATH_OR_URL host 'third.example'"
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
    assert_stderr_contains "curl missing" "curl failed to execute"
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

test_ua_major_from_local_read() {
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "local-read" 0
    # defaults shim returns 122.1.2.3 -> major 122
    assert_contains "UA uses local major" "$(get_curl_args)" "Chrome/122.0.0.0"
    assert_contains "UA is mac shape" "$(get_curl_args)" "Macintosh; Intel Mac OS X 10_15_7"
}

test_ua_pinned_fallback_no_chrome() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "pinned-fallback" 0
    # no local Chrome + curl shim returns non-JSON -> fetch yields empty -> pinned 148
    assert_contains "UA uses pinned major" "$(get_curl_args)" "Chrome/148.0.0.0"
    assert_stderr_not_contains "no sfcc-test" "sfcc-test"
}

test_ua_explicit_major_env() {
    export PIN_DNS_CHROME_MAJOR="200"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "env-major" 0
    assert_contains "UA uses env major" "$(get_curl_args)" "Chrome/200.0.0.0"
}

test_impersonation_navigate_default() {
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "navigate" 0
    assert_contains "sec-ch-ua-mobile" "$(get_curl_args)" "sec-ch-ua-mobile: ?0"
    assert_contains "sec-ch-ua-platform mac" "$(get_curl_args)" "sec-ch-ua-platform: \"macOS\""
    assert_contains "sec-fetch-mode navigate" "$(get_curl_args)" "Sec-Fetch-Mode: navigate"
    assert_contains "sec-fetch-dest document" "$(get_curl_args)" "Sec-Fetch-Dest: document"
    assert_contains "sec-fetch-user" "$(get_curl_args)" "Sec-Fetch-User: ?1"
    assert_contains "upgrade-insecure" "$(get_curl_args)" "Upgrade-Insecure-Requests: 1"
    assert_contains "accept html" "$(get_curl_args)" "Accept: text/html,application/xhtml+xml"
    assert_contains "accept-language" "$(get_curl_args)" "Accept-Language: en-US,en;q=0.9"
    assert_contains "accept-encoding full" "$(get_curl_args)" "Accept-Encoding: gzip, deflate, br, zstd"
    # Canonical wire order: UA is emitted via -H at slot 5, not first (curl -A
    # would send it first). Verify the surrounding sequence holds
    assert_curl_arg_order "platform before UA" "sec-ch-ua-platform: \"macOS\"" "User-Agent: Mozilla/5.0"
    assert_curl_arg_order "upgrade-insecure before UA" "Upgrade-Insecure-Requests: 1" "User-Agent: Mozilla/5.0"
    assert_curl_arg_order "UA before Accept" "User-Agent: Mozilla/5.0" "Accept: text/html"
    assert_curl_arg_order "Accept before Accept-Language" "Accept: text/html" "Accept-Language: en-US,en;q=0.9"
}

test_impersonation_override_wins() {
    run_script "https://example.com" --target "edge.somesite.com" -H "Accept-Language: fr"
    assert_rc "override" 0
    assert_contains "user AL present" "$(get_curl_args)" "Accept-Language: fr"
    assert_not_contains "no default AL" "$(get_curl_args)" "Accept-Language: en-US,en;q=0.9"
    assert_curl_arg_count "one Accept-Language value" "Accept-Language: fr" "1"
}

test_impersonation_ua_backoff() {
    run_script "https://example.com" --target "edge.somesite.com" -A "curl/8.7.1"
    assert_rc "backoff" 0
    assert_contains "user UA present" "$(get_curl_args)" "curl/8.7.1"
    # All three Chrome client hints suppressed against a non-Chrome UA
    assert_not_contains "no sec-ch-ua" "$(get_curl_args)" "sec-ch-ua:"
    assert_not_contains "no sec-ch-ua-mobile" "$(get_curl_args)" "sec-ch-ua-mobile:"
    assert_not_contains "no sec-ch-ua-platform" "$(get_curl_args)" "sec-ch-ua-platform:"
    # Neutral headers still sent (client-hint backoff does not drop these)
    assert_contains "sec-fetch still sent" "$(get_curl_args)" "Sec-Fetch-Mode:"
    assert_contains "accept still sent" "$(get_curl_args)" "Accept: text/html"
    assert_contains "accept-language still sent" "$(get_curl_args)" "Accept-Language: en-US,en;q=0.9"
    assert_contains "accept-encoding still sent" "$(get_curl_args)" "Accept-Encoding: gzip, deflate, br, zstd"
}

test_impersonation_ua_backoff_combined_h() {
    # Combined no-space -H form (-HUser-Agent:value) must trigger backoff too,
    # matching the spaced -H form and -A. Client hints suppressed, rest survives
    run_script "https://example.com" --target "edge.somesite.com" -H"User-Agent: curl/8.7.1"
    assert_rc "backoff-combined-h" 0
    assert_contains "user UA present" "$(get_curl_args)" "User-Agent: curl/8.7.1"
    assert_not_contains "no sec-ch-ua" "$(get_curl_args)" "sec-ch-ua:"
    assert_not_contains "no sec-ch-ua-mobile" "$(get_curl_args)" "sec-ch-ua-mobile:"
    assert_not_contains "no sec-ch-ua-platform" "$(get_curl_args)" "sec-ch-ua-platform:"
    assert_contains "accept still sent" "$(get_curl_args)" "Accept: text/html"
}

test_flag_platform_win() {
    run_script --platform win "https://example.com" --target "edge.somesite.com"
    assert_rc "platform-win" 0
    assert_contains "win UA" "$(get_curl_args)" "Windows NT 10.0; Win64; x64"
    assert_contains "win hint" "$(get_curl_args)" "sec-ch-ua-platform: \"Windows\""
}

test_flag_fetch_mode_cors() {
    run_script --fetch-mode cors "https://example.com" --target "edge.somesite.com"
    assert_rc "fetch-cors" 0
    assert_contains "accept star" "$(get_curl_args)" "Accept: */*"
    assert_contains "sf-mode cors" "$(get_curl_args)" "Sec-Fetch-Mode: cors"
    assert_contains "sf-dest empty" "$(get_curl_args)" "Sec-Fetch-Dest: empty"
    assert_not_contains "no sf-user in cors" "$(get_curl_args)" "Sec-Fetch-User"
    assert_not_contains "no UIR in cors" "$(get_curl_args)" "Upgrade-Insecure-Requests"
}

test_flag_no_impersonate() {
    run_script --no-impersonate "https://example.com" --target "edge.somesite.com"
    assert_rc "no-imp" 0
    assert_not_contains "no sec-ch-ua" "$(get_curl_args)" "sec-ch-ua"
    assert_not_contains "no sec-fetch" "$(get_curl_args)" "Sec-Fetch"
    assert_not_contains "no injected UA" "$(get_curl_args)" "Chrome/"
    assert_contains "still pins DNS" "$(get_curl_args)" "--resolve"
}

test_flag_chrome_major_beats_env() {
    export PIN_DNS_CHROME_MAJOR="111"
    run_script --chrome-major 222 "https://example.com" --target "edge.somesite.com"
    assert_rc "major-flag" 0
    assert_contains "flag major wins" "$(get_curl_args)" "Chrome/222.0.0.0"
}

test_flag_platform_invalid() {
    run_script --platform bsd "https://example.com" --target "edge.somesite.com"
    assert_rc "bad-platform" 2
    assert_stderr_contains "platform error" "Invalid --platform"
}

test_flag_equals_form() {
    run_script --platform=linux "https://example.com" --target "edge.somesite.com"
    assert_rc "eq-form" 0
    assert_contains "linux UA" "$(get_curl_args)" "X11; Linux x86_64"
    assert_contains "linux platform hint" "$(get_curl_args)" 'sec-ch-ua-platform: "Linux"'
}

# --- engine selection tests ---

test_engine_auto_uses_impersonate() {
    _install_impersonate_stub
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "auto-imp" 0
    assert_contains "impersonate called" "$(get_impersonate_args)" "--impersonate"
    # defaults shim returns 122.1.2.3 -> major 122
    assert_contains "impersonate chrome major" "$(get_impersonate_args)" "chrome122"
    assert_contains "compressed passed" "$(get_impersonate_args)" "--compressed"
    assert_contains "resolve passed through" "$(get_impersonate_args)" "example.com:443:192.0.2.11"
    # User-supplied URL token flows through verbatim (no trailing slash added)
    assert_contains "url passed through" "$(get_impersonate_args)" "https://example.com"
    # No header suite injected on the impersonate path
    assert_not_contains "no sec-ch-ua" "$(get_impersonate_args)" "sec-ch-ua"
    assert_not_contains "no sec-fetch" "$(get_impersonate_args)" "Sec-Fetch"
    assert_not_contains "no UA header on impersonate path" "$(get_impersonate_args)" "User-Agent:"
    assert_not_contains "no Accept-Encoding on impersonate path" "$(get_impersonate_args)" "Accept-Encoding:"
    # stock curl NOT used for the main request
    assert_eq "stock curl not called" "$(get_curl_args)" ""
}

test_engine_curl_forces_stock() {
    _install_impersonate_stub
    run_script --engine curl "https://example.com" --target "edge.somesite.com"
    assert_rc "force-curl" 0
    assert_contains "stock curl used" "$(get_curl_args)" "--resolve"
    assert_eq "impersonate not called" "$(get_impersonate_args)" ""
    assert_contains "headers present on stock" "$(get_curl_args)" "Sec-Fetch-Mode: navigate"
}

test_engine_impersonate_required_missing() {
    # no stub installed -> curl-impersonate absent
    run_script --engine impersonate "https://example.com" --target "edge.somesite.com"
    assert_rc "imp-missing" 3
    assert_stderr_contains "imp missing error" "curl-impersonate"
}

test_engine_invalid_enum() {
    run_script --engine=bogus "https://example.com" --target "edge.somesite.com"
    assert_rc "bad-engine" 2
    assert_stderr_contains "engine error" "Invalid --engine"
}

# --- cache tests ---

# Write a Version History API JSON fixture and point the script at it
_write_api_fixture() {
    local major="$1"
    printf '{"versions":[{"version":"%s.0.7000.99"}]}\n' "$major" > "$TEST_DIR/api.json"
    export PIN_DNS_VERSION_API_URL="file://$TEST_DIR/apiroot"
    # file:// path must expand to $TEST_DIR/apiroot/<plat>/channels/stable/versions?...
    # curl shim (below) maps any file:// version URL to api.json
}

test_cache_writes_then_reads() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    _write_api_fixture 199
    # First call: network path writes cache
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "first" 0
    assert_contains "uses fetched major" "$(get_curl_args)" "Chrome/199.0.0.0"
    assert_file_exists "cache written" "$TEST_DIR/cache/pin-dns/chrome-major.mac"
    # Second call: change fixture to prove cache (not network) is used
    _write_api_fixture 111
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "second" 0
    assert_contains "still cached 199" "$(get_curl_args)" "Chrome/199.0.0.0"
}

test_cache_ttl_zero_refetches() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    export PIN_DNS_UA_CACHE_TTL="0"
    _write_api_fixture 199
    run_script "https://example.com" --target "edge.somesite.com"
    _write_api_fixture 200
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "refetch" 0
    assert_contains "refetched 200" "$(get_curl_args)" "Chrome/200.0.0.0"
}

test_cache_corrupt_is_miss() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    mkdir -p "$TEST_DIR/cache/pin-dns"
    printf 'garbage not a record\n' > "$TEST_DIR/cache/pin-dns/chrome-major.mac"
    _write_api_fixture 177
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "corrupt-miss" 0
    assert_contains "fetched despite corrupt" "$(get_curl_args)" "Chrome/177.0.0.0"
}

test_cache_stale_if_error_within_window() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    export PIN_DNS_UA_OFFLINE="1" # force fetch to be skipped -> step 6
    mkdir -p "$TEST_DIR/cache/pin-dns"
    local now; now="$(date +%s)"
    local fetched=$((now - 100000)) # ~1.15 days old: past 24h TTL, within 90d
    {
        printf 'cacheVersion=1\nsource=versionhistory-api\nplatform=mac\n'
        printf 'major=155\nfetchedAt=%s\nttl=86400\nexpiresAt=%s\n' "$fetched" "$((fetched + 86400))"
    } > "$TEST_DIR/cache/pin-dns/chrome-major.mac"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "stale-served" 0
    assert_contains "serves stale 155 not pin" "$(get_curl_args)" "Chrome/155.0.0.0"
}

test_cache_stale_beyond_window_uses_pin() {
    export PIN_DNS_CHROME_APP="$TEST_DIR/NoSuchChrome.app"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    export PIN_DNS_UA_OFFLINE="1"
    mkdir -p "$TEST_DIR/cache/pin-dns"
    local now; now="$(date +%s)"
    local fetched=$((now - 9000000)) # ~104 days: beyond 90d max-stale
    {
        printf 'cacheVersion=1\nsource=versionhistory-api\nplatform=mac\n'
        printf 'major=155\nfetchedAt=%s\nttl=86400\nexpiresAt=%s\n' "$fetched" "$((fetched + 86400))"
    } > "$TEST_DIR/cache/pin-dns/chrome-major.mac"
    run_script "https://example.com" --target "edge.somesite.com"
    assert_rc "too-stale" 0
    assert_contains "falls to pin 148" "$(get_curl_args)" "Chrome/148.0.0.0"
    assert_not_contains "not stale 155" "$(get_curl_args)" "Chrome/155.0.0.0"
}

# --- run ---

run_tests "$@"
