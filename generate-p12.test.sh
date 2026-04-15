#!/bin/bash
# generate-p12.test.sh - Tests for generate-p12
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/generate-p12"

# --- helpers ---

# Create fake cert bundle files in TEST_DIR
create_cert_bundle() {
    local hostname="$1"
    local suffix="${2:-01}"
    : > "$TEST_DIR/${hostname}_${suffix}.crt"
    : > "$TEST_DIR/${hostname}_${suffix}.key"
    : > "$TEST_DIR/${hostname}_${suffix}.txt"
    : > "$TEST_DIR/${hostname}.srl"
}

# Set up input for interactive prompts
# Usage: setup_input "hostname" "years"
setup_input() {
    local hostname="$1"
    local years="$2"
    printf '%s\n%s\n' "$hostname" "$years" > "$TEST_DIR/input"
}

# Run script with input file
run_script_with_input() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" "$@" < "$TEST_DIR/input" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# --- shims ---

write_shims() {
    # openssl shim: tracks which subcommand was called
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/openssl.log"
printf 'openssl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

case "$1" in
    req)
        # Generate CSR and key
        while [ $# -gt 0 ]; do
            case "$1" in
                -out) touch "$2"; shift 2 ;;
                -keyout) touch "$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        exit 0
        ;;
    x509)
        # Generate certificate
        while [ $# -gt 0 ]; do
            case "$1" in
                -out) touch "$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        exit 0
        ;;
    pkcs12)
        # Generate p12 bundle
        while [ $# -gt 0 ]; do
            case "$1" in
                -out) touch "$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        exit 0
        ;;
    *)
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
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_missing_directory() {
    run_script "/nonexistent/path/to/nowhere" < /dev/null
    assert_rc "missing dir fails" 1
}

test_missing_ca_cert() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    rm "$TEST_DIR/cert.staging.customer.realm.demandware.net_01.crt"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "missing ca cert" 1
}

test_missing_ca_key() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    rm "$TEST_DIR/cert.staging.customer.realm.demandware.net_01.key"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "missing ca key" 1
}

test_missing_ca_password() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    rm "$TEST_DIR/cert.staging.customer.realm.demandware.net_01.txt"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "missing ca pass" 1
}

test_missing_ca_serial() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    rm "$TEST_DIR/cert.staging.customer.realm.demandware.net.srl"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "missing ca serial" 1
}

test_openssl_req_failure() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    # Make openssl req fail
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/openssl.log"
printf 'openssl %s\n' "$1" >> "$log"
case "$1" in
    req) exit 1 ;;
    *) exit 0 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/openssl"

    run_script_with_input "$TEST_DIR"
    assert_rc "openssl req fails" 1
}

test_openssl_x509_failure() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    # Make openssl x509 fail
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/openssl.log"
printf 'openssl %s\n' "$1" >> "$log"
case "$1" in
    req)
        for a in "$@"; do
            case "$a" in
                -out) shift; touch "$1"; shift ;;
                -keyout) shift; touch "$1"; shift ;;
                *) shift ;;
            esac
        done
        exit 0
        ;;
    x509) exit 1 ;;
    *) exit 0 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/openssl"

    run_script_with_input "$TEST_DIR"
    assert_rc "openssl x509 fails" 1
}

test_openssl_pkcs12_failure() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    # Make openssl pkcs12 fail
    cat > "$SHIM_DIR/openssl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/openssl.log"
printf 'openssl %s\n' "$1" >> "$log"
case "$1" in
    req|x509)
        for a in "$@"; do
            case "$a" in
                -out) shift; touch "$1"; shift ;;
                -keyout) shift; touch "$1"; shift ;;
                *) shift ;;
            esac
        done
        exit 0
        ;;
    pkcs12) exit 1 ;;
    *) exit 0 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/openssl"

    run_script_with_input "$TEST_DIR"
    assert_rc "openssl pkcs12 fails" 1
}

test_hostname_normalization_short() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer-realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "short hostname succeeds" 0
}

test_hostname_normalization_full() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "cert.staging.customer.realm.demandware.net" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "full hostname succeeds" 0
}

test_hostname_normalization_production() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "production.customer.realm.demandware.net" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "production hostname normalized" 0
}

test_hostname_normalization_development() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "development.customer.realm.demandware.net" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "development hostname normalized" 0
}

test_hostname_with_underscores() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer_realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "underscores converted" 0
}

test_years_validation_zero() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    printf 'customer.realm\n0\n1\n' > "$TEST_DIR/input"

    run_script_with_input "$TEST_DIR"
    assert_rc "rejects zero years" 0
}

test_years_validation_negative() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    printf 'customer.realm\n-5\n1\n' > "$TEST_DIR/input"

    run_script_with_input "$TEST_DIR"
    assert_rc "rejects negative years" 0
}

test_years_validation_non_numeric() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    printf 'customer.realm\nabc\n1\n' > "$TEST_DIR/input"

    run_script_with_input "$TEST_DIR"
    assert_rc "rejects non-numeric" 0
}

test_happy_path_default_dir() {
    cd "$TEST_DIR" || exit 1
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "2"

    run_script_with_input
    assert_rc "default dir succeeds" 0
    # Note: When stdin is redirected, _color() tries to read from stdin
    # instead of using arguments, so normal output is not captured
    # We can only reliably test exit code and file creation
}

test_happy_path_explicit_dir() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "3"

    run_script_with_input "$TEST_DIR"
    assert_rc "explicit dir succeeds" 0
}

test_openssl_commands_invoked() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "commands invoked" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log")"
    assert_contains "req called" "$log" "openssl req"
    assert_contains "x509 called" "$log" "openssl x509"
    assert_contains "pkcs12 called" "$log" "openssl pkcs12"
}

test_openssl_req_args() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "req args" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log" | grep '^openssl req')"
    assert_contains "uses sha256" "$log" "-sha256"
    assert_contains "uses rsa:2048" "$log" "rsa:2048"
    assert_contains "uses -nodes" "$log" "-nodes"
    assert_contains "has -out" "$log" "-out"
    assert_contains "has -keyout" "$log" "-keyout"
}

test_openssl_x509_args() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "5"

    run_script_with_input "$TEST_DIR"
    assert_rc "x509 args" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log" | grep '^openssl x509')"
    assert_contains "has -req" "$log" "-req"
    assert_contains "has -in" "$log" "-in"
    assert_contains "has -out" "$log" "-out"
    assert_contains "has -days" "$log" "-days"
    assert_contains "calculates days" "$log" "1825" # 5 years * 365
    assert_contains "has -CA" "$log" "-CA"
    assert_contains "has -CAkey" "$log" "-CAkey"
    assert_contains "has -passin" "$log" "-passin"
    assert_contains "has -CAserial" "$log" "-CAserial"
}

test_openssl_pkcs12_args() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "pkcs12 args" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log" | grep '^openssl pkcs12')"
    assert_contains "has -export" "$log" "-export"
    assert_contains "has -in" "$log" "-in"
    assert_contains "has -inkey" "$log" "-inkey"
    assert_contains "has -certfile" "$log" "-certfile"
    assert_contains "has -name" "$log" "-name"
    assert_contains "has -out" "$log" "-out"
}

test_output_files_created() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "files created" 0

    local user="$USER"
    local hostname="cert.staging.customer.realm.demandware.net"
    [ -f "$TEST_DIR/$user-$hostname.req" ] || _fail "req file not created"
    [ -f "$TEST_DIR/$user-$hostname.key" ] || _fail "key file not created"
    [ -f "$TEST_DIR/$user-$hostname.pem" ] || _fail "pem file not created"
    [ -f "$TEST_DIR/$user-$hostname.p12" ] || _fail "p12 file not created"
}

test_days_calculation() {
    create_cert_bundle "cert.staging.customer.realm.demandware.net"
    setup_input "customer.realm" "10"

    run_script_with_input "$TEST_DIR"
    assert_rc "days calculation" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log" | grep '^openssl x509')"
    assert_contains "10 years is 3650 days" "$log" "3650"
}

test_suffix_02_only() {
    local hostname="cert.staging.customer.realm.demandware.net"
    create_cert_bundle "$hostname" "02"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "suffix 02 succeeds" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log")"
    assert_contains "uses _02 cert" "$log" "${hostname}_02.crt"
    assert_contains "uses _02 key" "$log" "${hostname}_02.key"
    assert_contains "uses _02 pass" "$log" "${hostname}_02.txt"
}

test_suffix_picks_highest() {
    local hostname="cert.staging.customer.realm.demandware.net"
    create_cert_bundle "$hostname" "01"
    create_cert_bundle "$hostname" "02"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "highest suffix succeeds" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log")"
    assert_contains "uses _02 cert" "$log" "${hostname}_02.crt"
    assert_contains "uses _02 key" "$log" "${hostname}_02.key"
    assert_contains "uses _02 pass" "$log" "${hostname}_02.txt"
}

test_suffix_skips_incomplete() {
    local hostname="cert.staging.customer.realm.demandware.net"
    create_cert_bundle "$hostname" "01"
    # Create _02 with only .crt and .key (missing .txt)
    : > "$TEST_DIR/${hostname}_02.crt"
    : > "$TEST_DIR/${hostname}_02.key"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "falls back to 01" 0

    local log
    log="$(cat "$TEST_DIR/openssl.log")"
    assert_contains "uses _01 cert" "$log" "${hostname}_01.crt"
    assert_contains "uses _01 key" "$log" "${hostname}_01.key"
    assert_contains "uses _01 pass" "$log" "${hostname}_01.txt"
}

test_suffix_no_complete_bundle() {
    local hostname="cert.staging.customer.realm.demandware.net"
    : > "$TEST_DIR/${hostname}.srl"
    # Only .crt exists for _01
    : > "$TEST_DIR/${hostname}_01.crt"
    setup_input "customer.realm" "1"

    run_script_with_input "$TEST_DIR"
    assert_rc "no complete bundle fails" 1
}

# --- run ---

run_tests "$@"
