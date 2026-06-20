#!/bin/bash
# verify-p12.test.sh - Tests for verify-p12
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../verify-p12"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }
get_openssl_input() { cat "$TEST_DIR/openssl.input" 2>/dev/null; }

assert_curl_contains() {
    local label="$1"
    local needle="$2"
    assert_contains "$label" "$(get_curl_args)" "$needle"
}

assert_curl_not_contains() {
    local label="$1"
    local needle="$2"
    assert_not_contains "$label" "$(get_curl_args)" "$needle"
}

# --- shims ---

write_shims() {
    # curl shim: log all args, return mock HTTP response
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
cat <<'RESPONSE'
HTTP/1.1 200 OK
Content-Type: text/html

<html><body>
<a href="/on/demandware.servlet/webdav/Sites/Cartridges/int_example/">int_example/</a>
<a href="/on/demandware.servlet/webdav/Sites/Cartridges/app_storefront/">app_storefront/</a>
</body></html>
RESPONSE
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # openssl shim: log stdin, output deterministic base64 for "user:pass"
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
cat > "$TEST_DIR/openssl.input"
# base64 of "testuser:testpass" is "dGVzdHVzZXI6dGVzdHBhc3M="
printf '%s' "dGVzdHVzZXI6dGVzdHBhc3M="
exit 0
SHIM
    chmod +x "$SHIM_DIR/openssl"

    # Create mock p12 file
    echo "mock-p12-content" > "$TEST_DIR/test.p12"
}

# --- test cases: help and arg validation ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has PRECONDITIONS" "PRECONDITIONS"
    assert_stdout_contains "help has CAVEATS" "CAVEATS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help has SEE ALSO" "SEE ALSO"
    assert_stdout_contains "help mentions Bearer" "Bearer"
    assert_stdout_contains "help mentions Basic" "Basic"
    assert_stdout_contains "help documents --basic" "--basic"
    assert_stdout_contains "help references propfind-p12" "propfind-p12"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_missing_args() {
    run_script
    assert_rc "no args exits 2" 2
    assert_stderr_contains "error message" "[ERR][verify-p12] hostname is required"
    assert_stderr_contains "points at help" "Run \`verify-p12 -h\`"
}

test_one_arg() {
    run_script "example.com"
    assert_rc "one arg exits 2" 2
    assert_stderr_contains "error message" "[ERR][verify-p12] credential is required"
}

# --- test cases: Bearer auth (default) ---

test_bearer_auth_basic() {
    run_script "dev01-realm-customer.demandware.net" "test-token-123"
    assert_rc "bearer auth exits 0" 0
    assert_curl_contains "silent flag" "-si"
    assert_curl_contains "GET method" "-X"
    assert_curl_contains "GET value" "GET"
    assert_curl_contains "url arg" "--url"
    assert_curl_contains "correct url" "https://dev01-realm-customer.demandware.net/on/demandware.servlet/webdav/Sites/Cartridges"
    assert_curl_contains "auth header flag" "-H"
    assert_curl_contains "bearer token" "Authorization: Bearer test-token-123"
    assert_curl_not_contains "no basic auth" "Authorization: Basic"
    assert_curl_not_contains "no -k flag" "-k"
    assert_curl_not_contains "no cert-type" "--cert-type"
    assert_stderr_contains "prints GET url" "GET https://dev01-realm-customer.demandware.net/on/demandware.servlet/webdav/Sites/Cartridges"
}

test_bearer_with_p12_default_file() {
    export USER="testuser"
    touch "$TEST_DIR/testuser-example.com.p12"
    cd "$TEST_DIR" || exit 1
    run_script "example.com" "token456" "p12pass"
    assert_rc "p12 default exits 0" 0
    assert_curl_contains "insecure flag" "-k"
    assert_curl_contains "cert-type" "--cert-type"
    assert_curl_contains "p12 type" "p12"
    assert_curl_contains "cert flag" "--cert"
    assert_curl_contains "default p12 file" "testuser-example.com.p12:p12pass"
}

test_bearer_with_p12_custom_file() {
    run_script "example.com" "token789" "mypass" "$TEST_DIR/test.p12"
    assert_rc "p12 custom exits 0" 0
    assert_curl_contains "cert with custom path" "$TEST_DIR/test.p12:mypass"
}

test_bearer_empty_p12_password_skips_mtls() {
    run_script "example.com" "token123" ""
    assert_rc "empty p12pass exits 0" 0
    assert_curl_not_contains "no -k with empty pass" "-k"
    assert_curl_not_contains "no cert-type with empty pass" "--cert-type"
}

# --- test cases: Basic auth (--basic flag) ---

test_basic_auth_no_p12() {
    run_script --basic "example.com" "testuser:testpass"
    assert_rc "basic auth exits 0" 0
    assert_stderr_contains "shows request URL" "GET https://example.com/on/demandware.servlet/webdav/Sites/Cartridges"
    assert_stdout_contains "shows HTTP status" "HTTP/1.1 200 OK"
    assert_curl_contains "curl has -si" "-si"
    assert_curl_contains "curl has GET" "-X"
    assert_curl_contains "curl has URL" "https://example.com/on/demandware.servlet/webdav/Sites/Cartridges"
    assert_curl_contains "basic auth header" "Authorization: Basic dGVzdHVzZXI6dGVzdHBhc3M="
    assert_curl_not_contains "no bearer" "Authorization: Bearer"
    assert_curl_not_contains "no p12 args" "--cert-type"
    assert_eq "openssl receives credentials" "$(get_openssl_input)" "testuser:testpass"
}

test_basic_auth_with_p12_default_file() {
    export USER="jdoe"
    touch "$TEST_DIR/jdoe-example.com.p12"
    cd "$TEST_DIR" || exit 1
    run_script --basic "example.com" "testuser:testpass" "p12secret"
    assert_rc "with p12 exits 0" 0
    assert_curl_contains "curl has -k" "-k"
    assert_curl_contains "curl has --cert-type" "--cert-type"
    assert_curl_contains "curl has p12" "p12"
    assert_curl_contains "curl has --cert" "--cert"
    assert_curl_contains "curl has default p12 file" "jdoe-example.com.p12:p12secret"
}

test_basic_auth_with_p12_custom_file() {
    run_script --basic "example.com" "testuser:testpass" "p12secret" "$TEST_DIR/test.p12"
    assert_rc "with custom p12 exits 0" 0
    assert_curl_contains "curl has custom p12 file" "$TEST_DIR/test.p12:p12secret"
}

test_basic_auth_special_chars_in_password() {
    run_script --basic "example.com" "user@domain:p@ss:w0rd!"
    assert_rc "special chars exits 0" 0
    # Colons in the password are fine -- openssl gets the full user:pass string untouched
    assert_eq "openssl receives special chars" "$(get_openssl_input)" "user@domain:p@ss:w0rd!"
}

test_basic_auth_missing_creds() {
    run_script --basic "example.com"
    assert_rc "basic without creds exits 2" 2
    assert_stderr_contains "error message" "credential is required"
}

test_basic_auth_empty_p12_password_skips_mtls() {
    export USER="jdoe"
    run_script --basic "example.com" "testuser:testpass" ""
    assert_rc "empty p12 password exits 0" 0
    assert_curl_not_contains "no --cert-type" "--cert-type"
}

# --- test cases: output parsing and edge cases ---

test_output_parsing() {
    run_script "example.com" "token-abc"
    assert_rc "output exits 0" 0
    assert_stdout_contains "http status line" "HTTP/1.1 200 OK"
    assert_stdout_contains "first cartridge" "/webdav/Sites/Cartridges/int_example/"
    assert_stdout_contains "second cartridge" "/webdav/Sites/Cartridges/app_storefront/"
    assert_stdout_not_contains "no html tags" "<a href="
    assert_stdout_not_contains "no closing tags" "</a>"
}

test_curl_failure() {
    # curl failure doesn't propagate through pipeline without pipefail
    # The script exits 0 because sed (last in pipeline) succeeds
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
echo "curl: (6) Could not resolve host" >&2
exit 6
SHIM
    chmod +x "$SHIM_DIR/curl"
    run_script "badhost.example" "token"
    assert_rc "curl failure exits 0" 0
    assert_stderr_contains "curl error to stderr" "curl: (6) Could not resolve host"
}

test_hostname_with_subdomain() {
    run_script "sub.example.com" "token-xyz"
    assert_rc "subdomain exits 0" 0
    assert_stderr_contains "subdomain in URL" "GET https://sub.example.com/on/demandware.servlet/webdav/Sites/Cartridges"
}

# --- run ---

run_tests "$@"
