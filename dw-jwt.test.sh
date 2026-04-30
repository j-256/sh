#!/bin/bash
# dw-jwt.test.sh - Tests for dw-jwt
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/dw-jwt"

# --- shims ---

write_shims() {
    # openssl shim that:
    # - handles `base64 -e -A` as stdin mode OR with `-in <file>`
    # - handles `dgst -sha256 -sign <key>` reading stdin, writing a fake sig to stdout
    # - exits non-zero on `dgst -sha256 -sign <key>` if the key file is unreadable
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
printf 'openssl %s\n' "$*" >> "$TEST_DIR/openssl.log"
if [ "$1 $2 $3" = "base64 -e -A" ]; then
    if [ "$4" = "-in" ] && [ -n "$5" ]; then
        base64 < "$5" | tr -d '\n'
    else
        base64 | tr -d '\n'
    fi
    exit 0
fi
if [ "$1 $2 $3" = "dgst -sha256 -sign" ]; then
    if [ ! -r "$4" ]; then
        printf 'Could not open file %s\n' "$4" >&2
        exit 1
    fi
    # Check if the key file has a valid-looking PEM header.
    if ! head -1 "$4" | grep -q 'PRIVATE KEY'; then
        printf 'unable to load Private Key\n' >&2
        exit 1
    fi
    printf 'FAKE_SIG'
    exit 0
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/openssl"

    cat > "$SHIM_DIR/date" <<'SHIM'
#!/bin/bash
printf 'date %s\n' "$*" >> "$TEST_DIR/date.log"
[ "$1" = "+%s" ] && printf '1700000000'
exit 0
SHIM
    chmod +x "$SHIM_DIR/date"

    mkdir -p "$TEST_DIR/keys"
    printf '%s\n' "-----BEGIN RSA PRIVATE KEY-----" "FAKE" "-----END RSA PRIVATE KEY-----" > "$TEST_DIR/keys/test.key"
    printf '%s\n' "not a pem key" > "$TEST_DIR/keys/bad.key"
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
    assert_stdout_contains "help lists openssl" "openssl"
    assert_stdout_contains "help has EXIT STATUS" "EXIT STATUS"
}

test_help_h_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
}

test_generates_jwt() {
    run_script "test-client-id" "$TEST_DIR/keys/test.key"
    assert_rc "generates jwt" 0
    local jwt; jwt="$(get_stdout)"
    local dots; dots="$(printf '%s' "$jwt" | tr -cd '.' | wc -c | tr -d ' ')"
    assert_eq "jwt has 2 dots (3 parts)" "$dots" "2"
}

test_openssl_calls() {
    run_script "test-client-id" "$TEST_DIR/keys/test.key"
    assert_rc "runs successfully" 0
    assert_contains "openssl base64" "$(cat "$TEST_DIR/openssl.log")" "base64 -e -A"
    assert_contains "openssl dgst" "$(cat "$TEST_DIR/openssl.log")" "dgst -sha256 -sign"
}

test_date_called() {
    run_script "test-client-id" "$TEST_DIR/keys/test.key"
    assert_rc "runs successfully" 0
    assert_contains "date called" "$(cat "$TEST_DIR/date.log")" "date +%s"
}

test_missing_all_args() {
    run_script
    assert_rc "missing all args exits 2" 2
    assert_err_contains "error mentions client_id" "client_id"
    assert_err_contains "error points to help" "-h"
}

test_missing_key_path() {
    run_script "some-client-id"
    assert_rc "missing key path exits 2" 2
    assert_err_contains "error mentions private_key_file" "private_key_file"
}

test_nonexistent_key_file() {
    run_script "test-client-id" "$TEST_DIR/keys/nosuch.key"
    assert_rc "nonexistent key exits 4" 4
    assert_err_contains "error mentions unreadable" "not found or unreadable"
    local out; out="$(get_stdout)"
    assert_eq "no JWT printed on failure" "$out" ""
}

test_malformed_key_file() {
    run_script "test-client-id" "$TEST_DIR/keys/bad.key"
    assert_rc "malformed key fails" 1
    assert_err_contains "error mentions signing failure" "signing failed"
    local out; out="$(get_stdout)"
    assert_eq "no JWT printed on failure" "$out" ""
}

test_empty_client_id() {
    run_script "" "$TEST_DIR/keys/test.key"
    assert_rc "empty client_id exits 2" 2
    assert_err_contains "error mentions client_id" "client_id"
}

# --- run ---

run_tests "$@"
