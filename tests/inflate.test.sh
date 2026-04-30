#!/bin/bash
# inflate.test.sh - Tests for inflate
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../inflate"

# --- helpers ---

get_curl_args() { cat "$TEST_DIR/curl.args" 2>/dev/null; }

# --- shims ---

write_shims() {
    # curl shim: returns different responses based on URL pattern
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/curl.args"

# Check if this is the initial page load (no query params) or the calculator request
has_query=0
for arg in "$@"; do
    case "$arg" in
        *cost1=*) has_query=1; break ;;
    esac
done

if [ "$has_query" -eq 0 ]; then
    # Initial page load - return HTML with recent year/month selector
    cat <<'HTML'
<select name="year2" id="year2">
<option value="202401">January 2024</option>
<option value="202402">February 2024</option>
<option value="202403">March 2024</option>
<option value="202404">April 2024</option>
<option value="202405">May 2024</option>
<option value="202406" selected="selected">June 2024</option>
</select>
HTML
else
    # Calculator request - check for error conditions
    for arg in "$@"; do
        case "$arg" in
            *cost1=0.00*)
                # FAIL gets formatted to 0.00 by printf - simulate failure
                cat <<'HTML'
<div class="error">Invalid input</div>
HTML
                exit 0
                ;;
            *year1=1899*)
                # Return HTML without id="answer" to simulate invalid year
                cat <<'HTML'
<div class="error">Year out of range</div>
HTML
                exit 0
                ;;
        esac
    done
    # Return successful result with answer
    cat <<'HTML'
<div id="answer">The result is $1202.20</div>
HTML
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"
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
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "-h shows help" "NAME"
}

test_missing_amount() {
    run_script
    assert_rc "no args returns 1" 1
    assert_err_contains "error message" "amount is required"
}

test_missing_year() {
    run_script 150
    assert_rc "missing year returns 1" 1
    assert_err_contains "error message" "year is required"
}

test_basic_conversion() {
    run_script 150 1970 9
    assert_rc "basic conversion exits 0" 0
    assert_stdout_contains "result on stdout" "1202.20"
    assert_err_contains "summary on stderr" "\$150.00: Sep 1970 -> Jun 2024"
}

test_default_month() {
    run_script 100 1980
    assert_rc "default month exits 0" 0
    assert_err_contains "defaults to January" "Jan 1980"
}

test_amount_formatting() {
    run_script 150.5 1970 9
    assert_rc "decimal amount exits 0" 0
    assert_err_contains "formats amount" "\$150.50"
}

test_single_digit_month() {
    run_script 100 1980 3
    assert_rc "single digit month exits 0" 0
    assert_err_contains "formats month" "Mar 1980"
}

test_double_digit_month() {
    run_script 100 1980 12
    assert_rc "double digit month exits 0" 0
    assert_err_contains "formats month" "Dec 1980"
}

test_month_with_leading_zero() {
    run_script 100 1980 03
    assert_rc "month with leading zero exits 0" 0
    assert_err_contains "formats month" "Mar 1980"
    assert_contains "curl gets zero-padded month" "$(get_curl_args)" "year1=198003"
}

test_curl_called_twice() {
    run_script 150 1970 9
    assert_rc "conversion exits 0" 0
    # We can't easily count curl invocations with a simple shim
    # but we can verify the final call had the expected parameters
    assert_contains "curl gets amount" "$(get_curl_args)" "cost1=150.00"
    assert_contains "curl gets year1" "$(get_curl_args)" "year1=197009"
    assert_contains "curl gets year2" "$(get_curl_args)" "year2=202406"
}

test_failed_conversion() {
    run_script FAIL 1970 9
    assert_rc "failed conversion returns 1" 1
    assert_err_contains "error message" "Failed to convert"
}

test_invalid_historical_year() {
    run_script 100 1899 1
    assert_rc "invalid year returns 1" 1
    assert_err_contains "error about conversion" "Failed to convert"
}

test_curl_silent_flags() {
    run_script 150 1970 9
    assert_rc "exits 0" 0
    assert_contains "curl uses -f" "$(get_curl_args)" "-fsS"
}

test_result_extracts_number() {
    run_script 150 1970 9
    assert_rc "exits 0" 0
    # Result should be just the number, not the full HTML
    assert_stdout_contains "stdout has number" "1202.20"
    assert_stdout_not_contains "no HTML on stdout" "<div"
}

# --- run ---

run_tests "$@"
