#!/bin/bash
# dkim-pubkey.test.sh - Tests for dkim-pubkey
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../dkim-pubkey"

# --- shims ---

write_shims() {
    # dig shim: returns DNS TXT response with p= field
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/dig.log"
printf 'dig' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

# Extract query hostname (last non-option arg)
query=""
for a in "$@"; do
    case "$a" in +*) ;; *) query="$a" ;; esac
done

case "$query" in
    empty._domainkey.*)
        # Empty response case
        ;;
    empty-p._domainkey.*)
        # Record exists but p= value is missing
        printf '%s\n' '"v=DKIM1; k=rsa; p="'
        ;;
    multiline._domainkey.*)
        # Multi-line response with quotes
        printf '%s\n' '"v=DKIM1; k=rsa; " "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC3QEKyU1fSma0axspqYK5iAj+54lsAg"'
        ;;
    *)
        # Standard single-line response
        printf '%s\n' '"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1234567890abcdefghijklmnopqrstuvwxyz"'
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
    assert_stdout_contains "help has EXAMPLE" "EXAMPLE"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_no_args() {
    run_script
    assert_rc "no args exits 2" 2
    assert_stderr_contains "no args error" "selector is required"
}

test_missing_domain() {
    run_script "dkim-selector"
    assert_rc "missing domain exits 2" 2
    assert_stderr_contains "missing domain error" "domain is required"
}

test_basic_query() {
    run_script "dkim-prd" "gmail.com"
    assert_rc "basic query exits 0" 0
    assert_stderr_contains "shows dig command" "\$ dig +short TXT \"dkim-prd._domainkey.gmail.com\""
    assert_stderr_contains "shows DNS response" "v=DKIM1"
    assert_stdout_contains "outputs p= value" "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1234567890abcdefghijklmnopqrstuvwxyz"
}

test_dig_invocation() {
    run_script "selector1" "example.com"
    assert_rc "dig invocation exits 0" 0
    local dig_log
    dig_log="$(cat "$TEST_DIR/dig.log")"
    assert_contains "dig called with +short" "$dig_log" "+short"
    assert_contains "dig called with TXT" "$dig_log" "TXT"
    assert_contains "dig called with hostname" "$dig_log" "selector1._domainkey.example.com"
}

test_empty_dns_response() {
    run_script "empty" "example.com"
    assert_rc "empty response exits 1" 1
    assert_stderr_contains "empty response error" "[ERR][dkim-pubkey] DNS response empty"
}

test_empty_p_value() {
    run_script "empty-p" "example.com"
    assert_rc "empty p= exits 4 (domain-specific)" 4
    assert_stderr_contains "empty p error" "Record found but key is empty"
}

test_dig_missing() {
    rm -f "$SHIM_DIR/dig"
    env PATH="$SHIM_DIR" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" "selector" "example.com" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "dig missing exits 3" 3
    assert_stderr_contains "dig error" "dig is required"
}

test_multiline_response() {
    run_script "multiline" "example.com"
    assert_rc "multiline exits 0" 0
    assert_stderr_contains "shows multiline response" "v=DKIM1"
    assert_stdout_contains "extracts p= from multiline" "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC3QEKyU1fSma0axspqYK5iAj+54lsAg"
}

test_stderr_blank_line() {
    run_script "dkim-prd" "gmail.com"
    assert_rc "stderr blank line exits 0" 0
    local stderr_lines
    stderr_lines="$(get_stderr | wc -l | tr -d ' ')"
    # Should have: dig command line + DNS response + blank line = at least 3 lines
    if [ "$stderr_lines" -ge 3 ]; then
        _ok "stderr has blank line separator"
    else
        _fail "stderr missing blank line separator"
    fi
}

test_dns_hostname_construction() {
    run_script "s1" "domain.example"
    assert_rc "hostname construction exits 0" 0
    assert_stderr_contains "constructs _domainkey hostname" "s1._domainkey.domain.example"
}

test_p_value_extraction() {
    run_script "test" "example.com"
    assert_rc "p value extraction exits 0" 0
    local stdout
    stdout="$(get_stdout)"
    # Should not contain v=DKIM1, quotes, or p=
    assert_not_contains "strips v=DKIM1" "$stdout" "v=DKIM1"
    assert_not_contains "strips quotes" "$stdout" '"'
    assert_not_contains "strips p=" "$stdout" "p="
}

# --- run ---

run_tests "$@"
