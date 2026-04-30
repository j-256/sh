#!/bin/bash
# cf-ips-subnets.test.sh - Tests for cf-ips-subnets
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../cf-ips-subnets"

# --- shims ---

write_shims() {
    # curl shim: return fake Cloudflare IP ranges
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
if [ -f "$TEST_DIR/curl.response" ]; then
    cat "$TEST_DIR/curl.response"
else
    printf '%s\n' "103.21.244.0/22"
    printf '%s\n' "173.245.48.0/20"
    printf '%s\n' "198.41.0.0/16"
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # ipcalc shim: simulate subnet expansion
    # The real ipcalc -b outputs the original network first, then subnets
    # The script uses sed '1d' to skip the first Network: line
    cat > "$SHIM_DIR/ipcalc" <<'SHIM'
#!/bin/bash
flag="$1"
cidr="$2"
new_prefix="$3"
[ "$flag" != "-b" ] && exit 1
case "$cidr" in
    103.21.244.0/22)
        if [ "$new_prefix" = "24" ]; then
            printf 'Network:   %s\n' "103.21.244.0/22"
            printf 'Network:   %s\n' "103.21.244.0/24"
            printf 'Network:   %s\n' "103.21.245.0/24"
            printf 'Network:   %s\n' "103.21.246.0/24"
            printf 'Network:   %s\n' "103.21.247.0/24"
        fi
        ;;
    173.245.48.0/20)
        if [ "$new_prefix" = "24" ]; then
            printf 'Network:   %s\n' "173.245.48.0/20"
            printf 'Network:   %s\n' "173.245.48.0/24"
            printf 'Network:   %s\n' "173.245.49.0/24"
        fi
        ;;
    198.41.0.0/16)
        if [ "$new_prefix" = "16" ]; then
            printf 'Network:   %s\n' "198.41.0.0/16"
            printf 'Network:   %s\n' "198.41.0.0/16"
        fi
        ;;
    192.0.2.0/14)
        if [ "$new_prefix" = "16" ]; then
            printf 'Network:   %s\n' "192.0.2.0/14"
            printf 'Network:   %s\n' "192.0.0.0/16"
            printf 'Network:   %s\n' "192.1.0.0/16"
            printf 'Network:   %s\n' "192.2.0.0/16"
            printf 'Network:   %s\n' "192.3.0.0/16"
        fi
        ;;
    192.0.2.0/25)
        printf 'Network:   %s\n' "192.0.2.0/25"
        printf 'Network:   %s\n' "192.0.2.0/25"
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/ipcalc"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_h_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
}

test_ipcalc_missing() {
    # Remove shim and restrict PATH so command -v fails
    rm "$SHIM_DIR/ipcalc"
    env PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "ipcalc missing exits 1" 1
    assert_err_contains "ipcalc error" "ERROR: ipcalc is required"
}

test_curl_empty_response() {
    : > "$TEST_DIR/curl.response"
    run_script
    assert_rc "empty response exits 1" 1
    assert_err_contains "fetch error" "ERROR: Failed to fetch Cloudflare IPs"
}

test_curl_whitespace_only() {
    printf '\n\n\n' > "$TEST_DIR/curl.response"
    run_script
    assert_rc "whitespace exits 1" 1
    assert_err_contains "whitespace error" "ERROR: Failed to fetch Cloudflare IPs"
}

test_cidr_greater_than_24() {
    printf '192.0.2.0/25\n' > "$TEST_DIR/curl.response"
    run_script
    assert_rc "cidr > 24 exits 1" 1
    assert_err_contains "cidr error" "Cannot allowlist ranges greater than /24"
}

test_cidr_17_to_24_expands_to_24() {
    printf '103.21.244.0/22\n' > "$TEST_DIR/curl.response"
    run_script
    assert_rc "cidr 22 exits 0" 0
    assert_stdout_contains "subnet 244" "103.21.244.0/24"
    assert_stdout_contains "subnet 245" "103.21.245.0/24"
    assert_stdout_contains "subnet 246" "103.21.246.0/24"
    assert_stdout_contains "subnet 247" "103.21.247.0/24"
}

test_cidr_16_or_smaller_expands_to_16() {
    printf '198.41.0.0/16\n' > "$TEST_DIR/curl.response"
    run_script
    assert_rc "cidr 16 exits 0" 0
    assert_stdout_contains "expands to /16" "198.41.0.0/16"
}

test_cidr_14_expands_to_16() {
    printf '192.0.2.0/14\n' > "$TEST_DIR/curl.response"
    run_script
    assert_rc "cidr 14 exits 0" 0
    assert_stdout_contains "expands to /16 subnets" "192.0.0.0/16"
    assert_stdout_contains "second /16" "192.1.0.0/16"
}

test_multiple_ranges() {
    printf '103.21.244.0/22\n173.245.48.0/20\n198.41.0.0/16\n' > "$TEST_DIR/curl.response"
    run_script
    assert_rc "multiple ranges exits 0" 0
    assert_stdout_contains "first range" "103.21.244.0/24"
    assert_stdout_contains "second range" "173.245.48.0/24"
    assert_stdout_contains "third range" "198.41.0.0/16"
}

test_default_response() {
    run_script
    assert_rc "default exits 0" 0
}

# --- run ---

run_tests "$@"
