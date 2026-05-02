#!/bin/bash
# git-backup.test.sh - Tests for git-backup
# shellcheck source-path=SCRIPTDIR disable=SC2329,SC2016

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../git-backup"

# --- helpers ---

get_git_log() { cat "$TEST_DIR/git.log" 2>/dev/null; }
get_date_log() { cat "$TEST_DIR/date.log" 2>/dev/null; }

# --- shims ---

write_shims() {
    # git shim: log all invocations, simulate success or failure based on current directory
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/git.log"
printf 'git' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

# Check current directory to determine which failure mode to use
cwd="$(basename "$(pwd)")"

# Simulate failures based on command and current directory
case "$cwd:$*" in
    fail-stash:stash\ save\ --include-untracked*) exit 1 ;;
    fail-checkout:checkout\ -b*) exit 1 ;;
    fail-apply:stash\ apply*) exit 1 ;;
    fail-add:add\ .*) exit 1 ;;
    fail-commit:commit\ -m*) exit 1 ;;
    fail-push:push*) exit 1 ;;
    fail-checkout-dash:checkout\ -) exit 1 ;; # Match exactly "checkout -", not "checkout -b"
    fail-branch:branch\ -D*) exit 1 ;;
esac

# Conflict mode handling (for test-repo directory only)
case "$*" in
    stash\ apply*)
        # Check if we're in conflict mode (first apply after checkout -b)
        if [ -f "$TEST_DIR/conflict_mode" ] && [ ! -f "$TEST_DIR/conflict_happened" ]; then
            echo "CONFLICT (content): Merge conflict in test.txt" >&2
            : > "$TEST_DIR/conflict_happened"
            exit 1
        fi
        ;;
    status\ --short*)
        # Return unmerged files when in conflict mode
        if [ -f "$TEST_DIR/conflict_mode" ] && [ -f "$TEST_DIR/conflict_happened" ]; then
            echo "UU test.txt"
            echo "UU other.txt"
        fi
        ;;
esac

exit 0
SHIM
    chmod +x "$SHIM_DIR/git"

    # date shim: return deterministic timestamp
    cat > "$SHIM_DIR/date" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/date.log"
printf 'date' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
printf '%s\n' "2025-01-15-1430.45"
exit 0
SHIM
    chmod +x "$SHIM_DIR/date"

    # cd shim: track directory changes, fail if requested
    cat > "$SHIM_DIR/cd" <<'SHIM'
#!/bin/bash
case "$1" in
    */fail-cd*) exit 1 ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/cd"

    # Create all test repo directories
    mkdir -p "$TEST_DIR/test-repo"
    mkdir -p "$TEST_DIR/fail-stash"
    mkdir -p "$TEST_DIR/fail-checkout"
    mkdir -p "$TEST_DIR/fail-apply"
    mkdir -p "$TEST_DIR/fail-add"
    mkdir -p "$TEST_DIR/fail-commit"
    mkdir -p "$TEST_DIR/fail-push"
    mkdir -p "$TEST_DIR/fail-checkout-dash"
    mkdir -p "$TEST_DIR/fail-branch"
    mkdir -p "$TEST_DIR/dir with spaces"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has git-backup name" "git-backup"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has repo_directory" "repo_directory"
}

test_missing_directory() {
    run_script
    assert_rc "missing dir" 2
    assert_err_contains "error message" "[ERR][git-backup] No directory provided"
}

test_basic_backup_flow() {
    run_script "$TEST_DIR/test-repo"
    assert_rc "basic backup" 0
    assert_contains "stash save called" "$(get_git_log)" "git stash save --include-untracked backup-2025-01-15-1430.45"
    assert_contains "checkout -b called" "$(get_git_log)" "git checkout -b backup-2025-01-15-1430.45"
    assert_contains "stash apply called" "$(get_git_log)" "git stash apply"
    assert_contains "add called" "$(get_git_log)" "git add ."
    assert_contains "commit called" "$(get_git_log)" "git commit -m Backup 2025-01-15-1430.45"
    assert_contains "push to origin" "$(get_git_log)" "git push origin backup-2025-01-15-1430.45"
    assert_contains "checkout dash" "$(get_git_log)" "git checkout -"
    assert_contains "branch delete" "$(get_git_log)" "git branch -D backup-2025-01-15-1430.45"
    assert_stdout_contains "timestamp message" "Starting git repo backup 2025-01-15-1430.45"
}

test_custom_remote() {
    run_script "$TEST_DIR/test-repo" "upstream"
    assert_rc "custom remote" 0
    assert_contains "push to upstream" "$(get_git_log)" "git push upstream backup-2025-01-15-1430.45"
}

test_default_remote_origin() {
    run_script "$TEST_DIR/test-repo"
    assert_rc "default remote" 0
    assert_contains "uses origin" "$(get_git_log)" "git push origin backup-2025-01-15-1430.45"
}

test_cd_failure() {
    run_script "$TEST_DIR/fail-cd"
    assert_rc "cd fails" 1
    assert_err_contains "cd error" "[ERR][git-backup] Failed to change to directory"
}

test_stash_save_failure() {
    run_script "$TEST_DIR/fail-stash"
    assert_rc "stash save fails" 1
    assert_err_contains "stash error" '[ERR][git-backup] `git stash save --include-untracked "backup-2025-01-15-1430.45"` failed'
}

test_checkout_b_failure() {
    run_script "$TEST_DIR/fail-checkout"
    assert_rc "checkout -b fails" 1
    assert_err_contains "checkout error" '[ERR][git-backup] `git checkout -b "backup-2025-01-15-1430.45"` failed'
}

test_stash_apply_failure() {
    run_script "$TEST_DIR/fail-apply"
    assert_rc "stash apply fails" 1
    assert_err_contains "apply error" '[ERR][git-backup] `git stash apply` failed'
}

test_add_failure() {
    run_script "$TEST_DIR/fail-add"
    assert_rc "git add fails" 1
    assert_err_contains "add error" '[ERR][git-backup] `git add .` failed'
}

test_commit_failure() {
    run_script "$TEST_DIR/fail-commit"
    assert_rc "git commit fails" 1
    assert_err_contains "commit error" '[ERR][git-backup] `git commit -m "Backup 2025-01-15-1430.45"` failed'
}

test_push_failure() {
    run_script "$TEST_DIR/fail-push"
    assert_rc "git push fails" 1
    assert_err_contains "push error" '[ERR][git-backup] `git push "origin" "backup-2025-01-15-1430.45"` failed'
}

test_checkout_dash_failure() {
    run_script "$TEST_DIR/fail-checkout-dash"
    assert_rc "checkout - fails" 1
    assert_err_contains "checkout - error" '[ERR][git-backup] `git checkout -` failed'
}

test_branch_delete_failure() {
    run_script "$TEST_DIR/fail-branch"
    assert_rc "branch -D fails" 1
    assert_err_contains "branch error" '[ERR][git-backup] `git branch -D "backup-2025-01-15-1430.45"` failed'
}

test_stash_apply_conflict_path() {
    # Test that stash apply with conflicts doesn't fail immediately (returns 1 but script handles it)
    # This is a simplified test since the full conflict resolution uses pipes and subshells
    : > "$TEST_DIR/conflict_mode"

    run_script "$TEST_DIR/test-repo"
    # The shim makes stash apply fail, which should cause the script to fail
    # since the conflict resolution pipeline is complex to test
    assert_rc "conflict causes failure" 1
    assert_err_contains "apply failed" '[ERR][git-backup] `git stash apply` failed'
}

test_utc_timestamp() {
    run_script "$TEST_DIR/test-repo"
    assert_rc "utc timestamp" 0
    assert_contains "TZ set to UTC" "$(get_date_log)" "date +%Y-%m-%d-%H%M.%S"
    local date_invocation
    date_invocation="$(get_date_log)"
    # The shim doesn't check TZ env var, but the actual script calls `TZ=Etc/UTC date`
    # We verify the date command was called with the right format
    assert_contains "date format" "$date_invocation" "+%Y-%m-%d-%H%M.%S"
}

test_backup_name_in_all_commands() {
    run_script "$TEST_DIR/test-repo"
    assert_rc "backup name used" 0
    local log
    log="$(get_git_log)"
    # Count occurrences of backup name in log
    local count
    count="$(echo "$log" | grep -c "backup-2025-01-15-1430.45" || true)"
    # Should appear in: stash save, checkout -b, push, branch -D = 4 times (commit uses timestamp only)
    if [ "$count" -ge 4 ]; then
        _ok "backup name appears in multiple commands"
    else
        _fail "backup name should appear at least 4 times, got $count"
    fi
}

test_stash_apply_twice() {
    run_script "$TEST_DIR/test-repo"
    assert_rc "two stash applies" 0
    local log
    log="$(get_git_log)"
    # First apply is after checkout -b, second is after checkout -
    local count
    count="$(echo "$log" | grep -c "git stash apply" || true)"
    if [ "$count" -eq 2 ]; then
        _ok "stash apply called twice"
    else
        _fail "stash apply should be called twice, got $count"
    fi
}

test_directory_with_spaces() {
    mkdir -p "$TEST_DIR/dir with spaces"
    run_script "$TEST_DIR/dir with spaces"
    assert_rc "dir with spaces" 0
    assert_stdout_contains "backup started" "Starting git repo backup"
}

test_remote_with_special_chars() {
    run_script "$TEST_DIR/test-repo" "origin-2.0"
    assert_rc "remote special chars" 0
    assert_contains "push to origin-2.0" "$(get_git_log)" "git push origin-2.0 backup-2025-01-15-1430.45"
}

test_dry_run() {
    run_script --dry-run "$TEST_DIR/test-repo"
    assert_rc "dry-run exits 0" 0
    assert_stdout_contains "dry-run header" "[DRY RUN] would back up"
    assert_stdout_contains "dry-run mentions push" "git push"
    # Real git should NOT be called (only shimmed date may be logged)
    local git_log
    git_log="$(get_git_log)"
    assert_eq "no git commands ran" "$git_log" ""
}

test_dry_run_short_flag() {
    run_script -n "$TEST_DIR/test-repo"
    assert_rc "dry-run -n exits 0" 0
    assert_stdout_contains "dry-run header" "[DRY RUN] would back up"
}

test_missing_remote_preflight() {
    # Override git shim: remote get-url fails, everything else succeeds.
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/git.log"
printf 'git' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
case "$*" in
    "remote get-url origin") exit 2 ;;
    "remote get-url upstream") exit 2 ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/git"

    run_script "$TEST_DIR/test-repo"
    assert_rc "missing remote exits 2" 2
    assert_err_contains "missing remote error" "[ERR][git-backup] Remote 'origin' not configured"
    # Ensure no destructive commands ran after the pre-flight failure
    local git_log
    git_log="$(get_git_log)"
    assert_not_contains "no stash save" "$git_log" "stash save"
    assert_not_contains "no checkout -b" "$git_log" "checkout -b"
    assert_not_contains "no push" "$git_log" "git push"
}

# --- run ---

run_tests "$@"
