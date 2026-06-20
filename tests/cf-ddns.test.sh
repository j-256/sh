#!/bin/bash
# cf-ddns.test.sh - Tests for cf-ddns
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../cf-ddns"

# --- shims ---

write_shims() {
    # curl shim: handle different API calls
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

# Handle ipify.org separately
for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        printf '%s\n' "203.0.113.42"
        exit 0
    fi
done

# Parse arguments to find method and URL
method=""
url_path=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-X" ]]; then
        method="$a"
    elif [[ "$prev" == "--url" ]]; then
        if [[ "$a" == https://api.cloudflare.com/client/v4/* ]]; then
            url_path="${a#https://api.cloudflare.com/client/v4}"
        fi
    fi
    prev="$a"
done

# Match URL pattern
if [[ "$url_path" == "/zones" ]]; then
    printf '%s\n' '{"success":true,"result":[{"id":"zone123","name":"example.com"}]}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records/[^/]+ ]]; then
    # DELETE specific record
    printf '%s\n' '{"success":true,"result":{"id":"deleted"}}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records$ ]]; then
    if [[ "$method" == "POST" ]]; then
        printf '%s\n' '{"success":true,"result":{"id":"record789"}}'
        exit 0
    else
        # GET records
        printf '%s\n' '{"success":true,"result":[{"type":"A","content":"192.0.2.10","id":"record456"}]}'
        exit 0
    fi
fi

# Default fallback
printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # jq shim: pass through to real jq
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
exec /usr/bin/jq "$@"
SHIM
    chmod +x "$SHIM_DIR/jq"

    # dig shim: return deterministic IP
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/dig.log"
printf 'dig' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

# Check if this is a request that should return empty
for a in "$@"; do
    if [[ "$a" == *"noip"* ]]; then
        exit 0
    fi
done

printf '%s\n' "192.0.2.10"
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"

}

# --- helpers ---

get_curl_log() { cat "$TEST_DIR/curl.log" 2>/dev/null; }
get_dig_log() { cat "$TEST_DIR/dig.log" 2>/dev/null; }

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has cf-ddns" "cf-ddns"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_missing_jq() {
    # Restrict PATH to only shim dir without jq
    rm -f "$SHIM_DIR/jq"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" "token123" "example.com" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing jq" 3
    assert_stderr_contains "jq error message" "jq is required"
}

test_missing_curl() {
    rm -f "$SHIM_DIR/curl"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" "token123" "example.com" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing curl" 3
    assert_stderr_contains "curl error message" "curl is required"
}

test_missing_dig() {
    rm -f "$SHIM_DIR/dig"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" "token123" "example.com" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing dig" 3
    assert_stderr_contains "dig error message" "dig is required"
}

test_missing_api_token() {
    run_script
    assert_rc "missing token" 2
    assert_stderr_contains "token error" "Must provide an API bearer token"
}

test_missing_domain() {
    run_script "token123"
    assert_rc "missing domain" 2
    assert_stderr_contains "domain error" "Must provide a domain name"
}

test_ip_detection_failure() {
    # Make curl fail for ipify
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        exit 1
    fi
done
printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "token123" "example.com"
    assert_rc "ip detection failure" 1
    assert_stderr_contains "ip error" "Failed to get device's IP"
}

test_dns_already_up_to_date() {
    # dig returns same IP as ipify (203.0.113.42)
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
printf '%s\n' "203.0.113.42"
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"

    run_script "token123" "example.com"
    assert_rc "already up to date" 0
    assert_stderr_contains "up to date message" "DNS IP address already up-to-date"
}

test_dns_update_needed() {
    # dig returns different IP than ipify
    run_script "token123" "example.com"
    assert_rc "dns update" 0
    assert_stderr_contains "device ip" "Device's IP: 203.0.113.42"
    assert_stderr_contains "domain ip" "Domain's IP: 192.0.2.10"
    assert_stderr_contains "updating" "IP addresses do not match, updating DNS"
    assert_stderr_contains "deleting" "Deleting A record for 192.0.2.10"
    assert_stderr_contains "creating" "Creating A record for 203.0.113.42"
}

test_domain_no_ip() {
    # dig returns empty
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"

    run_script "token123" "example.com"
    assert_rc "no current ip" 0
    assert_stderr_contains "none message" "Domain's IP: NONE"
}

test_zone_not_found() {
    # Return empty zones list
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        printf '%s\n' "203.0.113.42"
        exit 0
    fi
done
if [[ "$*" == */zones ]]; then
    printf '%s\n' '{"success":true,"result":[]}'
    exit 0
fi
printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "token123" "notfound.com"
    assert_rc "zone not found" 1
    assert_stderr_contains "zone error" "No zone found for domain 'notfound.com'"
}

test_zone_retrieval_jq_error() {
    # Make jq fail on zone parsing
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
# Check if input looks like zones call
input=$(cat)
if [[ "$input" == *"zone123"* ]] && [[ "$*" == *".id"* ]]; then
    echo "jq: error parsing" >&2
    exit 1
fi
exec /usr/bin/jq "$@" <<< "$input"
SHIM
    chmod +x "$SHIM_DIR/jq"

    run_script "token123" "example.com"
    assert_rc "jq error on zones" 1
    assert_stderr_contains "exception message" "Unexpected error while retrieving zone ID"
}

test_no_existing_a_records() {
    # Return empty DNS records
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        printf '%s\n' "203.0.113.42"
        exit 0
    fi
done

method=""
url_path=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-X" ]]; then
        method="$a"
    elif [[ "$prev" == "--url" ]]; then
        if [[ "$a" == https://api.cloudflare.com/client/v4/* ]]; then
            url_path="${a#https://api.cloudflare.com/client/v4}"
        fi
    fi
    prev="$a"
done

if [[ "$url_path" == "/zones" ]]; then
    printf '%s\n' '{"success":true,"result":[{"id":"zone123","name":"example.com"}]}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records$ ]]; then
    if [[ "$method" == "POST" ]]; then
        printf '%s\n' '{"success":true,"result":{"id":"record789"}}'
        exit 0
    else
        printf '%s\n' '{"success":true,"result":[]}'
        exit 0
    fi
fi

printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "token123" "example.com"
    assert_rc "no a records" 0
    assert_stderr_contains "no records message" "No existing A records"
    assert_stderr_contains "creating only" "Creating A record for 203.0.113.42"
    assert_stderr_not_contains "no delete" "Deleting A record"
}

test_multiple_a_records() {
    # Return multiple A records
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        printf '%s\n' "203.0.113.42"
        exit 0
    fi
done

method=""
url_path=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-X" ]]; then
        method="$a"
    elif [[ "$prev" == "--url" ]]; then
        if [[ "$a" == https://api.cloudflare.com/client/v4/* ]]; then
            url_path="${a#https://api.cloudflare.com/client/v4}"
        fi
    fi
    prev="$a"
done

if [[ "$url_path" == "/zones" ]]; then
    printf '%s\n' '{"success":true,"result":[{"id":"zone123","name":"example.com"}]}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records/[^/]+ ]]; then
    printf '%s\n' '{"success":true,"result":{"id":"deleted"}}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records$ ]]; then
    if [[ "$method" == "POST" ]]; then
        printf '%s\n' '{"success":true,"result":{"id":"record789"}}'
        exit 0
    else
        printf '%s\n' '{"success":true,"result":[{"type":"A","content":"192.0.2.10","id":"record1"},{"type":"A","content":"192.0.2.11","id":"record2"}]}'
        exit 0
    fi
fi

printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "token123" "example.com"
    assert_rc "multiple records" 0
    assert_contains "delete first" "$(get_stderr)" "Deleting A record for 192.0.2.10"
    assert_contains "delete second" "$(get_stderr)" "Deleting A record for 192.0.2.11"
}

test_delete_record_api_failure() {
    # Make DELETE return failure
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        printf '%s\n' "203.0.113.42"
        exit 0
    fi
done

method=""
url_path=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-X" ]]; then
        method="$a"
    elif [[ "$prev" == "--url" ]]; then
        if [[ "$a" == https://api.cloudflare.com/client/v4/* ]]; then
            url_path="${a#https://api.cloudflare.com/client/v4}"
        fi
    fi
    prev="$a"
done

if [[ "$url_path" == "/zones" ]]; then
    printf '%s\n' '{"success":true,"result":[{"id":"zone123","name":"example.com"}]}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records/[^/]+ ]]; then
    printf '%s\n' '{"success":false,"errors":[{"message":"delete failed"}]}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records$ ]]; then
    if [[ "$method" == "POST" ]]; then
        printf '%s\n' '{"success":true,"result":{"id":"record789"}}'
        exit 0
    else
        printf '%s\n' '{"success":true,"result":[{"type":"A","content":"192.0.2.10","id":"record456"}]}'
        exit 0
    fi
fi

printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "token123" "example.com"
    assert_rc "delete failure still creates" 0
    assert_stderr_contains "delete failed" "Delete DNS Record request failed"
}

test_create_record_api_failure() {
    # Make POST return failure
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

for a in "$@"; do
    if [[ "$a" == *"ipify.org"* ]]; then
        printf '%s\n' "203.0.113.42"
        exit 0
    fi
done

method=""
url_path=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-X" ]]; then
        method="$a"
    elif [[ "$prev" == "--url" ]]; then
        if [[ "$a" == https://api.cloudflare.com/client/v4/* ]]; then
            url_path="${a#https://api.cloudflare.com/client/v4}"
        fi
    fi
    prev="$a"
done

if [[ "$url_path" == "/zones" ]]; then
    printf '%s\n' '{"success":true,"result":[{"id":"zone123","name":"example.com"}]}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records/[^/]+ ]]; then
    printf '%s\n' '{"success":true,"result":{"id":"deleted"}}'
    exit 0
elif [[ "$url_path" =~ ^/zones/[^/]+/dns_records$ ]]; then
    if [[ "$method" == "POST" ]]; then
        printf '%s\n' '{"success":false,"errors":[{"message":"create failed"}]}'
        exit 0
    else
        printf '%s\n' '{"success":true,"result":[{"type":"A","content":"192.0.2.10","id":"record456"}]}'
        exit 0
    fi
fi

printf '%s\n' '{"success":true,"result":[]}'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "token123" "example.com"
    assert_rc "create failure" 0
    assert_stderr_contains "create failed" "Create DNS Record request failed"
}

test_api_calls_use_bearer_token() {
    run_script "mytoken456" "example.com"
    assert_rc "token passed" 0
    assert_contains "bearer token" "$(get_curl_log)" "Bearer mytoken456"
}

test_dig_uses_tcp() {
    run_script "token123" "example.com"
    assert_rc "dig tcp" 0
    assert_contains "tcp flag" "$(get_dig_log)" "+tcp"
}

test_dig_uses_google_dns() {
    run_script "token123" "example.com"
    assert_rc "google dns" 0
    assert_contains "8.8.8.8" "$(get_dig_log)" "@8.8.8.8"
}

test_curl_api_base_url() {
    run_script "token123" "example.com"
    assert_rc "api base" 0
    assert_contains "cloudflare api" "$(get_curl_log)" "https://api.cloudflare.com/client/v4"
}

test_debug_mode() {
    DDNS_DEBUG=1 run_script "token123" "example.com"
    assert_rc "debug mode" 0
    assert_stderr_contains "debug output" "[DBG]"
}

test_no_debug_mode() {
    run_script "token123" "example.com"
    assert_rc "no debug" 0
    assert_stderr_not_contains "no debug output" "[DBG]"
}

# --- run ---

run_tests "$@"
