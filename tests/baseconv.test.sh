#!/bin/bash
# baseconv.test.sh - Tests for baseconv
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../baseconv"

# --- shims ---

# No shims needed - bc and grep are safe to use directly

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has EXAMPLES" "EXAMPLES"
    assert_stdout_contains "help has EXIT STATUS" "EXIT STATUS"
}

test_short_help() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
}

test_missing_all_args() {
    run_script
    assert_rc "no args exits 2" 2
    assert_stderr_contains "missing args error" "Must provide <from>, <to>, and <number>"
}

test_missing_third_arg() {
    run_script hex dec
    assert_rc "two args exits 2" 2
    assert_stderr_contains "missing third arg error" "Must provide <from>, <to>, and <number>"
}

test_too_many_args() {
    run_script hex dec ff extra
    assert_rc "four args exits 2" 2
    assert_stderr_contains "too many args error" "Too many arguments"
}

test_unknown_flag() {
    run_script -z hex dec ff
    assert_rc "unknown flag exits 2" 2
    assert_stderr_contains "unknown flag error" "Unknown argument '-z'"
}

test_missing_bc() {
    env TEST_DIR="$TEST_DIR" PATH="" \
        /bin/bash "$UNDER_TEST" hex dec ff >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing bc exits 3" 3
    assert_stderr_contains "missing bc error" "bc is required"
}

test_invalid_from_base() {
    run_script foo dec 10
    assert_rc "invalid from exits 2" 2
    assert_stderr_contains "invalid from error" "Invalid <from> base 'foo'"
}

test_invalid_to_base() {
    run_script dec foo 10
    assert_rc "invalid to exits 2" 2
    assert_stderr_contains "invalid to error" "Invalid <to> base 'foo'"
}

test_invalid_digit_for_binary() {
    run_script bin dec 102
    assert_rc "invalid bin digit exits 2" 2
    assert_stderr_contains "invalid bin digit error" "Invalid number '102' for base 2"
}

test_invalid_digit_for_octal() {
    run_script oct dec 89
    assert_rc "invalid oct digit exits 2" 2
    assert_stderr_contains "invalid oct digit error" "Invalid number '89' for base 8"
}

test_invalid_digit_for_decimal() {
    run_script dec hex abc
    assert_rc "invalid dec digit exits 2" 2
    assert_stderr_contains "invalid dec digit error" "Invalid number 'abc' for base 10"
}

test_invalid_digit_for_hex() {
    run_script hex dec xyz
    assert_rc "invalid hex digit exits 2" 2
    assert_stderr_contains "invalid hex digit error" "Invalid number 'xyz' for base 16"
}

# --- conversion table ---

test_hex_to_dec() {
    run_script hex dec ff
    assert_rc "hex->dec exits 0" 0
    assert_stdout_contains "ff hex = 255 dec" "255"
}

test_dec_to_hex() {
    run_script dec hex 255
    assert_rc "dec->hex exits 0" 0
    assert_stdout_contains "255 dec = FF hex" "FF"
}

test_dec_to_bin() {
    run_script dec bin 10
    assert_rc "dec->bin exits 0" 0
    assert_stdout_contains "10 dec = 1010 bin" "1010"
}

test_bin_to_dec() {
    run_script bin dec 1010
    assert_rc "bin->dec exits 0" 0
    assert_stdout_contains "1010 bin = 10 dec" "10"
}

test_bin_to_hex() {
    run_script bin hex 11111111
    assert_rc "bin->hex exits 0" 0
    assert_stdout_contains "11111111 bin = FF hex" "FF"
}

test_hex_to_bin() {
    run_script hex bin ff
    assert_rc "hex->bin exits 0" 0
    assert_stdout_contains "ff hex = 11111111 bin" "11111111"
}

test_oct_to_dec() {
    run_script oct dec 17
    assert_rc "oct->dec exits 0" 0
    assert_stdout_contains "17 oct = 15 dec" "15"
}

test_dec_to_oct() {
    run_script dec oct 15
    assert_rc "dec->oct exits 0" 0
    assert_stdout_contains "15 dec = 17 oct" "17"
}

test_zero_round_trip() {
    run_script dec hex 0
    assert_rc "0 dec->hex exits 0" 0
    assert_stdout_contains "0 dec = 0 hex" "0"
}

test_large_hex_to_bin() {
    run_script hex bin deadbeef
    assert_rc "deadbeef->bin exits 0" 0
    assert_stdout_contains "deadbeef bin form" "11011110101011011011111011101111"
}

# --- alias coverage ---

test_single_letter_aliases() {
    run_script h d ff
    assert_rc "h d aliases exit 0" 0
    assert_stdout_contains "h->d works" "255"
}

test_x_alias_for_hex() {
    run_script x d ff
    assert_rc "x alias exits 0" 0
    assert_stdout_contains "x->d works" "255"
}

test_numeric_aliases() {
    run_script 16 10 ff
    assert_rc "numeric aliases exit 0" 0
    assert_stdout_contains "16->10 works" "255"
}

test_b_alias_for_binary() {
    run_script b o 11111111
    assert_rc "b->o exits 0" 0
    assert_stdout_contains "b->o works" "377"
}

test_uppercase_base_names() {
    run_script HEX DEC ff
    assert_rc "uppercase base names exit 0" 0
    assert_stdout_contains "HEX/DEC normalized" "255"
}

test_uppercase_hex_input() {
    run_script hex dec FF
    assert_rc "uppercase hex digits exit 0" 0
    assert_stdout_contains "FF input works" "255"
}

test_mixed_case_hex_input() {
    run_script hex bin DeAdBeEf
    assert_rc "mixed-case hex exits 0" 0
    assert_stdout_contains "mixed-case normalized" "11011110101011011011111011101111"
}

# --- run ---

run_tests "$@"
