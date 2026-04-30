#!/bin/bash
# client-credentials.test.sh - Tests for client-credentials
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../client-credentials"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }
get_curl_body() { cat "$TEST_DIR/curl.body" 2>/dev/null; }

# --- shims ---

write_shims() {
    # curl shim: log args and body, return fake OAuth response
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
body=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -d) body="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf '%s' "$body" > "$TEST_DIR/curl.body"
# Return JSON response
printf '{"access_token":"fake_access_123","expires_in":1800,"token_type":"Bearer","refresh_token":"fake_refresh_456","refresh_token_expires_in":2592000}\n'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # jq shim: simple JSON field extraction
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
field="$2"
input="$(cat)"
case "$field" in
    .access_token) printf '%s\n' "fake_access_123" ;;
    .expires_in) printf '%s\n' "1800" ;;
    .refresh_token) printf '%s\n' "fake_refresh_456" ;;
    .refresh_token_expires_in) printf '%s\n' "2592000" ;;
    *) printf 'null\n' ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/jq"

    # base64 shim: fake encoding
    cat > "$SHIM_DIR/base64" <<'SHIM'
#!/bin/bash
input="$(cat)"
printf 'base64:%s' "$input"
exit 0
SHIM
    chmod +x "$SHIM_DIR/base64"

    # date shim: return fixed timestamp
    cat > "$SHIM_DIR/date" <<'SHIM'
#!/bin/bash
printf '1609459200\n'
exit 0
SHIM
    chmod +x "$SHIM_DIR/date"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has description" "OAuth2 access token"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help lists curl" "curl"
    assert_stdout_contains "help lists jq" "jq"
    assert_stdout_contains "help lists base64" "base64"
    assert_stdout_contains "help lists date" "date"
    assert_stdout_contains "help mentions SLAS" "SLAS"
}

test_help_short() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_missing_client_id() {
    run_script --client-secret "secret123"
    # Pre-request validation now rejects empty client_id with exit code 2
    assert_rc "missing client-id exits 2" 2
    assert_err_contains "missing client-id error" "client_id is required"
}

test_missing_client_secret() {
    run_script --client-id "client123"
    assert_rc "missing client-secret exits 2" 2
    assert_err_contains "missing client-secret error" "client_secret is required"
}

test_invalid_argument() {
    run_script --invalid-flag
    assert_rc "invalid arg exits 1" 1
    assert_err_contains "invalid arg error" "Invalid argument: --invalid-flag"
}

test_am_endpoint_basic() {
    run_script --endpoint am --client-id "client123" --client-secret "secret456"
    assert_rc "am basic exits 0" 0
    assert_stdout_contains "stdout has token" "fake_access_123"
    assert_contains "am URL" "$(get_curl_args)" "https://account.demandware.com/dwsso/oauth2/access_token"
    assert_contains "curl POST" "$(get_curl_args)" "-X"
    assert_contains "curl POST value" "$(get_curl_args)" "POST"
    assert_contains "content-type" "$(get_curl_args)" "Content-Type: application/x-www-form-urlencoded"
    assert_contains "auth header" "$(get_curl_args)" "Authorization: Basic base64:client123:secret456"
    assert_contains "grant type" "$(get_curl_body)" "grant_type=client_credentials"
}

test_am_endpoint_with_scopes() {
    run_script --endpoint am --client-id "client123" --client-secret "secret456" --scopes "read write"
    assert_rc "am with scopes exits 0" 0
    assert_contains "body has grant" "$(get_curl_body)" "grant_type=client_credentials"
    assert_contains "body has scopes" "$(get_curl_body)" "&scope=read write"
}

test_slas_endpoint_basic() {
    run_script --endpoint slas --client-id "client123" --client-secret "secret456" --shortcode "kv7kzm78" --org-id "f_ecom_zzxy_001"
    assert_rc "slas basic exits 0" 0
    assert_stdout_contains "stdout has token" "fake_access_123"
    assert_contains "slas URL shortcode" "$(get_curl_args)" "kv7kzm78.api.commercecloud.salesforce.com"
    assert_contains "slas URL org" "$(get_curl_args)" "/organizations/f_ecom_zzxy_001/oauth2/token"
}

test_slas_missing_shortcode() {
    run_script --endpoint slas --client-id "client123" --client-secret "secret456" --org-id "f_ecom_zzxy_001"
    # Pre-request validation now rejects missing shortcode with exit code 2
    assert_rc "slas missing shortcode exits 2" 2
    assert_err_contains "missing shortcode error" "shortcode is required for slas"
}

test_slas_missing_org_id() {
    run_script --endpoint slas --client-id "client123" --client-secret "secret456" --shortcode "kv7kzm78"
    assert_rc "slas missing org_id exits 2" 2
    assert_err_contains "missing org_id error" "org_id is required for slas"
}

test_invalid_endpoint() {
    run_script --endpoint invalid --client-id "client123" --client-secret "secret456"
    assert_rc "invalid endpoint exits 1" 1
    assert_err_contains "invalid endpoint error" "Invalid endpoint type: invalid"
}

test_default_endpoint_am() {
    run_script --client-id "client123" --client-secret "secret456"
    assert_rc "default endpoint exits 0" 0
    assert_contains "default is am" "$(get_curl_args)" "account.demandware.com"
}

test_env_input_client_id() {
    J_CLIENT_ID="env_client" J_CLIENT_SECRET="env_secret" run_script --endpoint am
    assert_rc "env client-id exits 0" 0
    assert_contains "uses env client-id" "$(get_curl_args)" "base64:env_client:env_secret"
}

test_cli_overrides_env() {
    J_CLIENT_ID="env_client" J_CLIENT_SECRET="env_secret" run_script --endpoint am --client-id "cli_client" --client-secret "cli_secret"
    assert_rc "cli override exits 0" 0
    assert_contains "cli overrides env" "$(get_curl_args)" "base64:cli_client:cli_secret"
}

test_env_endpoint() {
    J_ENDPOINT="slas" J_CLIENT_ID="client123" J_CLIENT_SECRET="secret456" J_SHORTCODE="kv7kzm78" J_ORG_ID="f_ecom_zzxy_001" run_script
    assert_rc "env endpoint exits 0" 0
    assert_contains "uses env endpoint" "$(get_curl_args)" "kv7kzm78.api.commercecloud.salesforce.com"
}

test_env_print_all() {
    J_CLIENT_ID="test_client" J_ACCESS_TOKEN="old_token" run_script --env
    assert_rc "env print exits 0" 0
    assert_stdout_contains "prints input vars" "Input Environment Variables:"
    assert_stdout_contains "prints output vars" "Output Environment Variables:"
    assert_stdout_contains "prints J_CLIENT_ID" "J_CLIENT_ID: \`test_client\`"
}

test_env_print_input() {
    J_CLIENT_ID="test_client" run_script --env input
    assert_rc "env input exits 0" 0
    assert_stdout_contains "prints input" "Input Environment Variables:"
    assert_stdout_not_contains "no output" "Output Environment Variables:"
    assert_stdout_contains "shows client-id" "J_CLIENT_ID: \`test_client\`"
}

test_env_print_output() {
    run_script --env output
    assert_rc "env output exits 0" 0
    assert_stdout_contains "prints output" "Output Environment Variables:"
    assert_stdout_not_contains "no input" "Input Environment Variables:"
}

test_env_print_in_alias() {
    run_script --env in
    assert_rc "env in alias exits 0" 0
    assert_stdout_contains "in is input" "Input Environment Variables:"
}

test_env_print_out_alias() {
    run_script --env out
    assert_rc "env out alias exits 0" 0
    assert_stdout_contains "out is output" "Output Environment Variables:"
}

test_env_print_invalid() {
    run_script --env invalid
    assert_rc "env invalid exits 1" 1
    assert_err_contains "env invalid error" "Invalid argument for -E|--env: invalid"
}

test_env_print_no_arg() {
    J_CLIENT_ID="test" run_script --env
    assert_rc "env no arg exits 0" 0
    assert_stdout_contains "env default is all" "Input Environment Variables:"
    assert_stdout_contains "env default has output" "Output Environment Variables:"
}

test_short_option_client() {
    run_script -e am -c "client123" -s "secret456"
    assert_rc "short options exit 0" 0
    assert_contains "short -c works" "$(get_curl_args)" "base64:client123:secret456"
}

test_short_option_scopes() {
    run_script -e am -c "client123" -s "secret456" -S "read"
    assert_rc "short -S exits 0" 0
    assert_contains "short -S works" "$(get_curl_body)" "scope=read"
}

test_short_option_shortcode() {
    run_script -e slas -c "client123" -s "secret456" -C "kv7kzm78" -o "f_ecom_zzxy_001"
    assert_rc "short -C exits 0" 0
    assert_contains "short -C works" "$(get_curl_args)" "kv7kzm78.api.commercecloud.salesforce.com"
}

test_alias_option_client() {
    run_script --endpoint am --client "client123" --secret "secret456"
    assert_rc "alias options exit 0" 0
    assert_contains "alias --client works" "$(get_curl_args)" "base64:client123:secret456"
}

test_alias_option_scope() {
    run_script --endpoint am --client-id "client123" --client-secret "secret456" --scope "read"
    assert_rc "alias --scope exits 0" 0
    assert_contains "alias --scope works" "$(get_curl_body)" "scope=read"
}

test_curl_not_found() {
    rm "$SHIM_DIR/curl"
    PATH="$SHIM_DIR" run_script --endpoint am --client-id "client123" --client-secret "secret456"
    assert_rc "curl not found exits 127" 127
}

test_jq_not_found() {
    rm "$SHIM_DIR/jq"
    PATH="$SHIM_DIR" run_script --endpoint am --client-id "client123" --client-secret "secret456"
    assert_rc "jq not found exits 127" 127
}

test_base64_not_found() {
    rm "$SHIM_DIR/base64"
    PATH="$SHIM_DIR" run_script --endpoint am --client-id "client123" --client-secret "secret456"
    assert_rc "base64 not found exits 127" 127
}

test_date_not_found() {
    rm "$SHIM_DIR/date"
    PATH="$SHIM_DIR" run_script --endpoint am --client-id "client123" --client-secret "secret456"
    # date is used in $((...)) arithmetic, so command not found causes exit 127
    assert_rc "date missing exits 127" 127
}

test_scopes_empty_string() {
    run_script --endpoint am --client-id "client123" --client-secret "secret456" --scopes ""
    assert_rc "empty scopes exits 0" 0
    # Empty string is falsy in bash [ "$scopes" ] test, so no scope added
    assert_not_contains "no scope in body" "$(get_curl_body)" "scope="
}

test_capital_e_env_after_other_options() {
    run_script --client-id "test" -E
    assert_rc "capital E after opts exits 0" 0
    assert_stdout_contains "capital E works" "Environment Variables:"
}

# --- run ---

run_tests "$@"
