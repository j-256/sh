#!/bin/bash
# propfind-p12.test.sh - Tests for propfind-p12
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../propfind-p12"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }

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

    # Create dummy cert files referenced by the script
    export USER="testuser"
    : > "$TEST_DIR/testuser-dev01-web-example.demandware.net.p12"
    : > "$TEST_DIR/dev01-web-example.demandware.net_01.crt"
    # Also create files for the alternate hostname used in test_url_construction
    : > "$TEST_DIR/testuser-staging.example.com.p12"
    : > "$TEST_DIR/staging.example.com_01.crt"
    # Ensure no token env leaks in from the parent shell
    unset SFCC_TOKEN
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has PRECONDITIONS" "PRECONDITIONS"
    assert_stdout_contains "help mentions generate-p12" "generate-p12"
}

test_help_short() {
    run_script -h
    assert_rc "short help exits 0" 0
    assert_stdout_contains "short help has NAME" "NAME"
}

test_basic_propfind() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "basic propfind exits 0" 0
    assert_contains "has PROPFIND method" "$(get_curl_args)" "-X"
    assert_contains "has PROPFIND method value" "$(get_curl_args)" "PROPFIND"
    assert_contains "has URL" "$(get_curl_args)" "https://dev01-web-example.demandware.net/on/demandware.servlet/webdav/Sites/Cartridges/version1"
}

test_cert_type_p12() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "cert type exits 0" 0
    assert_contains "has cert-type" "$(get_curl_args)" "--cert-type"
    assert_contains "cert-type is p12" "$(get_curl_args)" "p12"
}

test_cert_with_password() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "cert exits 0" 0
    assert_contains "has --cert" "$(get_curl_args)" "--cert"
    assert_contains "cert path with password" "$(get_curl_args)" "testuser-dev01-web-example.demandware.net.p12:p12pass"
}

test_cacert() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "cacert exits 0" 0
    assert_contains "has --cacert" "$(get_curl_args)" "--cacert"
    assert_contains "cacert path" "$(get_curl_args)" "dev01-web-example.demandware.net_01.crt"
}

test_bearer_token() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "token exits 0" 0
    assert_contains "has Authorization header" "$(get_curl_args)" "Authorization: Bearer mytoken123"
}

test_token_long_flag() {
    cd "$TEST_DIR" || exit 1
    run_script --token "longflagtoken" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "long --token exits 0" 0
    assert_contains "long --token in header" "$(get_curl_args)" "Authorization: Bearer longflagtoken"
}

test_token_equals_form() {
    cd "$TEST_DIR" || exit 1
    run_script --token=eqtoken "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "--token= exits 0" 0
    assert_contains "--token= in header" "$(get_curl_args)" "Authorization: Bearer eqtoken"
}

test_token_from_env() {
    cd "$TEST_DIR" || exit 1
    SFCC_TOKEN="envtoken456" run_script "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "env token exits 0" 0
    assert_contains "env token in header" "$(get_curl_args)" "Authorization: Bearer envtoken456"
}

test_flag_token_beats_env() {
    cd "$TEST_DIR" || exit 1
    SFCC_TOKEN="envtoken" run_script -t "flagtoken" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "flag-over-env exits 0" 0
    assert_contains "flag token wins" "$(get_curl_args)" "Authorization: Bearer flagtoken"
}

test_depth_header() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "depth exits 0" 0
    assert_contains "has Depth header" "$(get_curl_args)" "Depth: 1"
}

test_xml_body() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "xml exits 0" 0
    assert_contains "has data-raw" "$(get_curl_args)" "--data-raw"
    assert_contains "xml propfind" "$(get_curl_args)" '<?xml version="1.0" encoding="utf-8" ?><D:propfind xmlns:D="DAV:"><D:allprop/></D:propfind>'
}

test_url_construction() {
    cd "$TEST_DIR" || exit 1
    run_script -t "token456" "staging.example.com" "version2" "pass123"
    assert_rc "url construction exits 0" 0
    assert_contains "correct URL" "$(get_curl_args)" "https://staging.example.com/on/demandware.servlet/webdav/Sites/Cartridges/version2"
}

test_different_user() {
    cd "$TEST_DIR" || exit 1
    export USER="anotheruser"
    : > "$TEST_DIR/anotheruser-dev01-web-example.demandware.net.p12"
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "different user exits 0" 0
    assert_contains "uses different user in cert path" "$(get_curl_args)" "anotheruser-dev01-web-example.demandware.net.p12:p12pass"
}

test_missing_hostname() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123"
    assert_rc "missing hostname exits 2" 2
    assert_err_contains "error mentions hostname" "hostname is required"
    assert_err_contains "error points to help" "Run \`propfind-p12 -h\`"
}

test_missing_code_version() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net"
    assert_rc "missing code_version exits 2" 2
    assert_err_contains "error mentions code_version" "code_version is required"
}

test_missing_p12_password() {
    cd "$TEST_DIR" || exit 1
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1"
    assert_rc "missing p12_password exits 2" 2
    assert_err_contains "error mentions p12_password" "p12_password is required"
}

test_missing_token() {
    cd "$TEST_DIR" || exit 1
    run_script "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "missing token exits 2" 2
    assert_err_contains "error mentions token" "token is required"
    assert_err_contains "error mentions SFCC_TOKEN" "SFCC_TOKEN"
}

test_token_flag_without_value() {
    cd "$TEST_DIR" || exit 1
    run_script -t
    assert_rc "-t without value exits 2" 2
    assert_err_contains "-t requires value error" "requires a value"
}

test_missing_p12_file() {
    cd "$TEST_DIR" || exit 1
    rm -f "$TEST_DIR/testuser-dev01-web-example.demandware.net.p12"
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "missing p12 exits 4" 4
    assert_err_contains "error mentions p12 file" "p12 file not found"
    assert_err_contains "error points at generate-p12" "generate-p12"
}

test_missing_ca_cert() {
    cd "$TEST_DIR" || exit 1
    rm -f "$TEST_DIR/dev01-web-example.demandware.net_01.crt"
    run_script -t "mytoken123" "dev01-web-example.demandware.net" "version1" "p12pass"
    assert_rc "missing CA cert exits 4" 4
    assert_err_contains "error mentions CA cert" "CA certificate file not found"
}

# --- run ---

run_tests "$@"
