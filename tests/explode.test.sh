#!/bin/bash
# explode.test.sh - Tests for explode
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../explode"

# --- helpers ---

# Create a test directory structure with files
create_test_dir() {
    local name="$1"
    mkdir -p "$TEST_DIR/$name"
    echo "file1" > "$TEST_DIR/$name/file1.txt"
    echo "file2" > "$TEST_DIR/$name/file2.txt"
    mkdir -p "$TEST_DIR/$name/subdir"
    echo "nested" > "$TEST_DIR/$name/subdir/nested.txt"
}

# Count items in a directory
count_items() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "0"
        return
    fi
    find "$dir" -mindepth 1 -maxdepth 1 -print0 | tr -cd '\0' | wc -c | tr -d ' '
}

# Check if a directory exists
dir_exists() {
    [ -d "$1" ]
}

# Check if a file exists
file_exists() {
    [ -f "$1" ]
}

# --- shims ---

write_shims() {
    # mv shim: track calls, pass through to real mv
    cat > "$SHIM_DIR/mv" <<'SHIM'
#!/bin/bash
printf 'mv' >> "$TEST_DIR/mv.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/mv.log"; done
printf '\n' >> "$TEST_DIR/mv.log"
# Execute real mv
/bin/mv "$@"
SHIM
    chmod +x "$SHIM_DIR/mv"

    # find shim: track calls, pass through to real find
    cat > "$SHIM_DIR/find" <<'SHIM'
#!/bin/bash
printf 'find' >> "$TEST_DIR/find.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/find.log"; done
printf '\n' >> "$TEST_DIR/find.log"
# Execute real find
/usr/bin/find "$@"
SHIM
    chmod +x "$SHIM_DIR/find"

    # rmdir shim: track calls, pass through to real rmdir
    cat > "$SHIM_DIR/rmdir" <<'SHIM'
#!/bin/bash
printf 'rmdir' >> "$TEST_DIR/rmdir.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/rmdir.log"; done
printf '\n' >> "$TEST_DIR/rmdir.log"
# Execute real rmdir
/bin/rmdir "$@"
SHIM
    chmod +x "$SHIM_DIR/rmdir"

    # dirname shim: pass through to real dirname
    cat > "$SHIM_DIR/dirname" <<'SHIM'
#!/bin/bash
/usr/bin/dirname "$@"
SHIM
    chmod +x "$SHIM_DIR/dirname"

    # basename shim: pass through to real basename
    cat > "$SHIM_DIR/basename" <<'SHIM'
#!/bin/bash
/usr/bin/basename "$@"
SHIM
    chmod +x "$SHIM_DIR/basename"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help describes action" "move a directory's contents up one level"
}

test_no_args() {
    run_script
    assert_rc "no args fails" 2
    assert_stderr_contains "error: no directory" "No directory specified"
}

test_nonexistent_dir() {
    run_script "$TEST_DIR/nosuchdir"
    assert_rc "nonexistent fails" 2
    assert_stderr_contains "error: does not exist" "does not exist"
}

test_not_a_directory() {
    echo "file" > "$TEST_DIR/notdir.txt"
    run_script "$TEST_DIR/notdir.txt"
    assert_rc "not a dir fails" 2
    assert_stderr_contains "error: not a directory" "is not a directory"
}

test_basic_explode() {
    create_test_dir "basic"
    run_script "$TEST_DIR/basic"
    assert_rc "basic explode succeeds" 0
    assert_eq "basic: file1 moved" "$(file_exists "$TEST_DIR/file1.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "basic: file2 moved" "$(file_exists "$TEST_DIR/file2.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "basic: subdir moved" "$(dir_exists "$TEST_DIR/subdir" && echo "yes" || echo "no")" "yes"
    assert_eq "basic: nested file in place" "$(file_exists "$TEST_DIR/subdir/nested.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "basic: original dir removed" "$(dir_exists "$TEST_DIR/basic" && echo "no" || echo "yes")" "yes"
}

test_collision_no_force() {
    create_test_dir "collision"
    echo "existing" > "$TEST_DIR/file1.txt"
    run_script "$TEST_DIR/collision"
    assert_rc "collision fails without force" 2
    assert_stderr_contains "collision error" "the following items already exist"
    assert_stderr_contains "collision lists file" "file1.txt"
    assert_eq "collision: original dir still exists" "$(dir_exists "$TEST_DIR/collision" && echo "yes" || echo "no")" "yes"
    assert_eq "collision: existing file unchanged" "$(cat "$TEST_DIR/file1.txt")" "existing"
}

test_collision_with_force() {
    create_test_dir "collision"
    echo "existing" > "$TEST_DIR/file1.txt"
    run_script --force "$TEST_DIR/collision"
    assert_rc "force collision succeeds" 0
    assert_eq "force: file1 overwritten" "$(cat "$TEST_DIR/file1.txt")" "file1"
    assert_eq "force: file2 moved" "$(file_exists "$TEST_DIR/file2.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "force: original dir removed" "$(dir_exists "$TEST_DIR/collision" && echo "no" || echo "yes")" "yes"
}

test_dry_run_no_collision() {
    create_test_dir "dryrun"
    run_script --dry-run "$TEST_DIR/dryrun"
    assert_rc "dry-run succeeds" 0
    assert_stdout_contains "dry-run: shows move target" "Would move to $TEST_DIR:"
    assert_stdout_contains "dry-run: lists file1" "file1.txt"
    assert_stdout_contains "dry-run: lists file2" "file2.txt"
    assert_stdout_contains "dry-run: lists subdir" "subdir"
    assert_stdout_contains "dry-run: shows remove" "Would remove: $TEST_DIR/dryrun"
    assert_eq "dry-run: dir still exists" "$(dir_exists "$TEST_DIR/dryrun" && echo "yes" || echo "no")" "yes"
    assert_eq "dry-run: files not moved" "$(file_exists "$TEST_DIR/file1.txt" && echo "no" || echo "yes")" "yes"
}

test_dry_run_with_collision() {
    create_test_dir "dryrun"
    echo "existing" > "$TEST_DIR/file1.txt"
    run_script --dry-run "$TEST_DIR/dryrun"
    assert_rc "dry-run collision fails" 2
    assert_stderr_contains "dry-run: collision error" "the following items already exist"
    assert_stderr_contains "dry-run: aborts message" "Aborting"
    assert_eq "dry-run: dir still exists" "$(dir_exists "$TEST_DIR/dryrun" && echo "yes" || echo "no")" "yes"
}

test_dry_run_with_force() {
    create_test_dir "dryrun"
    echo "existing" > "$TEST_DIR/file1.txt"
    run_script --dry-run --force "$TEST_DIR/dryrun"
    assert_rc "dry-run force succeeds" 0
    assert_stdout_contains "dry-run force: shows overwrite" "Would overwrite (--force):"
    assert_stdout_contains "dry-run force: lists collision" "file1.txt"
    assert_eq "dry-run force: existing unchanged" "$(cat "$TEST_DIR/file1.txt")" "existing"
    assert_eq "dry-run force: dir still exists" "$(dir_exists "$TEST_DIR/dryrun" && echo "yes" || echo "no")" "yes"
}

test_verbose() {
    create_test_dir "verbose"
    run_script --verbose "$TEST_DIR/verbose"
    assert_rc "verbose succeeds" 0
    assert_stdout_contains "verbose: shows file1" "file1.txt -> $TEST_DIR/"
    assert_stdout_contains "verbose: shows file2" "file2.txt -> $TEST_DIR/"
    assert_stdout_contains "verbose: shows subdir" "subdir -> $TEST_DIR/"
}

test_unknown_option() {
    run_script --unknown
    assert_rc "unknown option fails" 2
    assert_stderr_contains "unknown option error" "Unknown argument '--unknown'"
}

test_multiple_dirs() {
    create_test_dir "dir1"
    create_test_dir "dir2"
    run_script "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    assert_rc "multiple dirs fails" 2
    assert_stderr_contains "multiple dirs error" "Multiple directories specified"
}

test_double_dash() {
    create_test_dir "doubledash"
    run_script -- "$TEST_DIR/doubledash"
    assert_rc "double dash succeeds" 0
    assert_eq "double dash: files moved" "$(file_exists "$TEST_DIR/file1.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "double dash: dir removed" "$(dir_exists "$TEST_DIR/doubledash" && echo "no" || echo "yes")" "yes"
}

test_short_options() {
    create_test_dir "short"
    run_script -f -v "$TEST_DIR/short"
    assert_rc "short options succeed" 0
    assert_stdout_contains "short -v works" "file1.txt -> $TEST_DIR/"
}

test_bundled_short_opts() {
    create_test_dir "bundle"
    run_script -nv "$TEST_DIR/bundle"
    assert_rc "bundled -nv succeeds" 0
    assert_stdout_contains "bundled: dry-run active" "Would move to"
    assert_eq "bundled: dir still exists" "$(dir_exists "$TEST_DIR/bundle" && echo "yes" || echo "no")" "yes"
}

test_bundled_with_force() {
    create_test_dir "bundle3"
    echo "existing" > "$TEST_DIR/file1.txt"
    run_script -nvf "$TEST_DIR/bundle3"
    assert_rc "bundled -nvf succeeds" 0
    assert_stdout_contains "bundled: force active" "Would overwrite (--force):"
    assert_stdout_contains "bundled: dry-run active" "Would move to"
}

test_empty_directory() {
    mkdir -p "$TEST_DIR/empty"
    run_script "$TEST_DIR/empty"
    assert_rc "empty dir succeeds" 0
    assert_eq "empty: dir removed" "$(dir_exists "$TEST_DIR/empty" && echo "no" || echo "yes")" "yes"
}

test_nested_subdirectories() {
    mkdir -p "$TEST_DIR/nested/sub1/sub2"
    echo "deep" > "$TEST_DIR/nested/sub1/sub2/deep.txt"
    run_script "$TEST_DIR/nested"
    assert_rc "nested succeeds" 0
    assert_eq "nested: sub1 moved" "$(dir_exists "$TEST_DIR/sub1" && echo "yes" || echo "no")" "yes"
    assert_eq "nested: deep file preserved" "$(file_exists "$TEST_DIR/sub1/sub2/deep.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "nested: original removed" "$(dir_exists "$TEST_DIR/nested" && echo "no" || echo "yes")" "yes"
}

test_files_with_spaces() {
    mkdir -p "$TEST_DIR/spaces"
    echo "content" > "$TEST_DIR/spaces/file with spaces.txt"
    echo "content2" > "$TEST_DIR/spaces/another file.txt"
    run_script "$TEST_DIR/spaces"
    assert_rc "spaces succeeds" 0
    assert_eq "spaces: file1 moved" "$(file_exists "$TEST_DIR/file with spaces.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "spaces: file2 moved" "$(file_exists "$TEST_DIR/another file.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "spaces: dir removed" "$(dir_exists "$TEST_DIR/spaces" && echo "no" || echo "yes")" "yes"
}

test_special_characters_in_names() {
    mkdir -p "$TEST_DIR/special"
    echo "content" > "$TEST_DIR/special/file-with-dash.txt"
    echo "content" > "$TEST_DIR/special/file_underscore.txt"
    echo "content" > "$TEST_DIR/special/file.multiple.dots.txt"
    run_script "$TEST_DIR/special"
    assert_rc "special chars succeed" 0
    assert_eq "special: dash file moved" "$(file_exists "$TEST_DIR/file-with-dash.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "special: underscore moved" "$(file_exists "$TEST_DIR/file_underscore.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "special: dots moved" "$(file_exists "$TEST_DIR/file.multiple.dots.txt" && echo "yes" || echo "no")" "yes"
}

test_relative_path() {
    create_test_dir "relative"
    cd "$TEST_DIR" || exit 1
    run_script "relative"
    assert_rc "relative path succeeds" 0
    assert_eq "relative: files moved" "$(file_exists "$TEST_DIR/file1.txt" && echo "yes" || echo "no")" "yes"
}

test_trailing_slash() {
    create_test_dir "trailing"
    run_script "$TEST_DIR/trailing/"
    assert_rc "trailing slash succeeds" 0
    assert_eq "trailing: files moved" "$(file_exists "$TEST_DIR/file1.txt" && echo "yes" || echo "no")" "yes"
    assert_eq "trailing: dir removed" "$(dir_exists "$TEST_DIR/trailing" && echo "no" || echo "yes")" "yes"
}

test_combined_options() {
    create_test_dir "combined"
    run_script -n -v "$TEST_DIR/combined"
    assert_rc "combined options succeed" 0
    assert_stdout_contains "combined: shows moves" "Would move to"
    assert_eq "combined: dir still exists" "$(dir_exists "$TEST_DIR/combined" && echo "yes" || echo "no")" "yes"
}

test_rmdir_fails_not_empty() {
    create_test_dir "rmfail"
    # Make rmdir fail by creating a shim that fails
    cat > "$SHIM_DIR/rmdir" <<'SHIM'
#!/bin/bash
exit 1
SHIM
    chmod +x "$SHIM_DIR/rmdir"
    run_script "$TEST_DIR/rmfail"
    assert_rc "rmdir fail exits 1" 1
    assert_stderr_contains "rmdir fail error" "Failed to remove"
}

test_option_after_dir() {
    create_test_dir "optafter"
    run_script "$TEST_DIR/optafter" --verbose
    assert_rc "option after dir succeeds" 0
    assert_stdout_contains "option after shows moves" "file1.txt -> $TEST_DIR/"
}

# --- run ---

run_tests "$@"
