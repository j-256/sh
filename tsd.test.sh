#!/bin/bash
# tsd.test.sh - Tests for tsd
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/tsd"

# --- shims ---

write_shims() {
    # date shim: return deterministic output based on timestamp
    # TZ is set as environment variable, format is in args
    # Input timestamp: 1609477200 (2021-01-01 00:00:00 EST / 05:00:00 UTC)
    cat > "$SHIM_DIR/date" <<'SHIM'
#!/bin/bash
# Extract timestamp from -r argument
ts=""
for arg in "$@"; do
    if [ "$prev" = "-r" ]; then
        ts="$arg"
        break
    fi
    prev="$arg"
done

# Determine output format based on TZ and format string
case "$ts" in
    1609477200)
        case "$TZ" in
            UTC)
                printf '%s\n' "2021-01-01T05:00:00Z"
                ;;
            *)
                printf '%s\n' "2021-01-01 00:00:00 EST (-0500)"
                ;;
        esac
        ;;
    1234567890)
        case "$TZ" in
            UTC)
                printf '%s\n' "2009-02-13T23:31:30Z"
                ;;
            *)
                printf '%s\n' "2009-02-13 18:31:30 EST (-0500)"
                ;;
        esac
        ;;
    0|0000000000)
        case "$TZ" in
            UTC)
                printf '%s\n' "1970-01-01T00:00:00Z"
                ;;
            *)
                printf '%s\n' "1969-12-31 19:00:00 EST (-0500)"
                ;;
        esac
        ;;
    1735689600)
        case "$TZ" in
            UTC)
                printf '%s\n' "2025-01-01T00:00:00Z"
                ;;
            *)
                printf '%s\n' "2024-12-31 19:00:00 EST (-0500)"
                ;;
        esac
        ;;
    *)
        printf 'date: unknown timestamp: %s (TZ=%s)\n' "$ts" "$TZ" >&2
        exit 1
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/date"

    # Fake /etc/localtime for TSD_LOCALTIME
    export TSD_LOCALTIME="$TEST_DIR/localtime"
    : > "$TSD_LOCALTIME"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has Usage" "Usage:"
    assert_stdout_contains "help has Options" "Options:"
    assert_stdout_contains "help has Examples" "Examples:"
}

test_no_input() {
    run_script
    assert_rc "no input exits 1" 1
    assert_err_contains "no input error" "Error: No input provided."
}

test_multiple_positional() {
    run_script 1234 5678
    assert_rc "multiple positional exits 1" 1
    assert_err_contains "multiple positional error" "Unknown option or multiple positional arguments: 5678"
}

test_multiple_units() {
    run_script 1234 -s -m
    assert_rc "multiple units exits 1" 1
    assert_err_contains "multiple units error" "Unit is already set to s. Cannot specify multiple units."
}

test_unknown_option() {
    run_script 1234 --invalid
    assert_rc "unknown option exits 1" 1
    assert_err_contains "unknown option error" "Unknown option or multiple positional arguments: --invalid"
}

# --- timestamp tests ---

test_timestamp_10_digits() {
    run_script 1609477200
    assert_rc "10 digit timestamp" 0
    assert_stdout_contains "UTC datetime" "2021-01-01T05:00:00Z"
    assert_stdout_contains "local datetime" "2021-01-01 00:00:00 EST (GMT-5)"
}

test_timestamp_13_digits_milliseconds() {
    run_script 1609477200123
    assert_rc "13 digit timestamp" 0
    assert_stdout_contains "UTC with ms" "2021-01-01T05:00:00.123Z"
    assert_stdout_contains "local with ms" "2021-01-01 00:00:00.123 EST (GMT-5)"
}

test_timestamp_16_digits_microseconds() {
    run_script 1609477200123456
    assert_rc "16 digit timestamp" 0
    assert_stdout_contains "UTC with us" "2021-01-01T05:00:00.123456Z"
    assert_stdout_contains "local with us" "2021-01-01 00:00:00.123456 EST (GMT-5)"
}

test_timestamp_19_digits_nanoseconds() {
    run_script 1609477200123456789
    assert_rc "19 digit timestamp" 0
    assert_stdout_contains "UTC with ns" "2021-01-01T05:00:00.123456789Z"
    assert_stdout_contains "local with ns" "2021-01-01 00:00:00.123456789 EST (GMT-5)"
}

test_timestamp_epoch_zero() {
    run_script 0000000000
    assert_rc "epoch zero" 0
    assert_stdout_contains "epoch UTC" "1970-01-01T00:00:00Z"
    assert_stdout_contains "epoch local" "1969-12-31 19:00:00 EST (GMT-5)"
}

test_timestamp_with_seconds_flag() {
    run_script 1609477200 --seconds
    assert_rc "timestamp with -s" 0
    assert_stdout_contains "still timestamp" "2021-01-01T05:00:00Z"
}

test_timestamp_override_with_duration_flag() {
    run_script 1609477200 --duration
    assert_rc "timestamp overridden" 0
    assert_stdout_contains "duration output" "18628d"
    assert_stdout_not_contains "not a timestamp" "2021-01-01"
}

# --- duration tests ---

test_duration_seconds_simple() {
    run_script 1800
    assert_rc "simple seconds" 0
    assert_eq "30 minutes" "$(get_stdout)" "30m"
}

test_duration_seconds_compound() {
    run_script 7238
    assert_rc "compound seconds" 0
    assert_eq "2h 0m 38s" "$(get_stdout)" "2h 0m 38s"
}

test_duration_days() {
    run_script 172800
    assert_rc "exact days" 0
    assert_eq "2 days" "$(get_stdout)" "2d"
}

test_duration_days_with_seconds() {
    run_script 172805
    assert_rc "days with seconds" 0
    assert_eq "2d 0h 0m 5s" "$(get_stdout)" "2d 0h 0m 5s"
}

test_duration_milliseconds_flag() {
    run_script 1800 -m
    assert_rc "ms flag" 0
    assert_eq "1s 800ms" "$(get_stdout)" "1s 800ms"
}

test_duration_milliseconds_complex() {
    run_script 135180 --milliseconds
    assert_rc "complex ms" 0
    assert_eq "2m 15s 180ms" "$(get_stdout)" "2m 15s 180ms"
}

test_duration_microseconds() {
    run_script 1234567 --micro
    assert_rc "microseconds" 0
    assert_eq "1s 234ms 567us" "$(get_stdout)" "1s 234ms 567us"
}

test_duration_nanoseconds() {
    run_script 1234567890 --nano
    assert_rc "nanoseconds" 0
    assert_eq "1s 234ms 567us 890ns" "$(get_stdout)" "1s 234ms 567us 890ns"
}

test_duration_zero_padding() {
    run_script 3661
    assert_rc "zero padding" 0
    assert_eq "1h 1m 1s" "$(get_stdout)" "1h 1m 1s"
}

test_duration_only_hours() {
    run_script 7200
    assert_rc "only hours" 0
    assert_eq "2h" "$(get_stdout)" "2h"
}

test_duration_trailing_zeros_omitted() {
    run_script 3600000 -m
    assert_rc "trailing zeros" 0
    assert_eq "1h" "$(get_stdout)" "1h"
}

test_duration_middle_zeros_included() {
    run_script 86405
    assert_rc "middle zeros" 0
    assert_eq "1d 0h 0m 5s" "$(get_stdout)" "1d 0h 0m 5s"
}

test_duration_single_millisecond() {
    run_script 1 -m
    assert_rc "1ms" 0
    assert_eq "1ms" "$(get_stdout)" "1ms"
}

test_duration_single_second() {
    run_script 1
    assert_rc "1s" 0
    assert_eq "1s" "$(get_stdout)" "1s"
}

test_duration_large_value() {
    run_script 31536000
    assert_rc "1 year in seconds" 0
    assert_eq "365d" "$(get_stdout)" "365d"
}

# --- unit inference tests ---

test_infer_seconds_9_digits() {
    run_script 123456789
    assert_rc "9 digits inferred as seconds" 0
    assert_stdout_contains "duration output" "d"
}

test_infer_milliseconds_11_digits() {
    run_script 12345678901
    assert_rc "11 digits inferred as ms" 0
    assert_stdout_contains "duration output" "d"
}

test_infer_microseconds_14_digits() {
    run_script 12345678901234
    assert_rc "14 digits inferred as us" 0
    assert_stdout_contains "duration output" "d"
}

test_infer_nanoseconds_17_digits() {
    run_script 12345678901234567
    assert_rc "17 digits inferred as ns" 0
    assert_stdout_contains "duration output" "d"
}

# --- option order tests ---

test_option_before_input() {
    run_script -m 1800
    assert_rc "option before input" 0
    assert_eq "option order" "$(get_stdout)" "1s 800ms"
}

test_option_after_input() {
    run_script 1800 -m
    assert_rc "option after input" 0
    assert_eq "option order" "$(get_stdout)" "1s 800ms"
}

test_duration_flag_before_input() {
    run_script --duration 1609477200
    assert_rc "duration flag first" 0
    assert_stdout_contains "is duration" "18628d"
}

# --- edge cases ---

test_timestamp_all_zeros_fractional() {
    run_script 1609477200000
    assert_rc "timestamp with .000" 0
    assert_stdout_contains "zeros included" "2021-01-01T05:00:00.000Z"
}

test_duration_zero_middle_units() {
    run_script 90005
    assert_rc "zero middle units" 0
    assert_eq "1d 1h 0m 5s" "$(get_stdout)" "1d 1h 0m 5s"
}

test_timestamp_future() {
    run_script 1735689600
    assert_rc "future timestamp" 0
    assert_stdout_contains "2025 timestamp" "2025-01-01T00:00:00Z"
}

# --- run ---

run_tests "$@"
