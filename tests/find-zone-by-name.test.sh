#!/bin/bash
# find-zone-by-name.test.sh - Tests for find-zone-by-name
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../find-zone-by-name"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }

# --- shims ---

write_shims() {
    # curl shim: return a single-page response with zone-target matching "stg-xxxx-example-com"
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/curl.args"
# Simulate HTTP response with headers and body
cat <<'EOF'
HTTP/2 200
content-type: application/json
sfdc-pagination-result-count: 2
sfdc-pagination-total-count: 2

{"data":[{"id":"zone1","name":"example1.cc-ecdn.net"},{"id":"zone-target","name":"stg-xxxx-example-com.cc-ecdn.net"}]}
EOF
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # jq shim: use real jq, just log invocation
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/jq.args"
# Find jq outside of SHIM_DIR
real_jq=$(PATH="${PATH#*:}" command -v jq)
exec "$real_jq" "$@"
SHIM
    chmod +x "$SHIM_DIR/jq"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has jwt option" "--jwt"
}

test_missing_jwt() {
    run_script -s "kv7kzm78" -r "xxxx" -i "stg" -t "example.com"
    assert_rc "missing jwt" 2
    assert_stderr_contains "missing jwt error" "jwt is required"
}

test_missing_shortcode() {
    run_script -j "eyJ.test.token" -r "xxxx" -i "stg" -t "example.com"
    assert_rc "missing shortcode" 2
    assert_stderr_contains "missing shortcode error" "shortcode is required"
}

test_missing_realm() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -i "stg" -t "example.com"
    assert_rc "missing realm" 2
    assert_stderr_contains "missing realm error" "realm is required"
}

test_missing_instance() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -r "xxxx" -t "example.com"
    assert_rc "missing instance" 2
    assert_stderr_contains "missing instance error" "instance is required"
}

test_missing_name() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -r "xxxx" -i "stg"
    assert_rc "missing name" 2
    assert_stderr_contains "missing name error" "target is required"
}

test_invalid_option() {
    run_script --invalid
    assert_rc "invalid option" 2
    assert_stderr_contains "invalid option error" "Unknown argument"
}

test_find_zone_happy_path() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -r "xxxx" -i "stg" -t "stg-xxxx-example-com"
    assert_rc "finds zone" 0
    assert_stdout_contains "outputs zone" "zone-target"
    assert_stdout_contains "outputs name" "stg-xxxx-example-com.cc-ecdn.net"
}

test_url_construction() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -r "abcd" -i "prd" -t "stg-xxxx-example-com"
    assert_rc "url construction" 0
    local args
    args="$(get_curl_args)"
    assert_contains "correct tenant" "$args" "f_ecom_abcd_prd"
    assert_contains "correct path" "$args" "/cdn/zones/v1/organizations/f_ecom_abcd_prd/zones/info"
    assert_contains "correct hostname" "$args" "kv7kzm78.api.commercecloud.salesforce.com"
}

test_curl_options() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -r "xxxx" -i "stg" -t "stg-xxxx-example-com"
    assert_rc "curl options" 0
    local args
    args="$(get_curl_args)"
    assert_contains "uses -fSsiL" "$args" "-fSsiL"
    assert_contains "uses GET" "$args" "-X"
    assert_contains "GET method" "$args" "GET"
    assert_contains "user agent" "$args" "User-Agent: sfcc-getzone"
    assert_contains "auth header" "$args" "Authorization: Bearer eyJ.test.token"
}

test_target_long_form() {
    run_script -j "eyJ.test.token" -s "kv7kzm78" -r "xxxx" -i "stg" --target "stg-xxxx-example-com"
    assert_rc "target long form" 0
    assert_stdout_contains "target works" "stg-xxxx-example-com.cc-ecdn.net"
}

test_token_alias() {
    run_script --token "eyJ.test.token" -s "kv7kzm78" -r "xxxx" -i "stg" -t "stg-xxxx-example-com"
    assert_rc "token alias" 0
    local args
    args="$(get_curl_args)"
    assert_contains "token works" "$args" "Bearer eyJ.test.token"
}

# --- run ---

run_tests "$@"
