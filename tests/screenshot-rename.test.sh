#!/bin/bash
# screenshot-rename.test.sh - Tests for screenshot-rename
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../screenshot-rename"

# --- shims ---

write_shims() {
    cat > "$SHIM_DIR/fswatch" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/fswatch"

    # defaults shim: by default, the screencapture location is not configured.
    # Tests can touch files in $TEST_DIR to change this behavior.
    cat > "$SHIM_DIR/defaults" <<'SHIM'
#!/bin/bash
if [ "$1" = "read" ] && [ "$2" = "com.apple.screencapture" ] && [ "$3" = "location" ]; then
    if [ -f "$TEST_DIR/screencapture_location" ]; then
        cat "$TEST_DIR/screencapture_location"
        exit 0
    fi
    # Mimic the real behavior: non-zero exit when the key is unset
    echo "Domain/default pair of (com.apple.screencapture, location) does not exist" >&2
    exit 1
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/defaults"

    export HOME="$TEST_DIR"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help mentions fswatch" "fswatch"
    assert_stdout_contains "help mentions daemon" "Ctrl-C to stop"
    assert_stdout_contains "help shows before example" "Screenshot 2025-08-04 at 12.05.57.png"
    assert_stdout_contains "help shows after example" "2025-08-04 12.05.57.png"
    assert_stdout_contains "help documents --path" "--path"
    assert_stdout_contains "help documents --format" "--format"
}

test_help_short() {
    run_script -h
    assert_rc "short help exits 0" 0
    assert_stdout_contains "short help has NAME" "NAME"
}

test_unknown_option() {
    run_script --unknown
    assert_rc "unknown exits 2" 2
    assert_err_contains "unknown msg" "Unknown option: --unknown"
}

test_unknown_short() {
    run_script -x
    assert_rc "unknown short exits 2" 2
    assert_err_contains "unknown short msg" "Unknown option: -x"
}

test_unexpected_argument() {
    run_script positional
    assert_rc "unexpected exits 2" 2
    assert_err_contains "unexpected msg" "Unexpected argument: positional"
}

test_utc_then_argument() {
    run_script --utc badarg
    assert_rc "utc arg exits 2" 2
    assert_err_contains "utc arg msg" "Unexpected argument: badarg"
}

test_fswatch_missing() {
    rm -f "$SHIM_DIR/fswatch"
    # Restrict PATH so real fswatch is not found
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "no fswatch exits 1" 1
    assert_err_contains "no fswatch msg" "fswatch is not installed"
}

test_fswatch_after_utc() {
    rm -f "$SHIM_DIR/fswatch"
    # Restrict PATH so real fswatch is not found
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" --utc >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "no fswatch utc exits 1" 1
    assert_err_contains "no fswatch utc msg" "fswatch is not installed"
}

test_double_dash() {
    run_script --
    assert_rc "double dash exits 0" 0
    assert_stdout_contains "runs normally" "Watching for new screenshots"
}

test_default_watch_dir_falls_back_to_desktop() {
    # No screencapture_location file -> defaults fails -> watch ~/Desktop
    mkdir -p "$HOME/Desktop"
    run_script
    assert_rc "default desktop exits 0" 0
    assert_stdout_contains "watching desktop" "$HOME/Desktop"
}

test_default_watch_dir_from_defaults_read() {
    # Simulate a user who configured a custom screencapture location
    mkdir -p "$TEST_DIR/screenshots"
    printf '%s' "$TEST_DIR/screenshots" > "$TEST_DIR/screencapture_location"
    run_script
    assert_rc "custom location exits 0" 0
    assert_stdout_contains "watching custom" "$TEST_DIR/screenshots"
}

test_default_watch_dir_tilde_expansion() {
    # defaults sometimes returns a tilde-prefixed path literally
    mkdir -p "$HOME/Shots"
    # shellcheck disable=SC2088 # literal tilde is what `defaults` emits
    printf '%s' '~/Shots' > "$TEST_DIR/screencapture_location"
    run_script
    assert_rc "tilde expanded exits 0" 0
    assert_stdout_contains "watching tilde" "$HOME/Shots"
}

test_default_watch_dir_invalid_falls_back() {
    # defaults returns a non-existent path -> fall back to ~/Desktop
    mkdir -p "$HOME/Desktop"
    printf '%s' '/nonexistent/path/xyzzy' > "$TEST_DIR/screencapture_location"
    run_script
    assert_rc "invalid falls back exits 0" 0
    assert_stdout_contains "fallback to desktop" "$HOME/Desktop"
}

test_path_flag_overrides_default() {
    mkdir -p "$TEST_DIR/custom"
    run_script --path "$TEST_DIR/custom"
    assert_rc "path flag exits 0" 0
    assert_stdout_contains "watching custom path" "$TEST_DIR/custom"
}

test_path_equals_form() {
    mkdir -p "$TEST_DIR/custom2"
    run_script --path="$TEST_DIR/custom2"
    assert_rc "path= exits 0" 0
    assert_stdout_contains "watching custom2" "$TEST_DIR/custom2"
}

test_path_missing_value() {
    run_script --path
    assert_rc "missing path value exits 2" 2
    assert_err_contains "path err msg" "--path requires a directory"
}

test_format_flag_accepted() {
    # We can't observe the format without triggering a rename, but we can at
    # least confirm the flag parses cleanly and the watcher starts.
    run_script --format "%Y%m%d-%H%M%S"
    assert_rc "format flag exits 0" 0
    assert_stdout_contains "watcher starts" "Watching for new screenshots"
}

test_format_missing_value() {
    run_script --format
    assert_rc "missing format value exits 2" 2
    assert_err_contains "format err msg" "--format requires a strftime pattern"
}

# --- run ---

run_tests "$@"
