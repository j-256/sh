#!/bin/bash
# pkce.test.sh - Tests for pkce
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../pkce"

# --- shims ---

write_shims() {
    # openssl rand shim: return deterministic base64 output
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
case "$1" in
    rand)
        # Deterministic 96-byte base64 output (128 chars unpadded)
        # 96 bytes = 128 base64 chars exactly (no padding needed)
        printf '%s\n' "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        exit 0
        ;;
    dgst)
        # Simulate sha256 digest of the verifier
        # Return binary sha256 (32 bytes for sha256)
        printf '\x1a\x2b\x3c\x4d\x5e\x6f\x70\x81\x92\xa3\xb4\xc5\xd6\xe7\xf8\x09\x1a\x2b\x3c\x4d\x5e\x6f\x70\x81\x92\xa3\xb4\xc5\xd6\xe7\xf8\x09'
        exit 0
        ;;
    enc)
        # Simulate base64 encoding of the digest
        # 32 bytes base64-encoded = 44 chars (with padding)
        printf '%s\n' "GitsPE1ebyBBksO0xdbn+AkaKzxNXm8wcZKjtMXW5/gJ+A=="
        exit 0
        ;;
    *)
        echo "openssl: unknown command: $1" >&2
        exit 1
        ;;
esac
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
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has EXAMPLES" "EXAMPLES"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help mentions RFC 7636" "RFC 7636"
}

test_help_short() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_default_tab_separator() {
    run_script
    assert_rc "default exits 0" 0
    local output
    output="$(get_stdout)"
    # Should contain a tab character between verifier and challenge
    assert_contains "contains tab" "$output" "$(printf '\t')"
    # Should have exactly one tab (verifier<tab>challenge)
    local tab_count
    tab_count=$(printf '%s' "$output" | tr -cd '\t' | wc -c | tr -d ' ')
    assert_eq "one tab separator" "$tab_count" "1"
}

test_newline_separator_long() {
    run_script --newline
    assert_rc "newline exits 0" 0
    local output
    output="$(get_stdout)"
    # Should NOT contain a tab character
    assert_not_contains "no tab with --newline" "$output" "$(printf '\t')"
    # Should contain an embedded newline (verifier<newline>challenge)
    assert_contains "has embedded newline" "$output" "$(printf '\n')"
    # Should be splittable into two parts with sed
    local first_line
    first_line=$(printf '%s' "$output" | sed -n '1p')
    [ -n "$first_line" ] || _fail "first line is empty"
    local second_line
    second_line=$(printf '%s' "$output" | sed -n '2p')
    [ -n "$second_line" ] || _fail "second line is empty"
}

test_newline_separator_short() {
    run_script -n
    assert_rc "newline -n exits 0" 0
    local output
    output="$(get_stdout)"
    assert_not_contains "no tab with -n" "$output" "$(printf '\t')"
    # Should contain an embedded newline
    assert_contains "has embedded newline with -n" "$output" "$(printf '\n')"
}

test_verifier_length() {
    run_script
    assert_rc "verifier length test exits 0" 0
    local verifier
    verifier="$(get_stdout | cut -f1)"
    local len
    len=$(printf '%s' "$verifier" | wc -c | tr -d ' ')
    assert_eq "verifier is 128 characters" "$len" "128"
}

test_challenge_present() {
    run_script
    assert_rc "challenge test exits 0" 0
    local challenge
    challenge="$(get_stdout | cut -f2)"
    # Challenge should not be empty
    [ -n "$challenge" ] || _fail "challenge is empty"
    # Challenge should be base64-url encoded (no =, +, /)
    assert_not_contains "no padding in challenge" "$challenge" "="
    assert_not_contains "no + in challenge" "$challenge" "+"
    assert_not_contains "no / in challenge" "$challenge" "/"
}

test_verifier_base64url_format() {
    run_script
    assert_rc "verifier format test exits 0" 0
    local verifier
    verifier="$(get_stdout | cut -f1)"
    # Verifier should be base64-url encoded (no =, +, /)
    assert_not_contains "no padding in verifier" "$verifier" "="
    assert_not_contains "no + in verifier" "$verifier" "+"
    assert_not_contains "no / in verifier" "$verifier" "/"
}

test_verifier_contains_underscore() {
    run_script
    assert_rc "underscore test exits 0" 0
    local verifier
    verifier="$(get_stdout | cut -f1)"
    # Our deterministic shim output should produce underscores (/ -> _)
    assert_contains "verifier has underscore" "$verifier" "_"
}

test_verifier_contains_dash() {
    run_script
    assert_rc "dash test exits 0" 0
    local verifier
    verifier="$(get_stdout | cut -f1)"
    # Our deterministic shim output should produce dashes (+ -> -)
    assert_contains "verifier has dash" "$verifier" "-"
}

test_cut_extraction() {
    run_script
    assert_rc "cut extraction exits 0" 0
    local codes
    codes="$(get_stdout)"
    local verifier
    verifier="$(printf '%s' "$codes" | cut -f1)"
    local challenge
    challenge="$(printf '%s' "$codes" | cut -f2)"
    # Both should be non-empty
    [ -n "$verifier" ] || _fail "cut verifier is empty"
    [ -n "$challenge" ] || _fail "cut challenge is empty"
    # Verifier should be 128 chars
    local len
    len=$(printf '%s' "$verifier" | wc -c | tr -d ' ')
    assert_eq "cut verifier is 128 characters" "$len" "128"
}

test_read_with_newline() {
    run_script -n
    assert_rc "read test exits 0" 0
    local output
    output="$(get_stdout)"
    # Simulate { read -r verifier; read -r challenge; } < <(pkce -n)
    # sed -n '1p' gets the first line, '2p' gets the second
    local verifier
    local challenge
    verifier="$(printf '%s' "$output" | sed -n '1p')"
    challenge="$(printf '%s' "$output" | sed -n '2p')"
    # Both should be non-empty
    [ -n "$verifier" ] || _fail "read verifier is empty"
    [ -n "$challenge" ] || _fail "read challenge is empty"
    # Verifier should be 128 chars
    local vlen
    vlen=$(printf '%s' "$verifier" | wc -c | tr -d ' ')
    assert_eq "read verifier is 128 characters" "$vlen" "128"
    # Challenge should be non-trivial (at least 20 chars)
    local clen
    clen=$(printf '%s' "$challenge" | wc -c | tr -d ' ')
    [ "$clen" -gt 20 ] || _fail "challenge too short: $clen"
}

test_invalid_option() {
    run_script --invalid-option
    assert_rc "invalid option exits 2" 2
    assert_err_contains "invalid option error mentions flag" "--invalid-option"
    assert_err_contains "invalid option points to -h" "-h"
    # No output should be produced
    local output
    output="$(get_stdout)"
    assert_eq "invalid option writes nothing to stdout" "$output" ""
}

test_openssl_rand_called() {
    run_script
    assert_rc "openssl test exits 0" 0
    # With our shim, we should get deterministic output
    local verifier
    verifier="$(get_stdout | cut -f1)"
    # The shim produces a specific pattern after base64-url conversion
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/... becomes
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_...
    assert_contains "verifier starts correctly" "$verifier" "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
}

test_no_trailing_newline_default() {
    run_script
    assert_rc "trailing newline test exits 0" 0
    # Output should not end with a newline (printf without trailing \n)
    # We can't test this directly with get_stdout since cat adds a newline,
    # but we can verify the format is correct
    local output
    output="$(get_stdout)"
    # Should have verifier, tab, challenge, no newline
    local last_char
    last_char=$(printf '%s' "$output" | tail -c 1)
    # Last char should not be a tab (it should be part of the challenge)
    assert_not_contains "no trailing tab" "$last_char" "$(printf '\t')"
}

test_challenge_deterministic() {
    run_script
    assert_rc "deterministic challenge exits 0" 0
    local challenge
    challenge="$(get_stdout | cut -f2)"
    # With our shim, the challenge should be deterministic
    # The shim returns a specific base64 string for the digest
    # GitsPE1ebyBBksO0xdbn-AkaKzxNXm8gcZKjtMXW5_gJ (after base64-url conversion)
    assert_contains "challenge is deterministic" "$challenge" "Git"
}

# --- run ---

run_tests "$@"
