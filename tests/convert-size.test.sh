#!/bin/bash
# convert-size.test.sh - Tests for convert-size
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../convert-size"

# --- shims ---

# No shims needed - bc and sed are safe to use directly

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has EXAMPLES" "EXAMPLES"
}

test_short_help() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
}

test_missing_bc() {
    # Use empty PATH to simulate missing bc
    env TEST_DIR="$TEST_DIR" PATH="" \
        /bin/bash "$UNDER_TEST" -t si 500G >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing bc exits 3" 3
    assert_stderr_contains "missing bc error" "bc is required"
}

test_missing_target() {
    run_script 500G
    assert_rc "missing -t exits 2" 2
    assert_stderr_contains "missing -t shows usage" "[ERR][convert-size] Must provide a target system and size"
}

test_missing_size() {
    run_script -t binary
    assert_rc "missing size exits 2" 2
    assert_stderr_contains "missing size shows usage" "[ERR][convert-size] Must provide a target system and size"
}

test_duplicate_to_option() {
    run_script -t binary -t si 500G
    assert_rc "duplicate -t exits 2" 2
    assert_stderr_contains "duplicate -t error" "-t|--to option is specified more than once"
}

test_duplicate_unit_option() {
    run_script -t binary -u G -u M 500
    assert_rc "duplicate -u exits 2" 2
    assert_stderr_contains "duplicate -u error" "-u|--unit option is specified more than once"
}

test_multiple_sizes() {
    run_script -t binary 500G 600M
    assert_rc "multiple sizes exits 2" 2
    assert_stderr_contains "multiple sizes error" "Multiple size inputs"
}

test_space_separated_unit() {
    run_script -t binary 500 GB
    assert_rc "space-separated unit exits 0" 0
    assert_stdout_contains "500 GB converts like 500G" "465.66G"
}

test_space_separated_unit_single_letter() {
    run_script -t binary 500 G
    assert_rc "space-separated single letter exits 0" 0
    assert_stdout_contains "500 G converts like 500G" "465.66G"
}

test_space_separated_unit_lowercase() {
    run_script -t binary 500 mb
    assert_rc "space-separated lowercase exits 0" 0
    assert_stdout_contains "500 mb converts like 500M" "476.83M"
}

test_space_separated_rejects_when_first_has_suffix() {
    run_script -t binary 500G G
    assert_rc "500G G exits 2" 2
    assert_stderr_contains "still errors when first has suffix" "Multiple size inputs"
}

test_invalid_size_non_numeric() {
    run_script -t binary abc
    assert_rc "invalid size exits 2" 2
    assert_stderr_contains "invalid size error" "Invalid size: A. Must be a positive integer"
}

test_invalid_size_negative() {
    run_script -t binary -500G
    assert_rc "negative size exits 2" 2
    assert_stderr_contains "negative size error" "Invalid size: -500"
}

test_bundled_short_with_glued_value() {
    # -tbinary equivalent to -t binary, glued via preprocessor
    run_script -tbinary 500G
    assert_rc "glued -tbinary exits 0" 0
    assert_stdout_contains "glued -tbinary converts" "465.66G"
}

test_equals_long_option() {
    run_script --to=binary 500G
    assert_rc "--to=binary exits 0" 0
    assert_stdout_contains "--to=binary converts" "465.66G"
}

test_invalid_unit() {
    run_script -t binary 500X
    assert_rc "invalid unit exits 2" 2
    assert_stderr_contains "invalid unit error" "Invalid size: 500X. Must be a positive integer"
}

test_invalid_unit_override() {
    run_script -t binary -u Z 500
    assert_rc "invalid unit override exits 2" 2
    assert_stderr_contains "invalid unit override error" "Invalid unit: Z"
}

test_invalid_target_system() {
    run_script -t foo 500G
    assert_rc "invalid target exits 2" 2
    assert_stderr_contains "invalid target error" "Invalid -t|--to 'foo'"
}

test_si_to_binary_gigabytes() {
    run_script -t binary 500G
    assert_rc "500G to binary exits 0" 0
    assert_stdout_contains "500G converts correctly" "465.66G"
}

test_binary_to_si_gigabytes() {
    run_script -t si 256G
    assert_rc "256G to si exits 0" 0
    assert_stdout_contains "256G converts correctly" "274.87G"
}

test_si_to_binary_megabytes() {
    run_script -t windows 100M
    assert_rc "100M to binary exits 0" 0
    assert_stdout_contains "100M converts correctly" "95.36M"
}

test_binary_to_si_megabytes() {
    run_script -t mac 128M
    assert_rc "128M to si exits 0" 0
    assert_stdout_contains "128M converts correctly" "134.21M"
}

test_kilobytes_si_to_binary() {
    run_script -t bin 1000K
    assert_rc "1000K to binary exits 0" 0
    assert_stdout_contains "1000K converts correctly" "976.56K"
}

test_bytes_conversion() {
    run_script -t binary 1000B
    assert_rc "1000B to binary exits 0" 0
    assert_stdout_contains "1000B converts correctly" "1000B"
}

test_terabytes_conversion() {
    run_script -t si 2T
    assert_rc "2T to si exits 0" 0
    assert_stdout_contains "2T converts correctly" "2.19T"
}

test_unit_override_with_bare_number() {
    run_script -t binary -u G 1000
    assert_rc "unit override exits 0" 0
    assert_stdout_contains "1000 with -u G converts" "931.32G"
}

test_unit_override_takes_precedence() {
    run_script -t binary -u M 500G
    assert_rc "override precedence exits 0" 0
    assert_stdout_contains "500 treated as M" "476.83M"
}

test_default_unit_is_bytes() {
    run_script -t binary 1024
    assert_rc "bare number exits 0" 0
    assert_stdout_contains "bare number is bytes" "1024B"
}

test_lowercase_size_suffix() {
    run_script -t binary 500g
    assert_rc "lowercase suffix exits 0" 0
    assert_stdout_contains "lowercase g normalized" "465.66G"
}

test_lowercase_target_system() {
    run_script -t Binary 500G
    assert_rc "mixed case target exits 0" 0
    assert_stdout_contains "Binary recognized" "465.66G"
}

test_lowercase_unit_override() {
    run_script -t binary -u m 100
    assert_rc "lowercase -u exits 0" 0
    assert_stdout_contains "lowercase m normalized" "95.36M"
}

test_target_mac() {
    run_script -t mac 256M
    assert_rc "mac target exits 0" 0
    assert_stdout_contains "mac converts to si" "268.43M"
}

test_target_macos() {
    run_script -t macos 256M
    assert_rc "macos target exits 0" 0
    assert_stdout_contains "macos converts to si" "268.43M"
}

test_target_unix() {
    run_script -t unix 256M
    assert_rc "unix target exits 0" 0
    assert_stdout_contains "unix converts to si" "268.43M"
}

test_target_nix() {
    run_script -t nix 256M
    assert_rc "nix target exits 0" 0
    assert_stdout_contains "nix converts to si" "268.43M"
}

test_target_win() {
    run_script -t win 500G
    assert_rc "win target exits 0" 0
    assert_stdout_contains "win converts to binary" "465.66G"
}

test_target_windows() {
    run_script -t windows 500G
    assert_rc "windows target exits 0" 0
    assert_stdout_contains "windows converts to binary" "465.66G"
}

test_long_option_to() {
    run_script --to binary 500G
    assert_rc "--to exits 0" 0
    assert_stdout_contains "--to works" "465.66G"
}

test_long_option_unit() {
    run_script --to binary --unit G 1000
    assert_rc "--unit exits 0" 0
    assert_stdout_contains "--unit works" "931.32G"
}

test_mixed_long_and_short_options() {
    run_script -t binary --unit G 1000
    assert_rc "mixed options exit 0" 0
    assert_stdout_contains "mixed options work" "931.32G"
}

test_size_before_options() {
    run_script 500G -t binary
    assert_rc "size before -t exits 0" 0
    assert_stdout_contains "size before options works" "465.66G"
}

test_zero_size() {
    run_script -t binary 0G
    assert_rc "0G exits 0" 0
    assert_stdout_contains "0G converts" "0G"
}

test_large_terabyte_value() {
    run_script -t binary 100T
    assert_rc "100T exits 0" 0
    assert_stdout_contains "100T converts" "90.94T"
}

test_small_kilobyte_value() {
    run_script -t si 1K
    assert_rc "1K exits 0" 0
    assert_stdout_contains "1K converts" "1.02K"
}

test_exact_zero_result() {
    run_script -t si 0M
    assert_rc "0M exits 0" 0
    assert_stdout_contains "0M converts to 0" "0M"
}

# --- run ---

run_tests "$@"
