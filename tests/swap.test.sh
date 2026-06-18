#!/bin/bash
# swap.test.sh - Tests for swap
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../swap"

# --- shims ---

write_shims() {
    # mv shim: support test scenarios (success, failure points)
    cat > "$SHIM_DIR/mv" <<'SHIM'
#!/bin/bash
printf 'mv' >> "$TEST_DIR/mv.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/mv.log"; done
printf '\n' >> "$TEST_DIR/mv.log"

# Extract source and dest from args
src="${@: -2:1}"
dest="${@: -1}"

# Failure injection for specific test scenarios
case "$FAIL_MV_AT" in
    first)
        if [[ "$dest" == /tmp/temp-swap-* ]]; then
            echo "mv: cannot move '$src' to '$dest': Permission denied" >&2
            exit 1
        fi
        ;;
    second)
        if [[ "$src" != /tmp/temp-swap-* && "$dest" != /tmp/temp-swap-* ]]; then
            echo "mv: cannot move '$src' to '$dest': Permission denied" >&2
            exit 1
        fi
        ;;
    third)
        if [[ "$src" == /tmp/temp-swap-* ]]; then
            echo "mv: cannot move '$src' to '$dest': Permission denied" >&2
            exit 1
        fi
        ;;
esac

# Actually perform the move
/bin/mv "$@"
SHIM
    chmod +x "$SHIM_DIR/mv"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has EXIT STATUS" "EXIT STATUS"
}

test_help_short_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h shows help" "swap - swap two files"
}

test_no_arguments() {
    run_script
    assert_rc "no args exits 2" 2
    assert_stderr_contains "no args error" "[ERR][swap] Must provide two files to swap (received 0). Run \`swap -h\` for usage"
}

test_one_argument() {
    run_script "file1"
    assert_rc "one arg exits 2" 2
    assert_stderr_contains "one arg error" "[ERR][swap] Must provide two files to swap (received 1). Run \`swap -h\` for usage"
}

test_first_file_missing() {
    touch "$TEST_DIR/file2"
    run_script "$TEST_DIR/nosuch" "$TEST_DIR/file2"
    assert_rc "first missing exits 4" 4
    assert_stderr_contains "first missing error" "[ERR][swap] File '$TEST_DIR/nosuch' does not exist"
}

test_first_file_is_directory() {
    mkdir -p "$TEST_DIR/dir1"
    touch "$TEST_DIR/file2"
    run_script "$TEST_DIR/dir1" "$TEST_DIR/file2"
    assert_rc "first dir exits 5" 5
    assert_stderr_contains "first dir error" "[ERR][swap] '$TEST_DIR/dir1' is a directory"
}

test_second_file_missing() {
    touch "$TEST_DIR/file1"
    run_script "$TEST_DIR/file1" "$TEST_DIR/nosuch"
    assert_rc "second missing exits 6" 6
    assert_stderr_contains "second missing error" "[ERR][swap] File '$TEST_DIR/nosuch' does not exist"
}

test_second_file_is_directory() {
    touch "$TEST_DIR/file1"
    mkdir -p "$TEST_DIR/dir2"
    run_script "$TEST_DIR/file1" "$TEST_DIR/dir2"
    assert_rc "second dir exits 7" 7
    assert_stderr_contains "second dir error" "[ERR][swap] '$TEST_DIR/dir2' is a directory"
}

test_successful_swap() {
    echo "content1" > "$TEST_DIR/file1"
    echo "content2" > "$TEST_DIR/file2"
    run_script "$TEST_DIR/file1" "$TEST_DIR/file2"
    assert_rc "swap success exits 0" 0
    assert_eq "file1 has content2" "$(cat "$TEST_DIR/file1")" "content2"
    assert_eq "file2 has content1" "$(cat "$TEST_DIR/file2")" "content1"
}

test_first_mv_fails() {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    FAIL_MV_AT=first run_script "$TEST_DIR/file1" "$TEST_DIR/file2"
    assert_rc "first mv fails exits 8" 8
    assert_stderr_contains "first mv error" "[ERR][swap] Failed to move '$TEST_DIR/file1' to temporary file"
}

test_second_mv_fails() {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    FAIL_MV_AT=second run_script "$TEST_DIR/file1" "$TEST_DIR/file2"
    assert_rc "second mv fails exits 9" 9
    assert_stderr_contains "second mv error" "[ERR][swap] Failed to move '$TEST_DIR/file2' to '$TEST_DIR/file1'"
}

test_third_mv_fails() {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    FAIL_MV_AT=third run_script "$TEST_DIR/file1" "$TEST_DIR/file2"
    assert_rc "third mv fails exits 10" 10
    assert_stderr_contains "third mv error" "[ERR][swap] Failed to move temporary file to '$TEST_DIR/file2'"
}

test_swap_preserves_permissions() {
    echo "exe" > "$TEST_DIR/exec1"
    echo "normal" > "$TEST_DIR/normal2"
    chmod 755 "$TEST_DIR/exec1"
    chmod 644 "$TEST_DIR/normal2"
    run_script "$TEST_DIR/exec1" "$TEST_DIR/normal2"
    assert_rc "perms swap exits 0" 0
    local perm1
    perm1="$(stat -f '%Lp' "$TEST_DIR/exec1" 2>/dev/null || stat -c '%a' "$TEST_DIR/exec1" 2>/dev/null)"
    local perm2
    perm2="$(stat -f '%Lp' "$TEST_DIR/normal2" 2>/dev/null || stat -c '%a' "$TEST_DIR/normal2" 2>/dev/null)"
    assert_eq "exec1 now has 644" "$perm1" "644"
    assert_eq "normal2 now has 755" "$perm2" "755"
}

test_swap_with_spaces_in_names() {
    echo "a" > "$TEST_DIR/file with spaces 1"
    echo "b" > "$TEST_DIR/file with spaces 2"
    run_script "$TEST_DIR/file with spaces 1" "$TEST_DIR/file with spaces 2"
    assert_rc "spaces swap exits 0" 0
    assert_eq "spaces file1 content" "$(cat "$TEST_DIR/file with spaces 1")" "b"
    assert_eq "spaces file2 content" "$(cat "$TEST_DIR/file with spaces 2")" "a"
}

test_swap_empty_files() {
    touch "$TEST_DIR/empty1" "$TEST_DIR/empty2"
    run_script "$TEST_DIR/empty1" "$TEST_DIR/empty2"
    assert_rc "empty swap exits 0" 0
    assert_eq "empty1 still empty" "$(cat "$TEST_DIR/empty1")" ""
    assert_eq "empty2 still empty" "$(cat "$TEST_DIR/empty2")" ""
}

test_swap_symlinks() {
    echo "target1" > "$TEST_DIR/target1"
    echo "target2" > "$TEST_DIR/target2"
    ln -s "$TEST_DIR/target1" "$TEST_DIR/link1"
    ln -s "$TEST_DIR/target2" "$TEST_DIR/link2"
    run_script "$TEST_DIR/link1" "$TEST_DIR/link2"
    assert_rc "symlink swap exits 0" 0
    local resolved1
    resolved1="$(readlink "$TEST_DIR/link1")"
    local resolved2
    resolved2="$(readlink "$TEST_DIR/link2")"
    assert_eq "link1 now points to target2" "$resolved1" "$TEST_DIR/target2"
    assert_eq "link2 now points to target1" "$resolved2" "$TEST_DIR/target1"
}

test_swap_different_directories() {
    mkdir -p "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    echo "a" > "$TEST_DIR/dir1/file"
    echo "b" > "$TEST_DIR/dir2/file"
    run_script "$TEST_DIR/dir1/file" "$TEST_DIR/dir2/file"
    assert_rc "cross-dir swap exits 0" 0
    assert_eq "dir1/file has b" "$(cat "$TEST_DIR/dir1/file")" "b"
    assert_eq "dir2/file has a" "$(cat "$TEST_DIR/dir2/file")" "a"
}

test_temp_file_collision_handling() {
    echo "x" > "$TEST_DIR/file1"
    echo "y" > "$TEST_DIR/file2"
    # Pre-create the simple temp file name to force RANDOM fallback
    touch "/tmp/temp-swap-file1"
    run_script "$TEST_DIR/file1" "$TEST_DIR/file2"
    assert_rc "collision handled exits 0" 0
    assert_eq "swap succeeded despite collision" "$(cat "$TEST_DIR/file1")" "y"
}

test_swap_large_files() {
    dd if=/dev/zero of="$TEST_DIR/large1" bs=1024 count=100 2>/dev/null
    dd if=/dev/zero of="$TEST_DIR/large2" bs=1024 count=100 2>/dev/null
    run_script "$TEST_DIR/large1" "$TEST_DIR/large2"
    assert_rc "large files swap exits 0" 0
    local size1
    size1="$(wc -c < "$TEST_DIR/large1" | tr -d ' ')"
    local size2
    size2="$(wc -c < "$TEST_DIR/large2" | tr -d ' ')"
    assert_eq "large1 size" "$size1" "102400"
    assert_eq "large2 size" "$size2" "102400"
}

test_mv_shim_called() {
    touch "$TEST_DIR/file1" "$TEST_DIR/file2"
    run_script "$TEST_DIR/file1" "$TEST_DIR/file2"
    assert_rc "mv shim exits 0" 0
    local mv_log
    mv_log="$(cat "$TEST_DIR/mv.log" 2>/dev/null)"
    assert_contains "mv called three times" "$mv_log" "mv "
    assert_contains "first mv to temp" "$mv_log" "$TEST_DIR/file1 /tmp/temp-swap-"
    assert_contains "second mv file2 to file1" "$mv_log" "$TEST_DIR/file2 $TEST_DIR/file1"
}

# --- run ---

run_tests "$@"
