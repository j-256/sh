#!/bin/bash
# unbak.test.sh - Tests for unbak
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../unbak"

# --- helpers ---

get_mv_log() { cat "$TEST_DIR/mv.log" 2>/dev/null; }

# --- shims ---

write_shims() {
    # mv shim: log arguments and actually perform the move for chaining to work
    cat > "$SHIM_DIR/mv" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/mv.log"
printf 'mv' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
# Call the real mv command by using full path
if [ -e "$1" ] && [ ! -e "$2" ]; then
    /bin/mv "$1" "$2"
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/mv"

    # tput shim: return empty string for test environment
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
}

test_help_short() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_no_args() {
    run_script
    assert_rc "no args shows help" 0
    assert_stdout_contains "no args has NAME" "NAME"
}

test_illegal_option() {
    run_script -x
    assert_rc "illegal option" 2
    assert_err_contains "illegal option message" "Unknown argument"
}

test_single_backup() {
    touch "$TEST_DIR/file.txt.bak"
    run_script "$TEST_DIR/file.txt.bak"
    assert_rc "single backup" 0
    assert_contains "mv called" "$(get_mv_log)" "mv $TEST_DIR/file.txt.bak $TEST_DIR/file.txt"
}

test_file_not_found() {
    run_script "$TEST_DIR/nosuchfile.bak"
    assert_rc "file not found" 1
    assert_err_contains "no such file error" "No such file"
}

test_destination_exists() {
    touch "$TEST_DIR/file.txt.bak"
    touch "$TEST_DIR/file.txt"
    run_script "$TEST_DIR/file.txt.bak"
    assert_rc "destination exists" 1
    assert_err_contains "already exists error" "File already exists, skipping"
}

test_chained_backup() {
    touch "$TEST_DIR/file.txt.bak.bak.bak"
    run_script "$TEST_DIR/file.txt.bak.bak.bak"
    assert_rc "chained backup" 0
    assert_contains "moves .bak.bak.bak" "$(get_mv_log)" "mv $TEST_DIR/file.txt.bak.bak.bak $TEST_DIR/file.txt.bak.bak"
}

test_chained_intermediate_collision() {
    touch "$TEST_DIR/file.txt.bak.bak"
    touch "$TEST_DIR/file.txt.bak"
    run_script "$TEST_DIR/file.txt.bak.bak"
    assert_rc "intermediate collision" 1
    assert_err_contains "intermediate exists error" "File already exists, skipping"
}

test_final_destination_exists() {
    touch "$TEST_DIR/file.txt.bak"
    touch "$TEST_DIR/file.txt"
    run_script "$TEST_DIR/file.txt.bak"
    assert_rc "final destination exists" 1
    assert_err_contains "final destination exists error" "File already exists, skipping"
}

test_verbose() {
    touch "$TEST_DIR/file.txt.bak"
    run_script -v "$TEST_DIR/file.txt.bak"
    assert_rc "verbose" 0
    assert_stdout_contains "verbose shows move" "Moving:"
}

test_verbose_long() {
    touch "$TEST_DIR/file.txt.bak"
    run_script --verbose "$TEST_DIR/file.txt.bak"
    assert_rc "verbose long" 0
    assert_stdout_contains "verbose long shows move" "Moving:"
}

test_dry_run() {
    touch "$TEST_DIR/file.txt.bak"
    run_script -n "$TEST_DIR/file.txt.bak"
    assert_rc "dry run" 0
    assert_stdout_contains "dry run shows would move" "Would move:"
}

test_dry_run_long() {
    touch "$TEST_DIR/file.txt.bak"
    run_script --dry-run "$TEST_DIR/file.txt.bak"
    assert_rc "dry run long" 0
    assert_stdout_contains "dry run long shows would move" "Would move:"
}

test_verbose_and_dry_run() {
    touch "$TEST_DIR/file.txt.bak"
    run_script -v -n "$TEST_DIR/file.txt.bak"
    assert_rc "verbose and dry run" 0
    assert_stdout_contains "verbose + dry run shows would move" "Would move:"
}

test_bundled_short_opts() {
    touch "$TEST_DIR/bundle.txt.bak"
    run_script -vn "$TEST_DIR/bundle.txt.bak"
    assert_rc "bundled -vn exits 0" 0
    assert_stdout_contains "bundled verbose active" "Would move:"
}

test_bundled_short_opts_reversed() {
    touch "$TEST_DIR/bundle2.txt.bak"
    run_script -nv "$TEST_DIR/bundle2.txt.bak"
    assert_rc "bundled -nv exits 0" 0
    assert_stdout_contains "reversed bundle still verbose" "Would move:"
}

test_multiple_files() {
    touch "$TEST_DIR/file1.txt.bak"
    touch "$TEST_DIR/file2.txt.bak"
    run_script "$TEST_DIR/file1.txt.bak" "$TEST_DIR/file2.txt.bak"
    assert_rc "multiple files" 0
    local log
    log="$(get_mv_log)"
    assert_contains "moves file1" "$log" "mv $TEST_DIR/file1.txt.bak $TEST_DIR/file1.txt"
    assert_contains "moves file2" "$log" "mv $TEST_DIR/file2.txt.bak $TEST_DIR/file2.txt"
}

test_multiple_files_one_fails() {
    touch "$TEST_DIR/file1.txt.bak"
    touch "$TEST_DIR/file2.txt.bak"
    touch "$TEST_DIR/file2.txt"
    run_script "$TEST_DIR/file1.txt.bak" "$TEST_DIR/file2.txt.bak"
    # When any file fails, unbak returns non-zero
    # But it continues processing remaining files
    assert_rc "multiple files one fails returns 1" 1
    local log
    log="$(get_mv_log)"
    assert_contains "moves file1" "$log" "mv $TEST_DIR/file1.txt.bak $TEST_DIR/file1.txt"
    assert_err_contains "file2 error" "File already exists, skipping"
}

test_double_dash() {
    touch "$TEST_DIR/file.txt.bak"
    run_script -- "$TEST_DIR/file.txt.bak"
    assert_rc "double dash" 0
    assert_contains "double dash moves" "$(get_mv_log)" "mv $TEST_DIR/file.txt.bak $TEST_DIR/file.txt"
}

test_double_dash_with_option_like_name() {
    touch "$TEST_DIR/-v.bak"
    run_script -- "$TEST_DIR/-v.bak"
    assert_rc "double dash with -v filename" 0
    assert_contains "double dash protects -v name" "$(get_mv_log)" "mv $TEST_DIR/-v.bak $TEST_DIR/-v"
}

test_stdin_single() {
    touch "$TEST_DIR/file.txt.bak"
    echo "$TEST_DIR/file.txt.bak" | run_script
    assert_rc "stdin single" 0
    assert_contains "stdin moves" "$(get_mv_log)" "mv $TEST_DIR/file.txt.bak $TEST_DIR/file.txt"
}

test_stdin_multiple() {
    touch "$TEST_DIR/file1.txt.bak"
    touch "$TEST_DIR/file2.txt.bak"
    printf '%s\n%s\n' "$TEST_DIR/file1.txt.bak" "$TEST_DIR/file2.txt.bak" | run_script
    assert_rc "stdin multiple" 0
    local log
    log="$(get_mv_log)"
    assert_contains "stdin moves file1" "$log" "mv $TEST_DIR/file1.txt.bak $TEST_DIR/file1.txt"
    assert_contains "stdin moves file2" "$log" "mv $TEST_DIR/file2.txt.bak $TEST_DIR/file2.txt"
}

test_stdin_and_args() {
    touch "$TEST_DIR/file1.txt.bak"
    touch "$TEST_DIR/file2.txt.bak"
    echo "$TEST_DIR/file1.txt.bak" | run_script "$TEST_DIR/file2.txt.bak"
    assert_rc "stdin and args" 0
    local log
    log="$(get_mv_log)"
    assert_contains "processes stdin" "$log" "mv $TEST_DIR/file1.txt.bak $TEST_DIR/file1.txt"
    assert_contains "processes args" "$log" "mv $TEST_DIR/file2.txt.bak $TEST_DIR/file2.txt"
}

test_option_after_positional() {
    touch "$TEST_DIR/file.txt.bak"
    run_script "$TEST_DIR/file.txt.bak" -v
    assert_rc "option after positional" 0
    assert_stdout_contains "verbose works after positional" "Moving:"
}

test_no_bak_extension() {
    touch "$TEST_DIR/file.txt"
    run_script "$TEST_DIR/file.txt"
    # File without .bak extension: base = file.txt, but file.txt already exists
    # so unbak correctly reports "File already exists"
    assert_rc "no bak extension rejected" 1
    assert_err_contains "file exists error" "File already exists"
}

test_only_bak_extension() {
    touch "$TEST_DIR/.bak"
    run_script "$TEST_DIR/.bak"
    # .bak with no basename would move to directory path, which already exists
    # so unbak correctly reports "File already exists"
    assert_rc "only bak extension rejected" 1
    assert_err_contains "directory exists error" "File already exists"
}

# --- run ---

run_tests "$@"
