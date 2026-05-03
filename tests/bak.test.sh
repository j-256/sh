#!/bin/bash
# bak.test.sh - Tests for bak
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../bak"

# --- helpers ---

get_mv_log() { cat "$TEST_DIR/mv.log" 2>/dev/null; }

assert_file_exists() {
    local label="$1"
    local file="$2"
    if [ -e "$TEST_DIR/files/$file" ]; then
        _ok "$label"
    else
        _fail "$label: expected file '$file' to exist"
    fi
}

assert_file_not_exists() {
    local label="$1"
    local file="$2"
    if [ ! -e "$TEST_DIR/files/$file" ]; then
        _ok "$label"
    else
        _fail "$label: expected file '$file' NOT to exist"
    fi
}

# --- shims ---

write_shims() {
    # mv shim: log calls and actually move files
    cat > "$SHIM_DIR/mv" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/mv.log"
printf 'mv %s %s\n' "$1" "$2" >> "$log"
# Actually perform the move for realistic testing
/bin/mv "$1" "$2"
exit 0
SHIM
    chmod +x "$SHIM_DIR/mv"

    # tput shim: suppress underline codes for testing
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"

    # basename shim
    cat > "$SHIM_DIR/basename" <<'SHIM'
#!/bin/bash
printf '%s\n' "bak"
exit 0
SHIM
    chmod +x "$SHIM_DIR/basename"

    # Create files directory for test files
    mkdir -p "$TEST_DIR/files"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
}

test_no_args_shows_help() {
    run_script
    assert_rc "no args exits 0" 0
    assert_stdout_contains "no args shows NAME" "NAME"
}

test_file_not_exists() {
    run_script "$TEST_DIR/files/nonexistent"
    assert_rc "file not exists" 1
    assert_err_contains "error message" "[ERR][bak] $TEST_DIR/files/nonexistent: No such file"
}

test_basic_backup() {
    echo "content" > "$TEST_DIR/files/test.txt"
    run_script "$TEST_DIR/files/test.txt"
    assert_rc "basic backup" 0
    assert_file_not_exists "original gone" "test.txt"
    assert_file_exists "backup created" "test.txt.bak"
    assert_contains "mv called" "$(get_mv_log)" "mv $TEST_DIR/files/test.txt $TEST_DIR/files/test.txt.bak"
}

test_chained_backup() {
    echo "original" > "$TEST_DIR/files/file.txt"
    echo "backup" > "$TEST_DIR/files/file.txt.bak"
    run_script "$TEST_DIR/files/file.txt"
    assert_rc "chained backup" 0
    assert_file_not_exists "original gone" "file.txt"
    assert_file_exists "backup level 1" "file.txt.bak"
    assert_file_exists "backup level 2" "file.txt.bak.bak"
    assert_contains "rotates existing backup" "$(get_mv_log)" "mv $TEST_DIR/files/file.txt.bak $TEST_DIR/files/file.txt.bak.bak"
    assert_contains "moves original" "$(get_mv_log)" "mv $TEST_DIR/files/file.txt $TEST_DIR/files/file.txt.bak"
}

test_triple_backup() {
    echo "a" > "$TEST_DIR/files/x.txt"
    echo "b" > "$TEST_DIR/files/x.txt.bak"
    echo "c" > "$TEST_DIR/files/x.txt.bak.bak"
    run_script "$TEST_DIR/files/x.txt"
    assert_rc "triple backup" 0
    assert_file_not_exists "original gone" "x.txt"
    assert_file_exists "bak exists" "x.txt.bak"
    assert_file_exists "bak.bak exists" "x.txt.bak.bak"
    assert_file_exists "bak.bak.bak exists" "x.txt.bak.bak.bak"
}

test_verbose_mode() {
    echo "content" > "$TEST_DIR/files/verbose.txt"
    run_script -v "$TEST_DIR/files/verbose.txt"
    assert_rc "verbose exits 0" 0
    assert_stdout_contains "shows move" "Moving"
}

test_verbose_long_flag() {
    echo "content" > "$TEST_DIR/files/verbose2.txt"
    run_script --verbose "$TEST_DIR/files/verbose2.txt"
    assert_rc "verbose long" 0
    assert_stdout_contains "shows move" "Moving"
}

test_dry_run_mode() {
    echo "content" > "$TEST_DIR/files/dryrun.txt"
    run_script -n "$TEST_DIR/files/dryrun.txt"
    assert_rc "dry run exits 0" 0
    assert_stdout_contains "shows would move" "Would move"
    assert_file_exists "original still exists" "dryrun.txt"
    assert_file_not_exists "backup not created" "dryrun.txt.bak"
}

test_dry_run_long_flag() {
    echo "content" > "$TEST_DIR/files/dryrun2.txt"
    run_script --dry-run "$TEST_DIR/files/dryrun2.txt"
    assert_rc "dry run long" 0
    assert_stdout_contains "shows would move" "Would move"
    assert_file_exists "original still exists" "dryrun2.txt"
}

test_dry_run_with_chain() {
    echo "original" > "$TEST_DIR/files/chain.txt"
    echo "backup" > "$TEST_DIR/files/chain.txt.bak"
    run_script -n "$TEST_DIR/files/chain.txt"
    assert_rc "dry run chain" 0
    assert_file_exists "original unchanged" "chain.txt"
    assert_file_exists "backup unchanged" "chain.txt.bak"
    assert_file_not_exists "no triple backup" "chain.txt.bak.bak"
}

test_multiple_files() {
    echo "a" > "$TEST_DIR/files/a.txt"
    echo "b" > "$TEST_DIR/files/b.txt"
    run_script "$TEST_DIR/files/a.txt" "$TEST_DIR/files/b.txt"
    assert_rc "multiple files" 0
    assert_file_exists "a backed up" "a.txt.bak"
    assert_file_exists "b backed up" "b.txt.bak"
    assert_file_not_exists "a gone" "a.txt"
    assert_file_not_exists "b gone" "b.txt"
}

test_multiple_files_one_missing() {
    echo "exists" > "$TEST_DIR/files/exists.txt"
    run_script "$TEST_DIR/files/exists.txt" "$TEST_DIR/files/missing.txt"
    assert_rc "one missing" 1
    assert_err_contains "error for missing" "[ERR][bak] $TEST_DIR/files/missing.txt: No such file"
}

test_unknown_option() {
    run_script --invalid
    assert_rc "unknown option" 2
    assert_err_contains "unknown argument" "[ERR][bak] Unknown argument '--invalid'"
}

test_double_dash_boundary() {
    echo "content" > "$TEST_DIR/files/dash.txt"
    run_script -- "$TEST_DIR/files/dash.txt"
    assert_rc "double dash" 0
    assert_file_exists "backup created" "dash.txt.bak"
}

test_double_dash_with_flags_before() {
    echo "content" > "$TEST_DIR/files/flags.txt"
    run_script -v -- "$TEST_DIR/files/flags.txt"
    assert_rc "flags before --" 0
    assert_stdout_contains "verbose works" "Moving"
    assert_file_exists "backup created" "flags.txt.bak"
}

test_backup_only_exists() {
    echo "backup only" > "$TEST_DIR/files/only.bak"
    run_script "$TEST_DIR/files/only"
    assert_rc "backup only" 1
    assert_err_contains "error message" "[ERR][bak] $TEST_DIR/files/only: No such file"
}

test_verbose_and_dry_run() {
    echo "content" > "$TEST_DIR/files/both.txt"
    run_script -v -n "$TEST_DIR/files/both.txt"
    assert_rc "both flags" 0
    assert_stdout_contains "shows would move" "Would move"
    assert_file_exists "file unchanged" "both.txt"
}

test_bundled_short_opts() {
    echo "content" > "$TEST_DIR/files/bundle.txt"
    run_script -vn "$TEST_DIR/files/bundle.txt"
    assert_rc "bundled -vn exits 0" 0
    assert_stdout_contains "bundled verbose active" "Would move"
    assert_file_exists "bundled dry-run leaves file" "bundle.txt"
    assert_file_not_exists "bundled dry-run makes no backup" "bundle.txt.bak"
}

test_bundled_short_opts_reversed() {
    echo "content" > "$TEST_DIR/files/bundle2.txt"
    run_script -nv "$TEST_DIR/files/bundle2.txt"
    assert_rc "bundled -nv exits 0" 0
    assert_stdout_contains "reversed bundle still verbose" "Would move"
    assert_file_exists "reversed bundle leaves file" "bundle2.txt"
}

test_interleaved_positional_and_flag() {
    echo "content" > "$TEST_DIR/files/interleave.txt"
    run_script "$TEST_DIR/files/interleave.txt" -v
    assert_rc "interleaved order exits 0" 0
    assert_stdout_contains "flag after positional works" "Moving"
    assert_file_exists "interleaved backup created" "interleave.txt.bak"
}

test_file_with_spaces() {
    echo "content" > "$TEST_DIR/files/file with spaces.txt"
    run_script "$TEST_DIR/files/file with spaces.txt"
    assert_rc "spaces in name" 0
    assert_file_not_exists "original gone" "file with spaces.txt"
    assert_file_exists "backup created" "file with spaces.txt.bak"
}

test_empty_file() {
    touch "$TEST_DIR/files/empty.txt"
    run_script "$TEST_DIR/files/empty.txt"
    assert_rc "empty file" 0
    assert_file_exists "backup created" "empty.txt.bak"
}

test_directory_backup() {
    mkdir -p "$TEST_DIR/files/mydir"
    run_script "$TEST_DIR/files/mydir"
    assert_rc "directory" 0
    assert_file_not_exists "dir gone" "mydir"
    assert_file_exists "dir backup" "mydir.bak"
}

# --- run ---

run_tests "$@"
