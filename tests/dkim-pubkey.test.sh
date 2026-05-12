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

# Extract query hostname (last non-option arg). Skip dig flags (+short) and
# server overrides (@host)
query=""
for a in "$@"; do
    case "$a" in +*|@*) ;; *) query="$a" ;; esac
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
    bad-b64._domainkey.*)
        # Contains '@' — not in base64 alphabet, fails regex stage
        printf '%s\n' '"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQE@AAOCAQ8AMIIBCgKCAQEA"'
        ;;
    bad-key._domainkey.*)
        # Valid base64 but trivially short — passes regex, fails openssl-shim stage
        printf '%s\n' '"v=DKIM1; k=rsa; p=AAAA"'
        ;;
    cname._domainkey.*)
        # CNAME-fronted record: dig returns the CNAME target on line 1
        # and the resolved TXT body on line 2
        printf '%s\n' 'cname.target.example.net.'
        printf '%s\n' '"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAcname1234567890abcdefghijklmnopqrstuvwxyz"'
        ;;
    *)
        # Standard single-line response
        printf '%s\n' '"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1234567890abcdefghijklmnopqrstuvwxyz"'
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"

    # openssl shim: only used by --validate. Reads DER bytes on stdin and emits
    # pkey -text-style output. Treats stdin shorter than 32 bytes as "not a real key"
    # so the bad-key selector above can drive a structural-failure case
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
# We only stub the `pkey -pubin -inform DER -text -noout` invocation
input="$(cat)"
if [ "${#input}" -lt 32 ]; then
    exit 1
fi
echo "Public-Key: (2048 bit)"
echo "Modulus:"
echo "    00:de:ad:be:ef"
echo "Exponent: 65537 (0x10001)"
SHIM
    chmod +x "$SHIM_DIR/openssl"
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

test_validate_happy_path() {
    run_script --validate "test" "example.com"
    assert_rc "validate happy path exits 0" 0
    assert_stdout_contains "key still on stdout" "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1234567890abcdefghijklmnopqrstuvwxyz"
    assert_stderr_contains "info line on success" "[INF][dkim-pubkey] Key valid"
    # Diagnostic comes AFTER the key on both success and failure (consistent
    # ordering); [INF] line preceded by a blank so the key on stdout doesn't
    # visually run into it
    local before_inf
    before_inf="$(get_stderr | grep -B1 '\[INF\]' | head -1)"
    assert_eq "blank line precedes [INF]" "$before_inf" ""
}

test_validate_short_flag() {
    run_script -V "test" "example.com"
    assert_rc "-V short flag exits 0" 0
    assert_stderr_contains "-V triggers validation" "[INF][dkim-pubkey] Key valid"
}

test_validate_bad_base64() {
    run_script --validate "bad-b64" "example.com"
    assert_rc "bad base64 exits 5" 5
    assert_stderr_contains "regex-stage error" "Validation failed: key is not valid base64"
    assert_stdout_contains "key still printed on failure" "MIIBIjANBgkqhkiG9w0BAQE@AAOCAQ8AMIIBCgKCAQEA"
    # [ERR] line is preceded by a blank line on stderr so the key on stdout
    # doesn't visually run into the diagnostic
    local before_err
    before_err="$(get_stderr | grep -B1 '\[ERR\]' | head -1)"
    assert_eq "blank line precedes [ERR]" "$before_err" ""
}

test_validate_bad_key_bytes() {
    run_script --validate "bad-key" "example.com"
    assert_rc "bad key bytes exits 5" 5
    assert_stderr_contains "openssl-stage error" "Validation failed: key bytes do not parse"
    assert_stdout_contains "key still printed on failure" "AAAA"
}

test_validate_openssl_missing() {
    # Build a minimal PATH containing the shim dir plus symlinks to the POSIX
    # tools the script reaches before the openssl check (sed, grep). Crucially
    # excludes any path containing a real openssl, so `command -v openssl` fails
    rm -f "$SHIM_DIR/openssl"
    local minpath="$TEST_DIR/minpath"
    mkdir -p "$minpath"
    local tool
    local tool_path
    for tool in sed grep; do
        tool_path="$(PATH="/usr/bin:/bin:/usr/local/bin" command -v "$tool")"
        ln -sf "$tool_path" "$minpath/$tool"
    done
    env PATH="$SHIM_DIR:$minpath" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" --validate "test" "example.com" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "openssl missing exits 3" 3
    assert_stderr_contains "openssl error" "openssl is required"
}

test_cname_fronted_extraction() {
    run_script "cname" "example.com"
    assert_rc "cname-fronted exits 0" 0
    assert_stderr_contains "stderr shows cname target" "cname.target.example.net."
    local stdout
    stdout="$(get_stdout)"
    assert_contains "stdout has key" "$stdout" "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAcname1234567890abcdefghijklmnopqrstuvwxyz"
    assert_not_contains "stdout omits cname target" "$stdout" "cname.target.example.net"
    # Stdout must be a single line (CNAME target line was filtered out)
    local stdout_lines
    stdout_lines="$(get_stdout | wc -l | tr -d ' ')"
    assert_eq "stdout is one line" "$stdout_lines" "1"
}

test_server_long_flag() {
    run_script --server "8.8.8.8" "test" "example.com"
    assert_rc "--server long flag exits 0" 0
    local dig_log
    dig_log="$(cat "$TEST_DIR/dig.log")"
    assert_contains "dig invoked with @server" "$dig_log" "@8.8.8.8"
    assert_stderr_contains "stderr shows @server" "@8.8.8.8 +short TXT"
}

test_server_short_flag() {
    run_script -s "1.1.1.1" "test" "example.com"
    assert_rc "-s short flag exits 0" 0
    local dig_log
    dig_log="$(cat "$TEST_DIR/dig.log")"
    assert_contains "dig invoked with @server (short)" "$dig_log" "@1.1.1.1"
}

test_server_at_shorthand() {
    run_script "test" "example.com" "@9.9.9.9"
    assert_rc "@host shorthand exits 0" 0
    local dig_log
    dig_log="$(cat "$TEST_DIR/dig.log")"
    assert_contains "dig invoked with @server (@-form)" "$dig_log" "@9.9.9.9"
}

test_server_equals_form() {
    run_script "--server=8.8.4.4" "test" "example.com"
    assert_rc "--server=val exits 0" 0
    local dig_log
    dig_log="$(cat "$TEST_DIR/dig.log")"
    assert_contains "dig invoked with @server (= form)" "$dig_log" "@8.8.4.4"
}

test_server_missing_value() {
    run_script --server "test" "example.com"
    # --server consumes "test" as the value, leaving only "example.com" — domain missing
    assert_rc "--server consumes next arg, then domain missing" 2
    assert_stderr_contains "domain missing error" "domain is required"
}

test_server_empty_after_equals() {
    run_script "--server=" "test" "example.com"
    assert_rc "--server= empty value exits 2" 2
    assert_stderr_contains "empty server value error" "--server requires a value"
}

test_server_at_empty() {
    run_script "test" "example.com" "@"
    assert_rc "bare @ exits 2" 2
    assert_stderr_contains "bare @ error" "@<host> requires a value"
}

test_server_duplicate() {
    run_script -s "8.8.8.8" "test" "example.com" "@1.1.1.1"
    assert_rc "duplicate --server/@host exits 2" 2
    assert_stderr_contains "duplicate server error" "Multiple --server not allowed"
}

test_server_default_no_at() {
    run_script "test" "example.com"
    assert_rc "no --server exits 0" 0
    local dig_log
    dig_log="$(cat "$TEST_DIR/dig.log")"
    assert_not_contains "no @server in dig args by default" "$dig_log" "@"
    assert_stderr_not_contains "no @ in stderr command line" "@"
}

test_no_validate_skips_openssl_check() {
    # Without --validate, missing openssl must not matter
    rm -f "$SHIM_DIR/openssl"
    run_script "test" "example.com"
    assert_rc "no --validate ignores openssl" 0
    assert_stderr_not_contains "no openssl error" "openssl is required"
}

# --- run ---

run_tests "$@"
