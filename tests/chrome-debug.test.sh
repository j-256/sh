#!/bin/bash
# chrome-debug.test.sh - Tests for chrome-debug
# shellcheck source-path=SCRIPTDIR disable=SC2329

# NOTE: the real launch + foreground-wait against a live browser is NOT unit-tested
# (needs a real Chrome and blocks on `wait`). See docs/chrome-debug.md "Manual
# verification". The two test_launch_* cases use shims and a fast-exit fake browser
# to cover the print/linkage and probe-failure branches only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../chrome-debug"

# --- shims ---
# nc shim: ports listed in $TEST_DIR/busy_ports (one per line) report busy (rc 0),
# all others free (rc 1). Mirrors `nc -z host port`.
write_shims() {
    cat > "$SHIM_DIR/nc" <<'SHIM'
#!/bin/bash
port=""
for a in "$@"; do case "$a" in [0-9]*) port="$a" ;; esac; done
if [ -f "$TEST_DIR/busy_ports" ] && grep -qx "$port" "$TEST_DIR/busy_ports"; then
    exit 0   # busy
fi
exit 1       # free
SHIM
    chmod +x "$SHIM_DIR/nc"
}

# Minimal .mcp.json fixture with two chrome-devtools entries (9222, 9223).
write_mcp_fixture() {
    cat > "$TEST_DIR/mcp.json" <<'JSON'
{"mcpServers":{
  "chrome-devtools-9222":{"type":"stdio","command":"npx","args":["chrome-devtools-mcp@latest","--browser-url=http://127.0.0.1:9222"]},
  "chrome-devtools-9223":{"type":"stdio","command":"npx","args":["chrome-devtools-mcp@latest","--browser-url=http://127.0.0.1:9223"]},
  "markview":{"type":"stdio","command":"npx","args":["mcp-server-markview"]}
}}
JSON
}

# Build a fake .app bundle at $1 whose CFBundleExecutable is $2.
make_app() {
    local app="$1"; local exe="$2"
    mkdir -p "$app/Contents/MacOS"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$exe</string>
</dict></plist>
PLIST
    printf '#!/bin/bash\necho fake-browser\n' > "$app/Contents/MacOS/$exe"
    chmod +x "$app/Contents/MacOS/$exe"
}

# Run the script with a chosen working directory (for relative-path cases).
run_script_in_dir() {
    local dir="$1"; shift
    ( cd "$dir" || exit 1
      env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" /bin/bash "$UNDER_TEST" "$@"
    ) >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# helper: a valid browser arg for tests that only care about port logic
_any_browser() { make_app "$TEST_DIR/B.app" "B"; printf '%s' "$TEST_DIR/B.app"; }

# Run with a controlled HOME (walk-up ceiling) and CHROME_DEBUG_MCP_JSON unset,
# from a chosen launch dir. For testing .mcp.json walk-up discovery.
run_script_walkup() {
    local home="$1"; local dir="$2"; shift 2
    ( cd "$dir" || exit 1
      env -u CHROME_DEBUG_MCP_JSON TEST_DIR="$TEST_DIR" HOME="$home" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" "$@"
    ) >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Write a .mcp.json at $1 containing a single chrome-devtools server on port $2, name $3.
write_pool_at() {
    local dir="$1"; local port="$2"; local name="$3"
    mkdir -p "$dir"
    cat > "$dir/.mcp.json" <<JSON
{"mcpServers":{"$name":{"type":"stdio","command":"npx","args":["chrome-devtools-mcp@latest","--browser-url=http://127.0.0.1:$port"]}}}
JSON
}

# --- test cases ---

test_help_exits_0_and_has_sections() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help NAME" "NAME"
    assert_stdout_contains "help SYNOPSIS" "SYNOPSIS"
}

test_missing_positional_is_usage_error() {
    run_script
    assert_rc "no browser-location exits 2" 2
    assert_stderr_contains "usage hint" "Run \`chrome-debug -h\` for usage"
}

test_unknown_flag_is_usage_error() {
    run_script --bogus /Applications/Google\ Chrome.app
    assert_rc "unknown flag exits 2" 2
    assert_stderr_contains "unknown arg" "Unknown argument"
}

test_port_flag_requires_value() {
    run_script -p
    assert_rc "-p with no value exits 2" 2
    assert_stderr_contains "port needs value" "requires a value"
}

test_resolve_app_bundle() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    make_app "$TEST_DIR/Test.app" "Test Browser"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/Test.app"
    assert_rc "resolve .app exits 0" 0
    assert_stdout_contains "resolved to inner binary" "browser: $TEST_DIR/Test.app/Contents/MacOS/Test Browser"
}

test_resolve_raw_executable() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    printf '#!/bin/bash\n:\n' > "$TEST_DIR/rawchrome"
    chmod +x "$TEST_DIR/rawchrome"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/rawchrome"
    assert_rc "resolve raw exe exits 0" 0
    assert_stdout_contains "raw exe used directly" "browser: $TEST_DIR/rawchrome"
}

test_resolve_directory_finds_app() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    make_app "$TEST_DIR/dl/chrome-mac-arm64/Chrome for Testing.app" "Google Chrome for Testing"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/dl"
    assert_rc "resolve dir exits 0" 0
    assert_stdout_contains "found buried app" "browser: $TEST_DIR/dl/chrome-mac-arm64/Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
}

test_resolve_directory_multiple_versions_newest_wins() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    make_app "$TEST_DIR/c/mac_arm-149.0.7827.103/x/A.app" "Google Chrome for Testing"
    make_app "$TEST_DIR/c/mac_arm-150.0.7871.46/x/B.app" "Google Chrome for Testing"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/c"
    assert_rc "multi-version exits 0" 0
    assert_stdout_contains "newest version chosen" "mac_arm-150.0.7871.46"
}

test_resolve_missing_path_errors() {
    # Fixture pool is defense-in-depth, not load-bearing: _resolve_browser fails
    # and returns 1 before _select_port ever runs. Added anyway so this test
    # never depends on the real ~/.mcp.json, even if the call order changes later.
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/nope"
    assert_rc "missing path exits 1" 1
    assert_stderr_contains "not found msg" "not found"
}

test_resolve_directory_no_app_errors() {
    # Fixture pool is defense-in-depth, not load-bearing: _resolve_browser fails
    # and returns 1 before _select_port ever runs. Added anyway so this test
    # never depends on the real ~/.mcp.json, even if the call order changes later.
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    mkdir -p "$TEST_DIR/empty"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/empty"
    assert_rc "no app in dir exits 1" 1
    assert_stderr_contains "no app msg" "no .app"
}

test_resolve_directory_ignores_nested_helper_apps() {
    # A realistic bundle: top-level browser .app with a nested Helper .app inside
    # Contents/Frameworks. Pointing at the PARENT dir must resolve the browser,
    # not the (version-sort-last) helper.
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    local base="$TEST_DIR/dl/chrome-mac-arm64/Google Chrome for Testing.app"
    make_app "$base" "Google Chrome for Testing"
    make_app "$base/Contents/Frameworks/cr.framework/Versions/150/Helpers/Google Chrome for Testing Helper (Renderer).app" "Google Chrome for Testing Helper (Renderer)"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$TEST_DIR/dl"
    assert_rc "nested-helper dir exits 0" 0
    assert_stdout_contains "resolves top-level browser, not helper" "browser: $base/Contents/MacOS/Google Chrome for Testing"
    assert_stdout_not_contains "does not pick a helper" "Helper (Renderer)"
}

test_resolve_relative_app_path() {
    # A relative .app path must resolve (defaults read rejects relative bundle paths,
    # so the resolver must absolutize first). run_script cds into $TEST_DIR via the
    # relative-path runner below.
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    make_app "$TEST_DIR/Rel.app" "Rel Browser"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script_in_dir "$TEST_DIR" -n "Rel.app"
    assert_rc "relative .app exits 0" 0
    assert_stdout_contains "absolutized resolved path" "browser: $TEST_DIR/Rel.app/Contents/MacOS/Rel Browser"
}

test_pool_parses_browser_url_entries() {
    write_mcp_fixture
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script --print-pool
    assert_rc "print-pool exits 0" 0
    assert_stdout_contains "pool has 9222" "9222 chrome-devtools-9222"
    assert_stdout_contains "pool has 9223" "9223 chrome-devtools-9223"
    assert_stdout_not_contains "excludes non-chrome server" "markview"
}

test_pool_parses_wsendpoint_entry() {
    cat > "$TEST_DIR/mcp.json" <<'JSON'
{"mcpServers":{
  "cdp-ws":{"command":"npx","args":["chrome-devtools-mcp@latest","--wsEndpoint","ws://127.0.0.1:9401/devtools/browser/abc"]}
}}
JSON
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script --print-pool
    assert_rc "ws pool exits 0" 0
    assert_stdout_contains "ws port parsed" "9401 cdp-ws"
}

test_pool_missing_file_errors() {
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/nope.json" run_script --print-pool
    assert_rc "missing mcp.json exits 1" 1
}

test_pool_no_chrome_entries_errors() {
    cat > "$TEST_DIR/mcp.json" <<'JSON'
{"mcpServers":{"markview":{"command":"npx","args":["mcp-server-markview"]}}}
JSON
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script --print-pool
    assert_rc "no chrome entries exits 1" 1
}

test_help_works_without_jq() {
    # --help must never require a dependency. Restrict PATH to a shim dir that
    # deliberately has NO jq, plus the coreutils the script needs.
    for t in bash basename dirname cat printf grep sed find sort tail awk; do
        src="$(command -v "$t" 2>/dev/null)"
        [ -n "$src" ] && ln -s "$src" "$SHIM_DIR/$t"
    done
    # Ensure no jq in the shim dir
    rm -f "$SHIM_DIR/jq"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" --help \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "help without jq exits 0" 0
    assert_stdout_contains "help still shows NAME without jq" "NAME"
}

test_port_default_lowest_free() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"    # nothing busy
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)"
    assert_rc "default port exits 0" 0
    assert_stdout_contains "picks 9222" "port: 9222"
    assert_stdout_contains "names server" "server: chrome-devtools-9222"
}

test_port_default_skips_busy() {
    write_mcp_fixture
    printf '9222\n' > "$TEST_DIR/busy_ports"   # 9222 busy -> pick 9223
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)"
    assert_rc "skip busy exits 0" 0
    assert_stdout_contains "picks 9223" "port: 9223"
}

test_port_all_busy_errors() {
    write_mcp_fixture
    printf '9222\n9223\n' > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)"
    assert_rc "all busy exits 1" 1
    assert_stderr_contains "all-busy guidance" "in use"
}

test_port_explicit_in_pool() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -p 9223 "$(_any_browser)"
    assert_rc "explicit in-pool exits 0" 0
    assert_stdout_contains "uses 9223" "port: 9223"
    assert_stdout_contains "names server" "server: chrome-devtools-9223"
}

test_port_explicit_off_pool_warns_but_proceeds() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -p 9299 "$(_any_browser)"
    assert_rc "off-pool exits 0" 0
    assert_stdout_contains "uses 9299" "port: 9299"
    assert_stdout_contains "no server" "server: (none)"
    assert_stderr_contains "off-pool warning" "no chrome-devtools entry for :9299"
}

test_port_explicit_busy_errors() {
    write_mcp_fixture
    printf '9223\n' > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -p 9223 "$(_any_browser)"
    assert_rc "explicit busy exits 1" 1
    assert_stderr_contains "busy msg" "already in use"
}

test_profile_default_per_port() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)"
    assert_stdout_contains "default profile" "profile: /tmp/chrome-debug-9222"
}

test_profile_explicit() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -d /tmp/myprof "$(_any_browser)"
    assert_stdout_contains "explicit profile" "profile: /tmp/myprof"
}

test_args_include_baked_flags() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -p 9223 "$(_any_browser)"
    assert_stdout_contains "remote-debugging-port" "args: --remote-debugging-port=9223"
    assert_stdout_contains "user-data-dir flag" "--user-data-dir=/tmp/chrome-debug-9223"
    assert_stdout_contains "no-first-run" "--no-first-run"
    assert_stdout_contains "no-default-browser-check" "--no-default-browser-check"
}

test_disable_sync_baked_in_by_default() {
    # --disable-sync is always passed (like --no-first-run): a debug browser must
    # not pull in synced bookmarks/history/passwords/extensions. Verified against
    # managed Edge, where account sign-in is forced but sync-down is suppressible.
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)"
    assert_rc "default dry-run exits 0" 0
    assert_stdout_contains "disable-sync baked in" "--disable-sync"
}

test_args_passthrough_appended() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)" -- --headless=new --lang=en-GB
    assert_stdout_contains "passthrough headless" "--headless=new"
    assert_stdout_contains "passthrough lang" "--lang=en-GB"
}

# Launch happy path: shim curl to return a version JSON; use a fast-exit fake browser
# so the foreground `wait` returns without blocking the test.
test_launch_prints_confirmation_and_linkage() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
for a in "$@"; do case "$a" in *json/version*) echo '{"Browser":"Chrome/150.0.7871.46"}'; exit 0 ;; esac; done
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/fastexit"
    chmod +x "$TEST_DIR/fastexit"

    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -p 9222 "$TEST_DIR/fastexit"
    assert_rc "launch exits 0" 0
    assert_stdout_contains "confirmation w/ browser+port" "launched Chrome/150.0.7871.46, listening on :9222"
    assert_stdout_contains "linkage line" "attach via MCP server 'chrome-devtools-9222'"
}

test_launch_probe_failure_errors() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/fastexit"
    chmod +x "$TEST_DIR/fastexit"

    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" CHROME_DEBUG_PROBE_TRIES=2 CHROME_DEBUG_PROBE_SLEEP=0 \
        run_script -p 9222 "$TEST_DIR/fastexit"
    assert_rc "probe failure exits 1" 1
    assert_stderr_contains "probe fail msg" "debug endpoint never came up"
}

test_dry_run_works_without_curl() {
    # Dry-run never launches, so it must not require curl. jq+nc are still needed
    # (pool parse + port liveness run during dry-run) so shim those, omit curl.
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    for t in bash basename dirname cat printf grep sed find sort tail awk nc jq defaults; do
        src="$(command -v "$t" 2>/dev/null)"
        [ -n "$src" ] && ln -sf "$src" "$SHIM_DIR/$t"
    done
    rm -f "$SHIM_DIR/curl"
    local app="$TEST_DIR/T.app"
    make_app "$app" "T"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" \
        /bin/bash "$UNDER_TEST" -n "$app" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "dry-run without curl exits 0" 0
    assert_stdout_contains "dry-run still prints args" "args:"
}

# Already-serving: nc reports the port busy AND curl reports DevTools serving.
# The fake browser records a launch by touching $TEST_DIR/launched, so we can
# assert the script did NOT relaunch when the port was already serving.
test_already_serving_prints_linkage_without_launching() {
    write_mcp_fixture
    printf '9222\n' > "$TEST_DIR/busy_ports"   # port busy (a serving port is listening)
    printf '9222\n' > "$TEST_DIR/serving_ports" # and it is serving DevTools
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
port=""
for a in "$@"; do case "$a" in *127.0.0.1:*) port="${a##*127.0.0.1:}"; port="${port%%/*}" ;; esac; done
if [ -f "$TEST_DIR/serving_ports" ] && grep -qx "$port" "$TEST_DIR/serving_ports"; then
    echo '{"Browser":"Chrome/150.0.7871.46"}'
    exit 0
fi
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"
    # Fake browser that records if it is ever launched (it must NOT be)
    rm -f "$TEST_DIR/launched"
    printf '#!/bin/bash\ntouch "$TEST_DIR/launched"\nexit 0\n' > "$TEST_DIR/recorder"
    chmod +x "$TEST_DIR/recorder"

    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -p 9222 "$TEST_DIR/recorder"
    assert_rc "already-serving exits 0" 0
    assert_stdout_contains "confirmation w/ port" "already serving on :9222"
    assert_stdout_contains "linkage line" "attach via MCP server 'chrome-devtools-9222'"
    if [ -f "$TEST_DIR/launched" ]; then
        echo "[FAIL] already-serving must not relaunch: browser was launched" >&2
        return 1
    fi
}

test_fresh_wipes_profile_before_launch() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    : > "$TEST_DIR/serving_ports"
    # curl serves on first probe so the launch completes fast
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
for a in "$@"; do case "$a" in *json/version*) echo '{"Browser":"Chrome/150"}'; exit 0 ;; esac; done
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/fastexit"
    chmod +x "$TEST_DIR/fastexit"
    # Pre-seed the profile dir with a sentinel; --fresh must wipe it
    mkdir -p "$TEST_DIR/prof"
    printf 'stale\n' > "$TEST_DIR/prof/sentinel"

    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -f -d "$TEST_DIR/prof" -p 9222 "$TEST_DIR/fastexit"
    assert_rc "fresh launch exits 0" 0
    if [ -f "$TEST_DIR/prof/sentinel" ]; then
        echo "[FAIL] --fresh must wipe the profile dir: sentinel still present" >&2
        return 1
    fi
}

test_fresh_does_not_wipe_during_dry_run() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    mkdir -p "$TEST_DIR/prof"
    printf 'keep\n' > "$TEST_DIR/prof/sentinel"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -f -d "$TEST_DIR/prof" "$(_any_browser)"
    assert_rc "dry-run fresh exits 0" 0
    assert_file_exists "dry-run does not wipe" "$TEST_DIR/prof/sentinel"
}

test_port_must_be_numeric() {
    # A non-numeric -p would flow into /tmp/chrome-debug-<port> and, with --fresh,
    # into rm -rf -- so reject it at parse time (defense-in-depth for the wipe).
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -p "../../evil" "$(_any_browser)"
    assert_rc "non-numeric port exits 2" 2
    assert_stderr_contains "numeric msg" "must be a port number"
}

test_fresh_ignored_when_already_serving_warns() {
    write_mcp_fixture
    printf '9222\n' > "$TEST_DIR/busy_ports"
    printf '9222\n' > "$TEST_DIR/serving_ports"
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
port=""
for a in "$@"; do case "$a" in *127.0.0.1:*) port="${a##*127.0.0.1:}"; port="${port%%/*}" ;; esac; done
if [ -f "$TEST_DIR/serving_ports" ] && grep -qx "$port" "$TEST_DIR/serving_ports"; then
    echo '{"Browser":"Chrome/150"}'; exit 0
fi
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"
    printf '#!/bin/bash\ntouch "$TEST_DIR/launched"\nexit 0\n' > "$TEST_DIR/recorder"
    chmod +x "$TEST_DIR/recorder"
    rm -f "$TEST_DIR/launched"

    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -f -p 9222 "$TEST_DIR/recorder"
    assert_rc "fresh+serving exits 0" 0
    assert_stderr_contains "warns fresh ignored" "already serving"
    if [ -f "$TEST_DIR/launched" ]; then
        echo "[FAIL] fresh+serving must not relaunch" >&2
        return 1
    fi
}

test_no_extensions_flag_injects_disable_extensions() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n --no-extensions "$(_any_browser)"
    assert_rc "no-extensions dry-run exits 0" 0
    assert_stdout_contains "injects --disable-extensions" "--disable-extensions"
}

test_no_extensions_absent_by_default() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)"
    assert_rc "default dry-run exits 0" 0
    assert_stdout_not_contains "no --disable-extensions by default" "--disable-extensions"
}

test_launch_message_says_launched_not_attached() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
for a in "$@"; do case "$a" in *json/version*) echo '{"Browser":"Chrome/150"}'; exit 0 ;; esac; done
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"
    printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/fastexit"
    chmod +x "$TEST_DIR/fastexit"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -p 9222 "$TEST_DIR/fastexit"
    assert_rc "launch exits 0" 0
    assert_stdout_contains "fresh launch says launched" "launched"
}

test_already_serving_message_says_already() {
    write_mcp_fixture
    printf '9222\n' > "$TEST_DIR/busy_ports"
    printf '9222\n' > "$TEST_DIR/serving_ports"
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
port=""
for a in "$@"; do case "$a" in *127.0.0.1:*) port="${a##*127.0.0.1:}"; port="${port%%/*}" ;; esac; done
if [ -f "$TEST_DIR/serving_ports" ] && grep -qx "$port" "$TEST_DIR/serving_ports"; then
    echo '{"Browser":"Chrome/150"}'; exit 0
fi
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"
    printf '#!/bin/bash\ntouch "$TEST_DIR/launched"\nexit 0\n' > "$TEST_DIR/recorder"
    chmod +x "$TEST_DIR/recorder"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -p 9222 "$TEST_DIR/recorder"
    assert_rc "already-serving exits 0" 0
    assert_stdout_contains "attach case says already serving" "already serving"
    assert_stdout_not_contains "attach case does not say launched" "launched"
}

test_walkup_finds_mcp_json_at_home_ceiling() {
    # .mcp.json only at the HOME ceiling; launch from a deep subdir -> found via walk-up.
    : > "$TEST_DIR/busy_ports"
    local home="$TEST_DIR/home"
    write_pool_at "$home" 9222 chrome-devtools-9222
    mkdir -p "$home/proj/sub"
    run_script_walkup "$home" "$home/proj/sub" -n "$(_any_browser)"
    assert_rc "walkup to home exits 0" 0
    assert_stdout_contains "found home .mcp.json" "port: 9222"
    assert_stdout_contains "names server" "server: chrome-devtools-9222"
}

test_walkup_stops_at_home_not_above() {
    # .mcp.json ABOVE home must NOT be found (ceiling is home).
    : > "$TEST_DIR/busy_ports"
    local home="$TEST_DIR/home2"
    mkdir -p "$home/proj"
    write_pool_at "$TEST_DIR" 9999 chrome-devtools-9999   # above home ($TEST_DIR is home's parent)
    run_script_walkup "$home" "$home/proj" -n "$(_any_browser)"
    # No pool at/below home -> empty pool, default-port path errors (exit 1)
    assert_rc "no pool below home exits 1" 1
    assert_stdout_not_contains "did NOT pick the above-home port" "port: 9999"
}

test_walkup_closer_file_wins_but_unions() {
    # A closer subdir .mcp.json (9223) plus one at home (9222): both in the pool,
    # so default picks lowest (9222) but 9223 is present too. Proves union, not replace.
    : > "$TEST_DIR/busy_ports"
    local home="$TEST_DIR/home3"
    write_pool_at "$home" 9222 chrome-devtools-9222
    write_pool_at "$home/proj" 9223 chrome-devtools-9223
    # print-pool shows the union
    run_script_walkup "$home" "$home/proj" --print-pool
    assert_rc "walkup print-pool exits 0" 0
    assert_stdout_contains "union has home port" "9222 chrome-devtools-9222"
    assert_stdout_contains "union has closer port" "9223 chrome-devtools-9223"
}

test_walkup_dedupes_by_port_closer_name_wins() {
    # Same port at home and a closer dir, different names -> one entry, closer name wins.
    : > "$TEST_DIR/busy_ports"
    local home="$TEST_DIR/home4"
    write_pool_at "$home" 9222 home-name
    write_pool_at "$home/proj" 9222 closer-name
    run_script_walkup "$home" "$home/proj" --print-pool
    assert_rc "dedupe print-pool exits 0" 0
    assert_stdout_contains "closer name wins for shared port" "9222 closer-name"
    assert_stdout_not_contains "home name suppressed for shared port" "home-name"
}

test_env_override_bypasses_walkup() {
    # CHROME_DEBUG_MCP_JSON set -> use exactly that file, ignore walk-up entirely.
    : > "$TEST_DIR/busy_ports"
    local home="$TEST_DIR/home5"
    write_pool_at "$home/proj" 9223 should-be-ignored
    write_mcp_fixture   # $TEST_DIR/mcp.json has 9222+9223 chrome-devtools-*
    ( cd "$home/proj" || exit 1
      env TEST_DIR="$TEST_DIR" HOME="$home" CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" --print-pool
    ) >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "override print-pool exits 0" 0
    assert_stdout_contains "uses override file" "chrome-devtools-9222"
    assert_stdout_not_contains "ignores walkup file" "should-be-ignored"
}

test_missing_jq_exits_3() {
    # A real (non --help) invocation with jq absent -> dependency error, exit 3.
    for t in bash basename dirname cat printf grep sed find sort tail awk nc; do
        src="$(command -v "$t" 2>/dev/null)"
        [ -n "$src" ] && ln -sf "$src" "$SHIM_DIR/$t"
    done
    rm -f "$SHIM_DIR/jq"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" -n "$TEST_DIR/whatever.app" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing jq exits 3" 3
    assert_stderr_contains "names jq" "jq is required"
}

test_missing_nc_exits_3() {
    for t in bash basename dirname cat printf grep sed find sort tail awk jq; do
        src="$(command -v "$t" 2>/dev/null)"
        [ -n "$src" ] && ln -sf "$src" "$SHIM_DIR/$t"
    done
    rm -f "$SHIM_DIR/nc"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" -n "$TEST_DIR/whatever.app" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing nc exits 3" 3
    assert_stderr_contains "names nc" "nc is required"
}

test_port_equals_form() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n --port=9223 "$(_any_browser)"
    assert_rc "--port=N exits 0" 0
    assert_stdout_contains "equals-form port used" "port: 9223"
}

test_port_attached_short_form() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n -p9223 "$(_any_browser)"
    assert_rc "-p9223 exits 0" 0
    assert_stdout_contains "attached short-form port used" "port: 9223"
}

test_multiple_positionals_is_usage_error() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n "$(_any_browser)" /Applications/Extra.app
    assert_rc "two positionals exits 2" 2
    assert_stderr_contains "multiple msg" "Multiple browser locations"
}

test_empty_user_data_dir_value_is_usage_error() {
    write_mcp_fixture
    : > "$TEST_DIR/busy_ports"
    CHROME_DEBUG_MCP_JSON="$TEST_DIR/mcp.json" run_script -n --user-data-dir= "$(_any_browser)"
    assert_rc "empty --user-data-dir= exits 2" 2
    assert_stderr_contains "requires a value" "requires a value"
}

# --- run ---
run_tests "$@"
