#!/bin/bash
# spf-find-ip.test.sh - Tests for spf-find-ip
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../spf-find-ip"

# --- helpers ---

get_dig_log() { cat "$TEST_DIR/dig.log" 2>/dev/null; }

# --- shims ---

write_shims() {
    # dig shim: returns canned SPF records based on domain
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/dig.log"
printf 'dig' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

# Extract domain from args (last non-option arg that's not TXT or a flag)
domain=""
for a in "$@"; do
    case "$a" in
        @*|+*|TXT) ;;
        *) domain="$a" ;;
    esac
done

case "$domain" in
    root.example)
        # Root domain with direct IPs (no includes to search)
        printf '%s\n' '"v=spf1 ip4:203.0.113.100 ip4:203.0.113.101/32 -all"'
        ;;
    example.com)
        # Root domain has no direct IPs, only includes
        printf '%s\n' '"v=spf1 include:spf.example.com -all"'
        ;;
    spf.example.com)
        # First level include has some IPs
        printf '%s\n' '"v=spf1 ip4:203.0.113.1 ip4:203.0.113.2/32 ip4:198.51.100.10 include:deep.example.com -all"'
        ;;
    deep.example.com)
        # Second level include has different IP
        printf '%s\n' '"v=spf1 ip4:192.0.2.50 -all"'
        ;;
    toplevel.example)
        printf '%s\n' '"v=spf1 include:nested1.example include:nested2.example -all"'
        ;;
    nested1.example)
        printf '%s\n' '"v=spf1 ip4:10.0.0.1 -all"'
        ;;
    nested2.example)
        printf '%s\n' '"v=spf1 ip4:10.0.0.2 include:nested3.example -all"'
        ;;
    nested3.example)
        printf '%s\n' '"v=spf1 ip4:10.0.0.99 -all"'
        ;;
    nospf.example)
        # No SPF record
        ;;
    badinclude.example)
        printf '%s\n' '"v=spf1 include:missing.example -all"'
        ;;
    missing.example)
        # No SPF record
        ;;
    notfound.example)
        printf '%s\n' '"v=spf1 ip4:1.2.3.4 include:sub.notfound.example -all"'
        ;;
    sub.notfound.example)
        printf '%s\n' '"v=spf1 ip4:5.6.7.8 -all"'
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_ip_found_at_root() {
    run_script example.com 203.0.113.1
    assert_rc "ip at root exits 0" 0
    assert_stdout_contains "finds IP in root" "IP 203.0.113.1 is included by: spf.example.com"
    assert_contains "dig called" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT example.com"
}

test_ip_found_with_slash32() {
    run_script example.com 203.0.113.2
    assert_rc "ip with /32 exits 0" 0
    assert_stdout_contains "matches /32 suffix" "IP 203.0.113.2 is included by: spf.example.com"
}

test_ip_found_in_include() {
    run_script example.com 198.51.100.10
    assert_rc "ip in include exits 0" 0
    assert_stdout_contains "finds IP in include" "IP 198.51.100.10 is included by: spf.example.com"
    assert_contains "dig called for root" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT example.com"
    assert_contains "dig called for include" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT spf.example.com"
}

test_ip_found_deep_in_chain() {
    run_script example.com 192.0.2.50
    assert_rc "deep chain exits 0" 0
    assert_stdout_contains "finds IP deep" "IP 192.0.2.50 is included by: deep.example.com"
    assert_contains "dig root" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT example.com"
    assert_contains "dig first include" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT spf.example.com"
    assert_contains "dig second include" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT deep.example.com"
}

test_multiple_includes_second_match() {
    run_script toplevel.example 10.0.0.2
    assert_rc "second include exits 0" 0
    assert_stdout_contains "finds in second include" "IP 10.0.0.2 is included by: nested2.example"
}

test_nested_include_chain() {
    run_script toplevel.example 10.0.0.99
    assert_rc "nested chain exits 0" 0
    assert_stdout_contains "finds in deeply nested" "IP 10.0.0.99 is included by: nested3.example"
    assert_contains "queries nested3" "$(get_dig_log)" "dig @8.8.8.8 +tcp +short TXT nested3.example"
}

test_ip_not_found() {
    run_script example.com 99.99.99.99
    assert_rc "not found exits 0" 0
    assert_stdout_contains "reports not found" "IP 99.99.99.99 not found in example.com's SPF records"
}

test_no_spf_record() {
    run_script nospf.example 1.2.3.4
    assert_rc "no spf exits 0" 0
    assert_stderr_contains "reports no spf" "No SPF record found for nospf.example"
}

test_include_has_no_spf() {
    run_script badinclude.example 1.2.3.4
    assert_rc "bad include exits 0" 0
    assert_stdout_contains "reports missing include" "No SPF record found for included domain missing.example"
}

test_ip_not_in_includes() {
    run_script notfound.example 99.99.99.99
    assert_rc "not in includes exits 0" 0
    assert_stdout_contains "checked includes" "IP 99.99.99.99 not found in notfound.example's SPF records"
}

test_colorized_output() {
    run_script example.com 203.0.113.1
    assert_rc "color exits 0" 0
    assert_stdout_contains "highlights IP in output" "203.0.113.1"
}

test_stderr_shows_lookups() {
    run_script example.com 198.51.100.10
    assert_rc "lookups exit 0" 0
    assert_stderr_contains "shows root lookup" "SPF record for example.com:"
    assert_stderr_contains "shows include lookup" "SPF record for spf.example.com:"
}

test_spf_record_echoed_to_stderr() {
    run_script example.com 203.0.113.1
    assert_rc "echo exits 0" 0
    assert_stderr_contains "echoes spf content" "v=spf1 ip4:203.0.113.1 ip4:203.0.113.2/32"
}

test_missing_domain_argument() {
    run_script
    assert_rc "missing domain exits 2" 2
    assert_stderr_contains "domain required error" "domain is required"
    assert_stderr_contains "error points to help" "Run \`spf-find-ip -h\`"
}

test_missing_ip_argument() {
    run_script example.com
    assert_rc "missing ip exits 2" 2
    assert_stderr_contains "ip required error" "ip is required"
    assert_stderr_contains "error points to help" "Run \`spf-find-ip -h\`"
}

test_dig_not_found() {
    # Remove dig shim and restrict PATH so dig isn't found
    /bin/rm -f "$SHIM_DIR/dig"
    env PATH="$SHIM_DIR" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" example.com 1.2.3.4 >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "dig missing exits 3" 3
    assert_stderr_contains "dig error" "dig is required"
}

# --- run ---

run_tests "$@"
