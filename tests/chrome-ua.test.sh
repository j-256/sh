#!/bin/bash
# chrome-ua.test.sh - Tests for chrome-ua
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../chrome-ua"

# --- shims ---

write_shims() {
    # defaults shim: returns a fake Chrome version; logs its args
    # Returns empty (exit 0) when the plist path contains "badplist"
    cat > "$SHIM_DIR/defaults" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/defaults.log"
printf 'defaults' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
case "$*" in *badplist*) exit 0 ;; esac
printf '%s\n' "133.7.1234.99"
exit 0
SHIM
    chmod +x "$SHIM_DIR/defaults"

    # curl shim: logs args, returns a minimal Google Version History JSON
    # Supports per-platform response (mac/win/linux) via the path it's called with
    # Returns empty on exit 1 when $TEST_DIR/curl_fails exists
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
[ -f "$TEST_DIR/curl_fails" ] && exit 1
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
case "$url" in
    *platforms/mac/*)   ver="148.0.7778.56" ;;
    *platforms/win/*)   ver="148.0.7778.56" ;;
    *platforms/linux/*) ver="147.0.7727.116" ;;
    *)                  ver="148.0.7778.56" ;;
esac
cat <<EOF
{
  "versions": [
    {
      "name": "chrome/platforms/XXX/channels/stable/versions/$ver",
      "version": "$ver"
    }
  ]
}
EOF
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # Fake Chrome app directory that tests point --app at
    mkdir -p "$TEST_DIR/Chrome.app/Contents"
    : > "$TEST_DIR/Chrome.app/Contents/Info.plist"
}

# --- test cases: help and argument validation ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has EXIT STATUS" "EXIT STATUS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help mentions --latest" "--latest"
    assert_stdout_contains "help mentions --platform" "--platform"
    assert_stdout_contains "help names -l short" "-l, --latest"
    assert_stdout_contains "help names -p short" "-p, --platform"
    assert_stdout_contains "help names -a short" "-a, --app"
    assert_stdout_contains "help mentions env var" "CHROME_UA_OFFLINE"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_unknown_flag() {
    run_script --bogus
    assert_rc "unknown flag exits 2" 2
    assert_stderr_contains "error names flag" "Unknown argument '--bogus'"
}

test_app_requires_value() {
    run_script --app
    assert_rc "missing --app value exits 2" 2
    assert_stderr_contains "error mentions --app" "--app requires a path"
}

test_platform_requires_value() {
    run_script --platform
    assert_rc "missing --platform value exits 2" 2
    assert_stderr_contains "error mentions --platform" "--platform requires"
}

test_platform_rejects_invalid_value() {
    run_script --platform bsd
    assert_rc "bad platform exits 2" 2
    assert_stderr_contains "error lists valid values" "mac|win|linux"
}

# --- test cases: default mode (local read) ---

test_basic_ua_from_plist() {
    run_script --app "$TEST_DIR/Chrome.app"
    assert_rc "basic exits 0" 0
    local stdout; stdout="$(get_stdout)"
    assert_contains "UA prefix" "$stdout" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    assert_contains "UA Chrome major" "$stdout" "Chrome/133.0.0.0"
    assert_contains "UA suffix" "$stdout" "Safari/537.36"
    # No warnings on happy path
    assert_stderr_not_contains "no fallback warning" "fallback"
    # No network call on happy path
    assert_eq "curl not called" "$(cat "$TEST_DIR/curl.log" 2>/dev/null || echo "")" ""
}

test_app_equals_form() {
    run_script --app="$TEST_DIR/Chrome.app"
    assert_rc "--app=VALUE exits 0" 0
    assert_stdout_contains "UA printed" "Chrome/133.0.0.0"
}

test_defaults_invocation() {
    run_script --app "$TEST_DIR/Chrome.app"
    assert_rc "defaults invocation exits 0" 0
    local log; log="$(cat "$TEST_DIR/defaults.log")"
    assert_contains "defaults called with 'read'" "$log" " read "
    assert_contains "defaults passed plist path" "$log" "Chrome.app/Contents/Info.plist"
    assert_contains "defaults requested version key" "$log" "CFBundleShortVersionString"
}

test_major_only_zero_padded() {
    cat > "$SHIM_DIR/defaults" <<'SHIM'
#!/bin/bash
printf '%s\n' "99.5.6789.42"
exit 0
SHIM
    chmod +x "$SHIM_DIR/defaults"
    run_script --app "$TEST_DIR/Chrome.app"
    assert_rc "custom version exits 0" 0
    assert_stdout_contains "major padded to X.0.0.0" "Chrome/99.0.0.0"
    assert_stderr_not_contains "no fallback warning" "fallback"
}

# --- test cases: automatic network fallback (local failure -> network) ---

test_local_fails_auto_fetches_latest() {
    # App missing, curl available, no env var -> should fetch latest
    run_script --app "$TEST_DIR/NoSuchChrome.app"
    assert_rc "auto network fallback exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log" 2>/dev/null)"
    assert_contains "curl called" "$curl_log" "versionhistory.googleapis.com"
    assert_contains "mac platform requested" "$curl_log" "platforms/mac"
    assert_stderr_contains "warns about network fallback" "Local read failed"
    assert_stdout_contains "latest major from API" "Chrome/148.0.0.0"
}

test_local_fails_env_blocks_network() {
    run_script --app "$TEST_DIR/NoSuchChrome.app" </dev/null
    # Run again with env var set
    env CHROME_UA_OFFLINE=1 TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" --app "$TEST_DIR/NoSuchChrome.app" \
        >"$TEST_DIR/stdout2" 2>"$TEST_DIR/stderr2"
    local rc=$?
    assert_rc "env-blocked fallback exits 0" 0
    local stdout2; stdout2="$(cat "$TEST_DIR/stdout2")"
    local stderr2; stderr2="$(cat "$TEST_DIR/stderr2")"
    # curl.log was populated by the first run; the second run should have been skipped
    # To verify, use the stderr message shape
    assert_contains "stderr warns pinned fallback" "$stderr2" "pinned"
    assert_contains "stdout still valid UA" "$stdout2" "Safari/537.36"
    # Exit status captured separately
    [ "$rc" -eq 0 ] || echo "[FAIL] env-blocked run: expected rc=0, got $rc" >&2
}

test_local_fails_network_fails_falls_back_to_pinned() {
    touch "$TEST_DIR/curl_fails"
    run_script --app "$TEST_DIR/NoSuchChrome.app"
    assert_rc "double failure still exits 0" 0
    assert_stderr_contains "warns pinned fallback" "pinned"
    assert_stdout_contains "UA prefix" "Mozilla/5.0 (Macintosh"
    assert_stdout_contains "UA suffix" "Safari/537.36"
}

test_plist_unreadable_triggers_network_fallback() {
    mkdir -p "$TEST_DIR/badplist.app/Contents"
    : > "$TEST_DIR/badplist.app/Contents/Info.plist"
    run_script --app "$TEST_DIR/badplist.app"
    assert_rc "unreadable plist exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log" 2>/dev/null)"
    assert_contains "auto-fetched latest" "$curl_log" "versionhistory.googleapis.com"
    assert_stdout_contains "latest UA" "Chrome/148.0.0.0"
}

# --- test cases: explicit --latest ---

test_latest_flag_fetches_from_api() {
    run_script --latest
    assert_rc "--latest exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log")"
    assert_contains "curl hit version API" "$curl_log" "versionhistory.googleapis.com"
    assert_contains "mac platform (default)" "$curl_log" "platforms/mac"
    assert_contains "pageSize=1" "$curl_log" "pageSize=1"
    # --latest skips defaults entirely
    local defaults_log; defaults_log="$(cat "$TEST_DIR/defaults.log" 2>/dev/null || echo "")"
    assert_eq "defaults not called with --latest" "$defaults_log" ""
    assert_stdout_contains "UA has latest version" "Chrome/148.0.0.0"
}

test_latest_with_curl_failure_falls_back_to_pinned() {
    touch "$TEST_DIR/curl_fails"
    run_script --latest
    assert_rc "--latest curl fail exits 0" 0
    assert_stderr_contains "warns curl fail" "fetch"
    assert_stderr_contains "warns pinned fallback" "pinned"
    assert_stdout_contains "UA emitted" "Safari/537.36"
}

test_latest_ignores_no_network_env() {
    # Explicit --latest should still fetch even with the env var set
    env CHROME_UA_OFFLINE=1 TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" --latest \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "--latest + env exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log")"
    assert_contains "curl was still called" "$curl_log" "versionhistory.googleapis.com"
}

# --- test cases: --platform (UA shape) ---

test_platform_mac_ua_shape() {
    run_script --platform mac --app "$TEST_DIR/Chrome.app"
    assert_rc "platform mac exits 0" 0
    assert_stdout_contains "mac platform string" "Macintosh; Intel Mac OS X 10_15_7"
}

test_platform_win_ua_shape() {
    run_script --platform win --app "$TEST_DIR/Chrome.app"
    assert_rc "platform win exits 0" 0
    assert_stdout_contains "win platform string" "Windows NT 10.0; Win64; x64"
}

test_platform_linux_ua_shape() {
    run_script --platform linux --app "$TEST_DIR/Chrome.app"
    assert_rc "platform linux exits 0" 0
    assert_stdout_contains "linux platform string" "X11; Linux x86_64"
}

test_latest_with_platform_win() {
    run_script --latest --platform win
    assert_rc "--latest --platform win exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log")"
    assert_contains "win API path requested" "$curl_log" "platforms/win"
    assert_stdout_contains "win UA shape" "Windows NT 10.0; Win64; x64"
    assert_stdout_contains "win version from API" "Chrome/148.0.0.0"
}

test_latest_with_platform_linux() {
    run_script --latest --platform linux
    assert_rc "--latest --platform linux exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log")"
    assert_contains "linux API path requested" "$curl_log" "platforms/linux"
    assert_stdout_contains "linux UA shape" "X11; Linux x86_64"
    assert_stdout_contains "linux version from API" "Chrome/147.0.0.0"
}

# --- test cases: short-option aliases (-l/-p/-a) ---

test_short_latest() {
    # -l is the short for --latest: skips local read, fetches from the API
    run_script -l
    assert_rc "-l exits 0" 0
    local curl_log; curl_log="$(cat "$TEST_DIR/curl.log")"
    assert_contains "-l hits version API (latest mode)" "$curl_log" "versionhistory.googleapis.com"
    assert_stdout_contains "-l emits latest UA" "Chrome/148.0.0.0"
}

test_short_platform() {
    # -p is the short for --platform: sets the UA shape
    run_script -p win --app "$TEST_DIR/Chrome.app"
    assert_rc "-p exits 0" 0
    assert_stdout_contains "-p sets Windows UA shape" "Windows NT 10.0; Win64; x64"
}

test_short_platform_glued() {
    # -p takes a value; the glued form (-pVALUE) must survive _expand_short_opts "pa"
    run_script -pwin --app "$TEST_DIR/Chrome.app"
    assert_rc "-pwin exits 0" 0
    assert_stdout_contains "-pwin sets Windows UA shape" "Windows NT 10.0; Win64; x64"
}

test_short_app() {
    # -a is the short for --app: points local mode at a specific Chrome.app
    run_script -a "$TEST_DIR/Chrome.app"
    assert_rc "-a exits 0" 0
    assert_stdout_contains "-a reads that app's version" "Chrome/133.0.0.0"
}

test_short_app_glued() {
    # -a takes a value; the glued form (-aPATH) must survive _expand_short_opts "pa"
    run_script -a"$TEST_DIR/Chrome.app"
    assert_rc "-a<path> exits 0" 0
    assert_stdout_contains "-a<path> reads that app's version" "Chrome/133.0.0.0"
}

# --- run ---

run_tests "$@"
