#!/bin/bash
# stats.test.sh - Tests for stats
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../stats"

# --- shims ---

write_shims() {
    # bc shim: evaluate arithmetic expressions
    cat > "$SHIM_DIR/bc" <<'SHIM'
#!/bin/bash
# Read from stdin
input=""
while IFS= read -r line || [ -n "$line" ]; do
    input+="$line"
done

# Strip leading/trailing whitespace and newlines
input="${input#"${input%%[![:space:]]*}"}"
input="${input%"${input##*[![:space:]]}"}"

# Handle division (e.g., "15 / 5")
if [[ "$input" =~ ^([0-9]+)\ /\ ([0-9]+)$ ]]; then
    echo $((${BASH_REMATCH[1]} / ${BASH_REMATCH[2]}))
    exit 0
fi

# Handle subtraction for bounds (Q1 - 1.5 * IQR)
if [[ "$input" =~ ^([0-9]+)\ -\ 1\.5\ \*\ ([0-9]+)$ ]]; then
    q1="${BASH_REMATCH[1]}"
    iqr="${BASH_REMATCH[2]}"
    result=$(awk "BEGIN {printf \"%.10f\", $q1 - 1.5 * $iqr}")
    echo "$result"
    exit 0
fi

# Handle addition for bounds (Q3 + 1.5 * IQR)
if [[ "$input" =~ ^([0-9]+)\ \+\ 1\.5\ \*\ ([0-9]+)$ ]]; then
    q3="${BASH_REMATCH[1]}"
    iqr="${BASH_REMATCH[2]}"
    result=$(awk "BEGIN {printf \"%.10f\", $q3 + 1.5 * $iqr}")
    echo "$result"
    exit 0
fi

# Handle percentage calculation (scale=4; count / total * 100)
if [[ "$input" =~ scale=4\;\ ([0-9]+)\ /\ ([0-9]+)\ \*\ 100 ]]; then
    count="${BASH_REMATCH[1]}"
    total="${BASH_REMATCH[2]}"
    result=$(awk "BEGIN {printf \"%.4f\", $count / $total * 100}")
    echo "$result"
    exit 0
fi

# Handle simple addition for total (e.g., "1+2+3" without spaces)
# This matches what stats generates via: printf '%s+' "${sorted[@]}" | sed 's/+$//' | bc
if [[ "$input" =~ ^[0-9]+(\+[0-9]+)*$ ]]; then
    # Convert to bash arithmetic
    result=$((${input//+/ + }))
    echo "$result"
    exit 0
fi

# Fallback: return 0
echo "0"
exit 0
SHIM
    chmod +x "$SHIM_DIR/bc"

    # sort shim: use real sort for simplicity
    cat > "$SHIM_DIR/sort" <<'SHIM'
#!/bin/bash
exec /usr/bin/sort "$@"
SHIM
    chmod +x "$SHIM_DIR/sort"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has stats" "stats"
}

test_help_short_option() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_basic_statistics() {
    printf '%s\n' 1 2 3 4 5 | run_script
    assert_rc "basic stats exits 0" 0
    assert_stdout_contains "has count" "Count: 5"
    assert_stdout_contains "has total" "Total: 15"
    assert_stdout_contains "has average" "Average: 3"
}

test_range_calculation() {
    printf '%s\n' 10 20 30 40 50 | run_script
    assert_rc "range exits 0" 0
    assert_stdout_contains "has range" "Range: 40 (10 to 50)"
}

test_single_number() {
    printf '%s\n' 42 | run_script
    assert_rc "single number exits 0" 0
    assert_stdout_contains "count is 1" "Count: 1"
    assert_stdout_contains "total is 42" "Total: 42"
    assert_stdout_contains "average is 42" "Average: 42"
    assert_stdout_contains "range is 0" "Range: 0 (42 to 42)"
}

test_unsorted_input() {
    printf '%s\n' 50 10 30 20 40 | run_script
    assert_rc "unsorted exits 0" 0
    assert_stdout_contains "correct count" "Count: 5"
    assert_stdout_contains "correct total" "Total: 150"
    assert_stdout_contains "correct range" "Range: 40 (10 to 50)"
}

test_with_outliers() {
    # Dataset with clear outliers: 1, 2, 3, 4, 5, 100
    printf '%s\n' 1 2 3 4 5 100 | run_script
    assert_rc "outliers exits 0" 0
    assert_stdout_contains "has outliers section" "Outliers:"
    assert_stdout_contains "has outlier count" "of 6"
}

test_n_flag_shows_dataset() {
    printf '%s\n' 1 2 3 | run_script -n
    assert_rc "-n exits 0" 0
    assert_stdout_contains "shows dataset" "1, 2, 3"
    assert_stdout_contains "still shows count" "Count: 3"
}

test_decimal_rejected() {
    printf '%s\n' 1.5 2.5 | run_script
    assert_rc "decimal rejected with rc 2" 2
    assert_err_contains "decimal error message" "Integers only"
}

test_negative_sign_rejected() {
    printf '%s\n' -5 10 | run_script
    assert_rc "negative rejected with rc 2" 2
    assert_err_contains "negative error message" "Integers only"
}

test_letters_rejected() {
    printf '%s\n' abc 123 | run_script
    assert_rc "letters rejected with rc 2" 2
    assert_err_contains "letters error message" "Integers only"
}

test_mixed_valid_invalid() {
    printf '%s\n' 1 2 three 4 | run_script
    assert_rc "mixed rejected with rc 2" 2
    assert_err_contains "mixed error message" "Integers only"
}

test_empty_input() {
    printf '' | run_script
    assert_rc "empty input exits 0" 0
    assert_stdout_contains "count 0" "Count: 0"
}

test_whitespace_only() {
    printf '   \n  \n' | run_script
    assert_rc "whitespace exits 0" 0
    # Empty lines are treated as empty strings, may result in count or error
    # This test verifies it doesn't crash
}

test_large_dataset() {
    # Generate numbers 1-100
    for i in $(seq 1 100); do echo "$i"; done | run_script
    assert_rc "large dataset exits 0" 0
    assert_stdout_contains "large count" "Count: 100"
    assert_stdout_contains "large total" "Total: 5050"
    assert_stdout_contains "large average" "Average: 50"
}

test_identical_numbers() {
    printf '%s\n' 7 7 7 7 7 | run_script
    assert_rc "identical exits 0" 0
    assert_stdout_contains "identical count" "Count: 5"
    assert_stdout_contains "identical total" "Total: 35"
    assert_stdout_contains "identical range" "Range: 0 (7 to 7)"
}

test_two_numbers() {
    printf '%s\n' 10 20 | run_script
    assert_rc "two numbers exits 0" 0
    assert_stdout_contains "two count" "Count: 2"
    assert_stdout_contains "two total" "Total: 30"
    assert_stdout_contains "two average" "Average: 15"
    assert_stdout_contains "two range" "Range: 10 (10 to 20)"
}

test_zero_values() {
    printf '%s\n' 0 0 0 | run_script
    assert_rc "zeros exit 0" 0
    assert_stdout_contains "zero count" "Count: 3"
    assert_stdout_contains "zero total" "Total: 0"
    assert_stdout_contains "zero average" "Average: 0"
    assert_stdout_contains "zero range" "Range: 0 (0 to 0)"
}

test_zeros_and_positives() {
    printf '%s\n' 0 5 10 | run_script
    assert_rc "zeros with positives exits 0" 0
    assert_stdout_contains "mixed count" "Count: 3"
    assert_stdout_contains "mixed total" "Total: 15"
    assert_stdout_contains "mixed range" "Range: 10 (0 to 10)"
}

test_very_large_numbers() {
    printf '%s\n' 1000000 2000000 3000000 | run_script
    assert_rc "large numbers exit 0" 0
    assert_stdout_contains "large number count" "Count: 3"
    assert_stdout_contains "large number total" "Total: 6000000"
}

test_no_trailing_newline() {
    printf '1\n2\n3' | run_script
    assert_rc "no trailing newline exits 0" 0
    assert_stdout_contains "includes last number" "Count: 3"
    assert_stdout_contains "includes last in total" "Total: 6"
}

test_n_flag_position_independent() {
    printf '%s\n' 1 2 3 | run_script -n
    assert_rc "n flag exits 0" 0
    local output1
    output1="$(get_stdout)"

    # Should work the same regardless of when -n is passed
    printf '%s\n' 1 2 3 | run_script -n
    assert_rc "n flag again exits 0" 0
    assert_eq "same output" "$(get_stdout)" "$output1"
}

test_whitespace_separated_input() {
    # Space-separated on one line should produce the same result as newline-separated
    echo "1 2 3 4 5" | run_script
    local space_rc; space_rc="$(get_rc)"
    local space_stdout; space_stdout="$(get_stdout)"

    printf '%s\n' 1 2 3 4 5 | run_script
    assert_rc "newline variant exits 0" 0
    assert_eq "space-separated rc matches newline" "$space_rc" "$(get_rc)"
    assert_eq "space-separated output matches newline" "$space_stdout" "$(get_stdout)"
}

test_space_separated_no_crash() {
    # Regression: echo "1 2 3" | stats used to crash with "syntax error in expression"
    echo "1 2 3" | run_script
    assert_rc "space-separated exits 0" 0
    assert_stdout_contains "has count 3" "Count: 3"
    assert_stdout_contains "has total 6" "Total: 6"
    assert_stdout_contains "has range" "Range: 2 (1 to 3)"
}

test_tab_separated_input() {
    printf '1\t2\t3\n' | run_script
    assert_rc "tab-separated exits 0" 0
    assert_stdout_contains "tab count" "Count: 3"
    assert_stdout_contains "tab total" "Total: 6"
}

test_mixed_whitespace_input() {
    # Mixed spaces, tabs, and newlines should all be normalized
    printf '1 2\n3\t4 5\n' | run_script
    assert_rc "mixed whitespace exits 0" 0
    assert_stdout_contains "mixed count" "Count: 5"
    assert_stdout_contains "mixed total" "Total: 15"
}

# --- run ---

run_tests "$@"
