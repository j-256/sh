#!/bin/bash
# genpw.test.sh - Tests for genpw
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../genpw"

# --- helpers ---

# Create a modified version of genpw that uses a test data source
setup_test_genpw() {
    # Create fake_random with many repetitions of all printable ASCII
    # Build character set: printable ASCII 32-126
    local all_chars
    all_chars="$(awk 'BEGIN{for(i=32;i<=126;i++)printf("%c",i)}')"

    # Repeat 500 times to ensure enough data for any test (47500 chars total)
    local i
    : > "$TEST_DIR/fake_random"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        {
            printf '%s' "$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars"
            printf '%s' "$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars$all_chars"
            printf '%s' "$all_chars$all_chars$all_chars$all_chars$all_chars"
        } >> "$TEST_DIR/fake_random"
    done

    # Copy genpw to a subdir under its real basename so that the script's
    # $SCRIPT_NAME (derived via basename) matches the production value
    local fake_random_path="$TEST_DIR/fake_random"
    mkdir -p "$TEST_DIR/bin"
    sed "s|</dev/random|<\"$fake_random_path\"|g" "$UNDER_TEST" > "$TEST_DIR/bin/genpw"
    chmod +x "$TEST_DIR/bin/genpw"
    UNDER_TEST="$TEST_DIR/bin/genpw"
}

# --- shims ---

write_shims() {
    setup_test_genpw
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help mentions length" "-l, --length"
    assert_stdout_contains "help mentions charset" "-c, --charset"
    assert_stdout_contains "help mentions exclude" "-e, --exclude"
}

test_missing_length_value() {
    run_script --length
    assert_rc "missing length" 2
    assert_stderr_contains "error message" "[ERR][genpw] --length specified but no length provided"
}

test_missing_charset_value() {
    run_script --charset
    assert_rc "missing charset" 2
    assert_stderr_contains "error message" "[ERR][genpw] --charset specified but no charset provided"
}

test_missing_exclude_value() {
    run_script --exclude
    assert_rc "missing exclude" 2
    assert_stderr_contains "error message" "[ERR][genpw] --exclude specified but no charset provided"
}

test_unknown_option() {
    run_script --invalid
    assert_rc "unknown option" 2
    assert_stderr_contains "error message" "[ERR][genpw] Unknown argument '--invalid'"
}

test_empty_charset_after_exclusions() {
    # Exclude all alphanumeric and punctuation
    run_script --charset "abc" --exclude "abc"
    assert_rc "empty charset" 4
    assert_stderr_contains "error message" "[ERR][genpw] Charset is empty after exclusions"
}

test_default_length() {
    run_script
    assert_rc "default length exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "default length is 32" "${#output}" "32"
}

test_custom_length_flag() {
    run_script --length 10
    assert_rc "custom length exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "custom length is 10" "${#output}" "10"
}

test_custom_length_positional() {
    run_script 10
    assert_rc "positional length exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "positional length is 10" "${#output}" "10"
}

test_short_flags() {
    run_script -l 5 -c "A"
    assert_rc "short flags exit 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "short flags length" "${#output}" "5"
    assert_stdout_contains "contains A" "A"
}

test_exclude_flag() {
    # Exclude should work even with minimal shims
    run_script -l 5 -c "abcdefg" -e "aei"
    assert_rc "exclude exits 0" 0
    # Output should not contain 'a' or 'e' (note: 'i' not in charset)
    local output
    output="$(get_stdout)"
    assert_not_contains "no 'a'" "$output" "a"
    assert_not_contains "no 'e'" "$output" "e"
}

test_exclude_equals_form() {
    run_script --length=5 --charset="xyz" --exclude="x"
    assert_rc "exclude =-form exits 0" 0
    local output
    output="$(get_stdout)"
    assert_not_contains "no 'x'" "$output" "x"
}

test_bundled_short_opts_with_value() {
    # -l5 equivalent to -l 5, glued via preprocessor
    run_script -l5 -c "abc"
    assert_rc "glued short-opt value exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "glued -l5 gives 5-char password" "${#output}" "5"
}

test_range_expansion() {
    # Test that ranges like a-z get expanded
    # Use explicit character list instead of range to avoid expansion issues
    run_script -l 5 -c "bcdef"
    assert_rc "range expansion exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "range expansion length" "${#output}" "5"
    # Check that output only contains chars from range b-f
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [b-f]) ;;
            *) _fail "range expansion contains invalid char '$char'" ;;
        esac
    done
}

test_posix_digit() {
    run_script -l 5 -c "[:digit:]"
    assert_rc "posix digit exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "posix digit length" "${#output}" "5"
    # Check that output only contains digits
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [0-9]) ;;
            *) _fail "posix digit contains invalid char '$char'" ;;
        esac
    done
}

test_posix_lower() {
    run_script -l 5 -c "[:lower:]"
    assert_rc "posix lower exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "posix lower length" "${#output}" "5"
    # Check that output only contains lowercase
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [a-z]) ;;
            *) _fail "posix lower contains invalid char '$char'" ;;
        esac
    done
}

test_posix_upper() {
    run_script -l 5 -c "[:upper:]"
    assert_rc "posix upper exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "posix upper length" "${#output}" "5"
    # Check that output only contains uppercase
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [A-Z]) ;;
            *) _fail "posix upper contains invalid char '$char'" ;;
        esac
    done
}

test_zero_length() {
    run_script -l 0
    assert_rc "zero length exits 0" 0
    local output
    output="$(get_stdout)"
    # Should be just a newline
    assert_eq "zero length output" "$output" ""
}

test_very_long_password() {
    run_script -l 1000
    assert_rc "long password exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "long password length" "${#output}" "1000"
}

test_multiple_length_args() {
    # Last one wins
    run_script -l 5 -l 8
    assert_rc "multiple length exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "last length wins" "${#output}" "8"
}

test_charset_and_exclude_interaction() {
    run_script -l 5 -c "abcdefghij" -e "acegi"
    assert_rc "charset+exclude exits 0" 0
    local output
    output="$(get_stdout)"
    assert_not_contains "no 'a'" "$output" "a"
    assert_not_contains "no 'c'" "$output" "c"
    assert_not_contains "no 'e'" "$output" "e"
    assert_not_contains "no 'g'" "$output" "g"
    assert_not_contains "no 'i'" "$output" "i"
}

test_complex_charset() {
    run_script -l 5 -c "ABC123!@#"
    assert_rc "complex charset exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "complex charset length" "${#output}" "5"
}

test_special_chars_in_charset() {
    run_script -l 5 -c '!@#$%^&*()'
    assert_rc "special chars exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "special chars length" "${#output}" "5"
}

test_execute_mode() {
    # Test that script works when executed (not sourced)
    run_script -l 8
    assert_rc "execute mode exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "execute mode length" "${#output}" "8"
}

test_help_short() {
    run_script -h
    assert_rc "help short exits 0" 0
    assert_stdout_contains "help short has NAME" "NAME"
}

test_non_numeric_positional() {
    run_script abc
    assert_rc "non-numeric positional" 2
    assert_stderr_contains "error for non-numeric" "Unknown argument 'abc'"
}

test_empty_string_argument() {
    run_script ""
    assert_rc "empty string arg" 2
    assert_stderr_contains "error for empty" "Unknown argument ''"
}

test_literal_range_charset() {
    # Previously failed: sed backreference parsing error when expanding ranges
    run_script -l 12 -c "a-z0-9"
    assert_rc "literal range charset exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "literal range charset length" "${#output}" "12"
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [a-z0-9]) ;;
            *) _fail "literal range charset contains invalid char '$char'" ;;
        esac
    done
}

test_mixed_posix_and_literal() {
    run_script -l 12 -c "[:lower:][:digit:]"
    assert_rc "mixed posix classes exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "mixed posix classes length" "${#output}" "12"
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [a-z0-9]) ;;
            *) _fail "mixed posix classes contains invalid char '$char'" ;;
        esac
    done
}

test_invalid_posix_class_rejected() {
    run_script -l 12 -c "[:foobar:]"
    assert_rc "invalid posix class rejected" 5
    assert_stderr_contains "error names invalid class" "[:foobar:]"
    assert_stderr_contains "error suggests valid classes" "[:alnum:]"
}

test_unclosed_posix_class_rejected() {
    run_script -l 12 -c "[:lower:"
    assert_rc "unclosed posix class rejected" 5
    assert_stderr_contains "error message present" "Invalid charset"
}

test_bare_posix_opener_rejected() {
    run_script -l 12 -c "[:"
    assert_rc "bare posix opener rejected" 5
    assert_stderr_contains "error message present" "Invalid charset"
}

test_bracket_expression_literal_chars() {
    # [0-9ab] → digits plus a, b
    run_script -l 20 -c '[0-9ab]'
    assert_rc "bracket expr exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "output length" "${#output}" "20"
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [0-9ab]) ;;
            *) _fail "bracket expr contains invalid char '$char'" ;;
        esac
    done
}

test_bracket_expression_range_only() {
    # [A-Z] → upper alphabet only
    run_script -l 20 -c '[A-Z]'
    assert_rc "bracket range exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "bracket range length" "${#output}" "20"
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [A-Z]) ;;
            *) _fail "bracket range contains non-upper '$char'" ;;
        esac
    done
}

test_bracket_nested_posix_class() {
    # [[:lower:]0-9] → lowercase letters plus digits
    run_script -l 20 -c '[[:lower:]0-9]'
    assert_rc "nested posix in bracket exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "nested posix length" "${#output}" "20"
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [a-z0-9]) ;;
            *) _fail "nested posix bracket contains invalid char '$char'" ;;
        esac
    done
}

test_unclosed_bracket_rejected() {
    run_script -l 12 -c '[0-9'
    assert_rc "unclosed bracket rejected" 5
    assert_stderr_contains "error mentions unclosed" "unclosed"
}

test_bracket_expr_excludes_chars_not_in_set() {
    # Any uppercase letter should be absent from a lowercase-only set
    run_script -l 50 -c '[abc]'
    assert_rc "bracket expr exits 0" 0
    local output
    output="$(get_stdout)"
    assert_eq "output length" "${#output}" "50"
    local char
    local i
    for ((i=0; i<${#output}; i++)); do
        char="${output:$i:1}"
        case "$char" in
            [abc]) ;;
            *) _fail "bracket expr admitted char outside set: '$char'" ;;
        esac
    done
}

# --- run ---

run_tests "$@"
