#!/bin/bash
# curl-timing.test.sh - Tests for curl-timing
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../curl-timing"

# --- shims ---

write_shims() {
    # curl shim: log args, return fake timing
    # Return 6-decimal value so _req's sed pipeline yields a non-empty ms integer
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf 'curl' >> "$TEST_DIR/curl.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/curl.log"; done
printf '\n' >> "$TEST_DIR/curl.log"
printf '0.136015\n'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # bc shim: handle the common expressions
    cat > "$SHIM_DIR/bc" <<'SHIM'
#!/bin/bash
input=$(cat)
case "$input" in
    *"/"*) echo "136" ;;
    *"+"*) echo "272" ;;
    *"-"*) echo "0" ;;
    *"*"*) echo "50" ;;
    *) echo "136" ;;
esac
SHIM
    chmod +x "$SHIM_DIR/bc"

    # tput shim: no-op
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"
}

# Override run_script to cd to TEST_DIR (curl-timing writes logs to CWD)
run_script() {
    ( cd "$TEST_DIR" || exit 1
      env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
          /bin/bash "$UNDER_TEST" "$@"
    ) >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# --- test cases ---

test_help_long() {
    run_script --help
    assert_rc "--help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has EXIT STATUS" "EXIT STATUS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_help_short() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
}

test_missing_url_exits_2() {
    run_script
    assert_rc "no args exits 2" 2
    assert_err_contains "error mentions URL" "URL"
}

test_unknown_flag_exits_2() {
    run_script --nope https://example.com
    assert_rc "unknown flag exits 2" 2
    assert_err_contains "error mentions unknown" "Unknown"
}

test_basic_url_argument() {
    run_script https://example.com
    assert_rc "basic URL exits 0" 0
    assert_contains "curl called" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "curl"
    assert_contains "curl got URL" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "https://example.com"
    assert_contains "curl -sS" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "-sS"
    assert_contains "curl -w" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "-w"
}

test_default_num_requests() {
    run_script https://example.com
    assert_rc "default -n exits 0" 0
    # Default is 10 requests -> 10 curl invocations
    local count
    count=$(grep -c '^curl ' "$TEST_DIR/curl.log" 2>/dev/null | tr -d ' ')
    assert_eq "10 curl calls by default" "$count" "10"
}

test_num_requests_flag() {
    run_script -n 3 https://example.com
    assert_rc "-n 3 exits 0" 0
    local count
    count=$(grep -c '^curl ' "$TEST_DIR/curl.log" 2>/dev/null | tr -d ' ')
    assert_eq "3 curl calls with -n 3" "$count" "3"
}

test_output_to_devnull() {
    run_script -n 1 https://example.com
    assert_rc "-n 1 exits 0" 0
    assert_contains "curl -o /dev/null" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "/dev/null"
}

test_ms_in_output() {
    run_script -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_stdout_contains "output has ms" "ms"
}

test_log_file_written() {
    run_script -n 2 https://example.com
    assert_rc "exit 0" 0
    assert_file_exists "log file exists" "$TEST_DIR/curl-timing.txt"
}

test_stats_file_written() {
    run_script -n 2 https://example.com
    assert_rc "exit 0" 0
    assert_file_exists "stats file exists" "$TEST_DIR/curl-timing_stats.txt"
}

test_no_save_suppresses_files() {
    run_script --no-save -n 2 https://example.com
    assert_rc "exit 0" 0
    local count
    count=$(find "$TEST_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "no .txt files with --no-save" "$count" "0"
}

test_user_agent_default() {
    run_script -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_contains "default UA" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "curl-timing"
}

test_user_agent_custom() {
    run_script -A "MyTool/2.0" -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_contains "custom UA passed" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "MyTool/2.0"
}

test_method_flag() {
    run_script -X PUT -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_contains "curl -X PUT" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "-X"
    assert_contains "curl method PUT" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "PUT"
}

test_header_flag() {
    run_script -H "X-Test: yes" -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_contains "header passed" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "X-Test: yes"
}

test_multiple_headers() {
    run_script -H "X-A: 1" -H "X-B: 2" -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_contains "header 1" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "X-A: 1"
    assert_contains "header 2" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "X-B: 2"
}

test_data_flag_implies_post() {
    run_script -d '{"k":"v"}' -n 1 https://example.com
    assert_rc "exit 0" 0
    assert_contains "data passed" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" '{"k":"v"}'
    assert_contains "method POST inferred" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "POST"
}

test_warmup_runs_excluded_from_log() {
    run_script -w 2 -n 3 https://example.com
    assert_rc "exit 0" 0
    # Log file should only contain 3 timings, not 5 (warmup excluded)
    local line_count
    line_count=$(grep -c . "$TEST_DIR/curl-timing.txt" 2>/dev/null | tr -d ' ')
    assert_eq "log has 3 lines (warmup excluded)" "$line_count" "3"
    # curl was invoked 5 times total (2 warmup + 3 timed)
    local curl_count
    curl_count=$(grep -c '^curl ' "$TEST_DIR/curl.log" 2>/dev/null | tr -d ' ')
    assert_eq "curl called 5 times (warmup + timed)" "$curl_count" "5"
}

test_multiple_urls() {
    run_script -n 1 https://example.com https://example.org/path
    assert_rc "exit 0" 0
    assert_contains "first URL" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "https://example.com"
    assert_contains "second URL" "$(cat "$TEST_DIR/curl.log" 2>/dev/null)" "https://example.org/path"
    assert_file_exists "log file 1 exists" "$TEST_DIR/curl-timing-1.txt"
    assert_file_exists "log file 2 exists" "$TEST_DIR/curl-timing-2.txt"
}

test_quiet_suppresses_per_request() {
    run_script -q -n 3 https://example.com
    assert_rc "exit 0" 0
    # With -q, per-request lines like "(1/3)" should not appear
    local stdout
    stdout="$(cat "$TEST_DIR/stdout")"
    assert_not_contains "no per-request line" "$stdout" "(1/3)"
    # But summary (Count:) should still appear
    assert_contains "summary still printed" "$stdout" "Count:"
}

test_stats_summary_present() {
    run_script -n 3 https://example.com
    assert_rc "exit 0" 0
    assert_stdout_contains "Count:" "Count:"
    assert_stdout_contains "Average:" "Average:"
    assert_stdout_contains "Range:" "Range:"
}

# --- run ---

run_tests "$@"
