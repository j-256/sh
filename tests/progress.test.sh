#!/bin/bash
# progress.test.sh - Tests for progress
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../progress"

# --- helpers ---

# Strip ANSI escape sequences for testing
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# --- shims ---

write_shims() {
    # stty shim: return deterministic terminal size
    cat > "$SHIM_DIR/stty" <<'SHIM'
#!/bin/bash
case "$*" in
    *size*) echo "24 80" ;;
    *) exit 1 ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/stty"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has CURRENT" "CURRENT"
    assert_stdout_contains "help has MAX" "MAX"
    assert_stdout_contains "help has EXAMPLES" "EXAMPLES"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_missing_current() {
    run_script
    assert_rc "missing current" 2
    assert_err_contains "missing param error" "Missing required positional parameter"
    assert_err_contains "help hint" "Run \`progress -h\` for usage"
}

test_missing_max() {
    run_script 50
    assert_rc "missing max" 2
    assert_err_contains "missing param error" "Missing required positional parameter"
}

test_current_not_integer() {
    run_script abc 100
    assert_rc "current not int" 2
    assert_err_contains "current int error" "current must be an integer"
}

test_max_not_integer() {
    run_script 50 abc
    assert_rc "max not int" 2
    assert_err_contains "max int error" "max must be a positive integer"
}

test_max_zero() {
    run_script 0 0
    assert_rc "max zero" 2
    assert_err_contains "max zero error" "max must be > 0"
}

test_max_negative() {
    run_script 50 -10
    assert_rc "max negative" 2
    assert_err_contains "max negative error" "max must be a positive integer"
}

test_width_missing_value() {
    run_script 50 100 --width
    assert_rc "width missing value" 2
    assert_err_contains "width missing error" "Missing value for width option"
}

test_width_zero() {
    run_script --width 0 50 100
    assert_rc "width zero" 2
    assert_err_contains "width zero error" "width must be > 0"
}

test_width_not_integer() {
    run_script --width abc 50 100
    assert_rc "width not int" 2
    assert_err_contains "width not int error" "width must be a positive integer"
}

test_progress_char_missing_value() {
    run_script 50 100 --progress-char
    assert_rc "progress-char missing" 2
    assert_err_contains "progress-char error" "Missing value for progress character option"
}

test_remaining_char_missing_value() {
    run_script 50 100 --remaining-char
    assert_rc "remaining-char missing" 2
    assert_err_contains "remaining-char error" "Missing value for remaining character option"
}

test_too_many_args() {
    run_script 50 100 150
    assert_rc "too many args" 2
    assert_err_contains "too many error" "Too many positional arguments"
}

test_basic_completion_non_tty() {
    # Non-TTY context: only output at completion
    run_script 100 100
    assert_rc "completion non-tty" 0
    local out
    out="$(get_stderr)"
    assert_contains "has bar" "$out" "["
    assert_contains "has percentage" "$out" "100%"
    assert_contains "has closing bracket" "$out" "]"
}

test_partial_progress_non_tty() {
    # Non-TTY context: no output for partial progress
    run_script 50 100
    assert_rc "partial non-tty" 0
    assert_eq "no output" "$(get_stderr)" ""
}

test_zero_progress_non_tty() {
    run_script 0 100
    assert_rc "zero non-tty" 0
    assert_eq "no output at zero" "$(get_stderr)" ""
}

test_50_percent_completion() {
    run_script 50 100
    assert_rc "50 percent" 0
}

test_75_percent_completion() {
    run_script 75 100
    assert_rc "75 percent" 0
}

test_clamp_current_negative() {
    run_script -10 100
    assert_rc "clamp negative" 0
}

test_clamp_current_above_max() {
    run_script 150 100
    assert_rc "clamp above max" 0
}

test_custom_width() {
    run_script --width 20 100 100
    assert_rc "custom width" 0
    local out
    out="$(get_stderr)"
    assert_contains "has output" "$out" "100%"
}

test_custom_progress_char() {
    run_script --progress-char "=" 100 100
    assert_rc "custom progress char" 0
    local out
    out="$(get_stderr)"
    assert_contains "has equals" "$out" "="
}

test_custom_remaining_char() {
    run_script --remaining-char "." 50 100
    assert_rc "custom remaining char" 0
}

test_short_width_option() {
    run_script -w 30 100 100
    assert_rc "short width" 0
}

test_short_progress_char_option() {
    run_script -p "+" 100 100
    assert_rc "short progress char" 0
}

test_short_remaining_char_option() {
    run_script -r "_" 50 100
    assert_rc "short remaining char" 0
}

test_stdout_mode() {
    run_script --stdout 100 100
    assert_rc "stdout mode" 0
    local out
    out="$(get_stdout)"
    assert_contains "stdout has output" "$out" "100%"
}

test_stderr_mode() {
    run_script --stderr 100 100
    assert_rc "stderr mode" 0
    local out
    out="$(get_stderr)"
    assert_contains "stderr has output" "$out" "100%"
}

test_current_negative_allowed() {
    run_script -5 100
    assert_rc "negative current ok" 0
}

test_options_before_positionals() {
    run_script -w 25 -p "*" -r " " 80 100
    assert_rc "options first" 0
}

test_options_mixed_with_positionals() {
    run_script -w 25 50 -p "=" 100
    assert_rc "mixed options" 0
}

test_one_of_one() {
    run_script 1 1
    assert_rc "one of one" 0
    local out
    out="$(get_stderr)"
    assert_contains "shows 100%" "$out" "100%"
}

test_large_numbers() {
    run_script 999999 1000000
    assert_rc "large numbers" 0
}

test_same_current_and_max() {
    run_script 42 42
    assert_rc "same values" 0
    local out
    out="$(get_stderr)"
    assert_contains "100% when equal" "$out" "100%"
}

test_width_one() {
    run_script --width 1 100 100
    assert_rc "width one" 0
    local out
    out="$(get_stderr)"
    assert_contains "minimal width works" "$out" "100%"
}

test_negative_current_clamped_to_zero() {
    run_script -999 100
    assert_rc "large negative clamped" 0
}

test_current_exceeds_max_clamped() {
    run_script 9999 100
    assert_rc "large excess clamped" 0
}

# --- run ---

run_tests "$@"
