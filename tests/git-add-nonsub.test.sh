#!/bin/bash
# git-add-nonsub.test.sh - Tests for git-add-nonsub
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../git-add-nonsub"

# --- helpers ---

get_git_log() { cat "$TEST_DIR/git.log" 2>/dev/null; }
get_mv_log() { cat "$TEST_DIR/mv.log" 2>/dev/null; }
get_mktemp_log() { cat "$TEST_DIR/mktemp.log" 2>/dev/null; }

# --- shims ---

write_shims() {
    # git shim: log invocations
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/git.log"
printf 'git' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
exit 0
SHIM
    chmod +x "$SHIM_DIR/git"

    # mv shim: log moves and actually move for normal cases
    cat > "$SHIM_DIR/mv" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/mv.log"
printf 'mv' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
if [ -f "$TEST_DIR/fail_mv" ]; then
    echo "mv: cannot move" >&2
    exit 1
fi
/bin/mv "$@"
exit 0
SHIM
    chmod +x "$SHIM_DIR/mv"

    # mktemp shim: create temp dirs and log
    cat > "$SHIM_DIR/mktemp" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/mktemp.log"
printf 'mktemp' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
/usr/bin/mktemp "$@"
exit 0
SHIM
    chmod +x "$SHIM_DIR/mktemp"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
}

test_no_directory_specified() {
    run_script
    assert_rc "no dir exits 2" 2
    assert_stderr_contains "error message" "No directory specified"
}

test_unknown_option() {
    run_script --unknown
    assert_rc "unknown option exits 2" 2
    assert_stderr_contains "error message" "Unknown argument '--unknown'"
}

test_multiple_directories() {
    mkdir -p "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    run_script "$TEST_DIR/dir1" "$TEST_DIR/dir2"
    assert_rc "multiple dirs exits 2" 2
    assert_stderr_contains "error message" "Unknown argument"
}

test_directory_does_not_exist() {
    run_script "$TEST_DIR/nonexistent"
    assert_rc "nonexistent dir exits 2" 2
    assert_stderr_contains "error message" "Directory '$TEST_DIR/nonexistent' does not exist"
}

test_no_git_directory() {
    mkdir -p "$TEST_DIR/no-git"
    run_script "$TEST_DIR/no-git"
    assert_rc "no .git exits 2" 2
    assert_stderr_contains "error message" "No .git directory found in '$TEST_DIR/no-git'"
}

test_not_in_outer_repo() {
    # Shim git so rev-parse fails (simulating "not in a repo")
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/git.log"
printf 'git' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
case "$*" in
    "rev-parse --is-inside-work-tree") exit 128 ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/git"
    mkdir -p "$TEST_DIR/myrepo/.git"
    run_script "$TEST_DIR/myrepo"
    assert_rc "not in outer repo exits 2" 2
    assert_stderr_contains "error message" "Not inside a git repository"
}

test_successful_backup_add_restore() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    run_script "$TEST_DIR/myrepo"
    assert_rc "success exits 0" 0
    assert_stderr_contains "backup created" "Backup created at"
    assert_contains "git add ran" "$(get_git_log)" "git -C $TEST_DIR/myrepo add ."
    assert_stderr_contains "restore message" "Restored .git directory"
    assert_stderr_contains "git add success" "git add completed successfully"
}

test_backup_failure() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    # Make mv fail
    : > "$TEST_DIR/fail_mv"
    run_script "$TEST_DIR/myrepo"
    assert_rc "backup fail exits 1" 1
    assert_stderr_contains "backup error" "Failed to move .git to"
    assert_stderr_contains "exit message" "Failed to back up .git"
}

test_git_add_failure_with_restore() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    # Make git add fail but rev-parse succeed (precondition passes)
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/git.log"
printf 'git' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
case "$*" in
    "rev-parse --is-inside-work-tree") exit 0 ;;
esac
echo "git: add failed" >&2
exit 1
SHIM
    chmod +x "$SHIM_DIR/git"

    run_script "$TEST_DIR/myrepo"
    assert_rc "git add fail exits 1" 1
    assert_stderr_contains "git add failed" "git add failed"
    assert_stderr_contains "restore triggered" "Restoring .git..."
    assert_contains "restore called" "$(get_mv_log)" "mv"
}

test_restore_failure_after_git_add() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    # Make mv succeed first time (backup), fail second time (restore)
    cat > "$SHIM_DIR/mv" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/mv.log"
printf 'mv' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
count="$TEST_DIR/mv.count"
if [ ! -f "$count" ]; then
    echo "1" > "$count"
    /bin/mv "$@"
    exit 0
else
    echo "mv: cannot restore" >&2
    exit 1
fi
SHIM
    chmod +x "$SHIM_DIR/mv"

    run_script "$TEST_DIR/myrepo"
    assert_rc "restore fail exits 1" 1
    assert_stderr_contains "restore error" "Failed to restore"
}

test_mktemp_called_for_backup() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    run_script "$TEST_DIR/myrepo"
    assert_rc "mktemp check exits 0" 0
    assert_contains "mktemp -d called" "$(get_mktemp_log)" "mktemp -d"
}

test_info_messages_on_success() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    run_script "$TEST_DIR/myrepo"
    assert_rc "info check exits 0" 0
    assert_stderr_contains "backup info" "[INF][git-add-nonsub] Backup created at"
    assert_stderr_contains "git add info" "[INF][git-add-nonsub] Running git add on"
    assert_stderr_contains "completion info" "[INF][git-add-nonsub] git add completed successfully"
    assert_stderr_contains "restore info" "[INF][git-add-nonsub] Restored .git directory"
}

test_git_directory_restored_to_correct_location() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    run_script "$TEST_DIR/myrepo"
    assert_rc "location check exits 0" 0
    local mv_log
    mv_log="$(get_mv_log)"
    assert_contains "restore to .git" "$mv_log" "$TEST_DIR/myrepo/.git"
}

test_relative_path_directory() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    cd "$TEST_DIR" || exit 1
    env PATH="$SHIM_DIR:$PATH" /bin/bash "$UNDER_TEST" "myrepo" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "relative path exits 0" 0
    assert_stderr_contains "backup created" "Backup created at"
}

test_absolute_path_directory() {
    mkdir -p "$TEST_DIR/myrepo/.git"
    run_script "$TEST_DIR/myrepo"
    assert_rc "absolute path exits 0" 0
    assert_stderr_contains "backup created" "Backup created at"
}

# --- run ---

run_tests "$@"
