#!/bin/bash
# wt.test.sh - Tests for wt
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "${TEST_HELPERS:-$SCRIPT_DIR/test-helpers.sh}"

UNDER_TEST="${WT_UNDER_TEST:-$SCRIPT_DIR/../scripts/wt}"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT

write_shims() {
    export XDG_STATE_HOME="$TEST_DIR/state"
}

run_wt_from() {
    local cwd="$1"
    shift
    (
        cd "$cwd" || exit 1
        env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" "$UNDER_TEST" "$@"
    ) >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

init_repo() {
    local repo="${1:-$TEST_DIR/repo}"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "WT Test"
    git -C "$repo" config user.email "wt@example.invalid"
    printf 'base\n' > "$repo/base.txt"
    printf 'ignored/\n' > "$repo/.gitignore"
    git -C "$repo" add -- base.txt .gitignore
    git -C "$repo" commit -q -m initial -- base.txt .gitignore
    printf '%s\n' "$repo"
}

commit_path() {
    local repo="$1"
    local path="$2"
    local content="$3"
    local message="$4"
    mkdir -p "$(dirname "$repo/$path")"
    printf '%s\n' "$content" > "$repo/$path"
    git -C "$repo" add -- "$path"
    git -C "$repo" commit -q -m "$message" -- "$path"
}

start_task() {
    local repo="$1"
    local branch="$2"
    local root="${3:-$TEST_DIR/worktrees}"
    run_wt_from "$repo" --root "$root" "$branch"
    [ "$(get_rc)" = 0 ] || return 1
    get_stdout
}

start_legacy_task() {
    local repo="$1"
    local branch="$2"
    local suffix="$3"
    local parent="$TEST_DIR/worktrees/repo-worktree.$suffix"
    local worktree="$parent/worktree"
    local marker="$parent/.wt-metadata"
    git -C "$repo" branch "$branch"
    mkdir -p "$parent"
    git -C "$repo" worktree add -q "$worktree" "$branch"
    worktree="$(cd "$worktree" && pwd -P)"
    parent="${worktree%/*}"
    marker="$parent/.wt-metadata"
    git config --file "$marker" wt.version 1
    git config --file "$marker" wt.commondir "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"
    git config --file "$marker" wt.branchref "refs/heads/$branch"
    git config --file "$marker" wt.worktree "$worktree"
    printf '%s\n' "$worktree"
}

assert_path_absent() {
    local label="$1"
    local path="$2"
    if [ ! -e "$path" ]; then
        assert_eq "$label" 0 0
    else
        assert_eq "$label" 1 0
    fi
}

assert_dir_exists() {
    local label="$1"
    local path="$2"
    if [ -d "$path" ]; then
        assert_eq "$label" 0 0
    else
        assert_eq "$label" 1 0
    fi
}

test_help_and_usage() {
    run_script --help
    assert_rc "long help exits 0" 0
    assert_stdout_contains "help names commands" "wt close"
    assert_stdout_contains "help documents fallback" "wt.root"

    run_script -h
    assert_rc "short help exits 0" 0

    run_script
    assert_rc "missing branch exits 2" 2
    assert_stderr_contains "missing branch is explained" "A task branch is required"

    run_script --unknown task/test
    assert_rc "unknown option exits 2" 2

    run_script --root= task/test
    assert_rc "empty root exits 2" 2
}

test_start_creates_and_resumes_full_worktree() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/create)"
    local worktree_root; worktree_root="$(cd "$TEST_DIR/worktrees" && pwd -P)"

    assert_eq "start exits 0" "$(get_rc)" 0
    assert_file_exists "tracked file is checked out" "$worktree/base.txt"
    assert_eq "task branch is checked out" "$(git -C "$worktree" branch --show-current)" "task/create"
    assert_contains "worktree name includes repository and branch" "$(basename "$worktree")" "repo-task-create."
    assert_eq "worktree is created directly under the root" "$(dirname "$worktree")" "$worktree_root"
    assert_eq "stdout contains only the result path" "$(get_stdout)" "$worktree"

    run_wt_from "$repo" task/create --root "$TEST_DIR/unused"
    assert_rc "repeat start exits 0" 0
    assert_eq "repeat start resumes the same path" "$(get_stdout)" "$worktree"
    assert_path_absent "unused root is not created during resume" "$TEST_DIR/unused"
}

test_start_attaches_an_existing_branch() {
    local repo; repo="$(init_repo)"
    git -C "$repo" branch task/existing

    local worktree; worktree="$(start_task "$repo" task/existing)"
    assert_eq "existing branch start exits 0" "$(get_rc)" 0
    assert_eq "existing branch is attached" "$(git -C "$worktree" branch --show-current)" "task/existing"
    assert_stderr_contains "existing branch is reported" "Attaching existing branch"
}

test_full_start_preserves_native_post_checkout_hook_arguments() {
    local repo; repo="$(init_repo)"
    local hooks="$TEST_DIR/hooks"
    local branch
    local worktree
    local head; head="$(git -C "$repo" rev-parse HEAD)"
    local zero; zero="$(printf '%s' "$head" | tr '0-9a-f' '0')"
    mkdir -p "$hooks"
    cat > "$hooks/post-checkout" <<'HOOK'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/post-checkout.args"
HOOK
    chmod +x "$hooks/post-checkout"
    git -C "$repo" config core.hooksPath "$hooks"
    git -C "$repo" branch task/existing-hook
    for branch in task/new-hook task/existing-hook; do
        : > "$TEST_DIR/post-checkout.args"
        worktree="$(start_task "$repo" "$branch")"
        assert_rc "$branch creation succeeds" 0
        assert_eq "$branch invokes native hook exactly once" "$(cat "$TEST_DIR/post-checkout.args")" "$(printf '%s\n%s\n1' "$zero" "$head")"
        assert_file_exists "$branch checks out content" "$worktree/base.txt"
    done
}

test_separate_git_metadata_is_refused_consistently() {
    local repo; repo="$(init_repo)"
    git -C "$repo" init -q --separate-git-dir "$TEST_DIR/git-admin"
    git -C "$repo" config core.worktree "$repo"
    run_wt_from "$repo" --root "$TEST_DIR/worktrees" separate-admin
    assert_rc "unsupported primary metadata refuses" 2
    assert_stderr_contains "unsupported layout is explained" "real .git directory"
    assert_path_absent "metadata refusal creates no worktree storage" "$TEST_DIR/worktrees"
}

test_start_uses_primary_head_when_called_from_another_task() {
    local repo; repo="$(init_repo)"
    local first; first="$(start_task "$repo" task/first)"
    commit_path "$first" first-only.txt first first
    local first_head; first_head="$(git -C "$first" rev-parse HEAD)"
    local primary_head; primary_head="$(git -C "$repo" rev-parse HEAD)"

    run_wt_from "$first" --root "$TEST_DIR/other-worktrees" task/second
    assert_rc "nested start exits 0" 0
    local second; second="$(get_stdout)"
    assert_eq "new task starts at primary head" "$(git -C "$second" rev-parse HEAD)" "$primary_head"
    assert_not_contains "new task excludes caller-only commit" "$(git -C "$second" rev-list HEAD)" "$first_head"
    assert_path_absent "new task excludes caller-only file" "$second/first-only.txt"
}

test_sparse_start_infers_scope_and_adds_hooks() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" proj/demo/demo.txt demo demo
    commit_path "$repo" other/other.txt other other
    commit_path "$repo" .githooks/pre-commit hook hook
    git -C "$repo" config wt.sparseWorktrees true
    git -C "$repo" config wt.projectRoot proj
    git -C "$repo" config wt.includeScope .githooks

    run_wt_from "$repo/proj/demo" --root "$TEST_DIR/worktrees" task/sparse
    assert_rc "sparse start exits 0" 0
    local worktree; worktree="$(get_stdout)"
    assert_file_exists "inferred project is checked out" "$worktree/proj/demo/demo.txt"
    assert_file_exists "hooks are checked out" "$worktree/.githooks/pre-commit"
    assert_path_absent "unselected subtree is absent" "$worktree/other/other.txt"
    assert_contains "sparse list contains project" "$(git -C "$worktree" sparse-checkout list)" "proj/demo"
    assert_contains "sparse list contains hooks" "$(git -C "$worktree" sparse-checkout list)" ".githooks"
}

test_sparse_root_requires_explicit_scope() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" proj/demo/demo.txt demo demo
    git -C "$repo" config wt.sparseWorktrees true

    run_wt_from "$repo" --root "$TEST_DIR/worktrees" task/no-scope
    assert_rc "root sparse start exits 2" 2
    assert_stderr_contains "root scope refusal is explained" "pass --scope"
    assert_eq "failed start does not create branch" "$(git -C "$repo" show-ref --verify --quiet refs/heads/task/no-scope; printf '%s' "$?")" 1
}

test_sparse_explicit_scopes() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" one/one.txt one one
    commit_path "$repo" two/two.txt two two
    commit_path "$repo" sec/secret.txt secret secret
    git -C "$repo" config wt.sparseWorktrees true

    run_wt_from "$repo" --root "$TEST_DIR/worktrees" --scope one -stwo task/multiple
    assert_rc "repeated scope start exits 0" 0
    local worktree; worktree="$(get_stdout)"
    assert_file_exists "first explicit scope is checked out" "$worktree/one/one.txt"
    assert_file_exists "second explicit scope is checked out" "$worktree/two/two.txt"
    assert_path_absent "sec is absent without selection" "$worktree/sec/secret.txt"
}

test_status_reports_landable_and_integrated_states() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/status)"

    run_wt_from "$worktree" status
    assert_rc "initial status exits 0" 0
    assert_stdout_contains "initial branch is integrated" "RELATION            integrated"
    assert_stdout_contains "initial next step is close" "wt close task/status"

    commit_path "$worktree" task.txt task task
    run_wt_from "$worktree" status
    assert_rc "advanced status exits 0" 0
    assert_stdout_contains "advanced branch is landable" "RELATION            landable"
    assert_stdout_contains "advanced next step is land" "wt land task/status after approval"
}

test_sync_rebases_local_task_onto_primary() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/sync)"
    commit_path "$worktree" task.txt task task
    commit_path "$repo" primary.txt primary primary

    run_wt_from "$worktree" sync
    assert_rc "sync exits 0" 0
    assert_eq "sync returns task path" "$(get_stdout)" "$worktree"
    git -C "$repo" merge-base --is-ancestor main task/sync
    assert_eq "primary is ancestor after sync" "$?" 0
    assert_file_exists "rebased task contains primary change" "$worktree/primary.txt"
    assert_file_exists "rebased task retains task change" "$worktree/task.txt"
    assert_stderr_not_contains "ordinary sync skips no primary history" "skipping"
}

test_sync_replays_only_task_commits_after_primary_rewrite() {
    local repo; repo="$(init_repo)"
    local initial; initial="$(git -C "$repo" rev-parse HEAD)"
    commit_path "$repo" base.txt one 'primary: one'
    commit_path "$repo" base.txt two 'primary: two'
    local worktree; worktree="$(start_task "$repo" task/rewrite)"
    commit_path "$worktree" task.txt task task
    # Replay the primary's commits onto a new base that conflicts with the first of them
    git -C "$repo" reset -q --hard "$initial"
    commit_path "$repo" base.txt upstream 'upstream: base'
    commit_path "$repo" base.txt one-replayed 'primary: one'
    commit_path "$repo" base.txt two 'primary: two'

    run_wt_from "$worktree" sync
    assert_rc "sync after primary rewrite exits 0" 0
    assert_eq "only the task commit is replayed" "$(git -C "$repo" log --format=%s main..task/rewrite)" task
    git -C "$repo" merge-base --is-ancestor main task/rewrite
    assert_eq "rewritten primary is ancestor after sync" "$?" 0
    assert_eq "task keeps the rewritten primary content" "$(cat "$worktree/base.txt")" two
    assert_stderr_contains "sync reports skipped pre-rewrite commits" "skipping 2 commits"
}

test_linear_history_is_default_and_merge_history_needs_repo_opt_out() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/merged)"
    git -C "$worktree" switch -q -c task/side
    commit_path "$worktree" side.txt side side
    git -C "$worktree" switch -q task/merged
    commit_path "$worktree" task.txt task task
    git -C "$worktree" merge --no-ff -m 'Merge side' task/side >/dev/null
    local merge_head; merge_head="$(git -C "$worktree" rev-parse HEAD)"
    local primary_head; primary_head="$(git -C "$repo" rev-parse HEAD)"

    run_wt_from "$worktree" status
    assert_rc "status accepts merge-bearing task" 0
    assert_stdout_contains "linear history is the default" "LINEAR_HISTORY      true"
    assert_stdout_contains "status identifies task merge" "TASK_MERGE_COMMIT   $merge_head"
    assert_stdout_contains "status directs merge review" "inspect and flatten task merge commits"

    run_wt_from "$worktree" sync
    assert_rc "default sync refuses merge-bearing task" 1
    assert_stderr_contains "sync explains merge refusal" "contains merge commit"
    assert_eq "sync did not rewrite the merge" "$(git -C "$worktree" rev-parse HEAD)" "$merge_head"

    run_wt_from "$worktree" land
    assert_rc "default land refuses merge-bearing task" 1
    assert_stderr_contains "land explains merge refusal" "contains merge commit"
    assert_eq "primary stays unchanged" "$(git -C "$repo" rev-parse HEAD)" "$primary_head"

    git -C "$repo" config wt.linearHistory false
    commit_path "$repo" primary.txt primary primary
    run_wt_from "$worktree" sync
    assert_rc "opted-out sync recreates merge history" 0
    assert_eq "opted-out task retains a merge" "$(git -C "$worktree" rev-list --count --merges main..task/merged)" 1
    assert_file_exists "opted-out task retains side change" "$worktree/side.txt"
    assert_file_exists "opted-out task contains primary change" "$worktree/primary.txt"

    run_wt_from "$worktree" land
    assert_rc "opted-out land accepts merge history" 0
    assert_eq "primary includes the merge" "$(git -C "$repo" rev-list --count --merges main)" 1
}

test_invalid_linear_history_setting_fails_closed() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/invalid-policy)"
    git -C "$repo" config wt.linearHistory maybe

    run_wt_from "$worktree" status
    assert_rc "invalid policy is rejected" 2
    assert_stderr_contains "invalid policy is explained" "wt.linearHistory must be true or false"
}

test_sync_refuses_remote_tracking_evidence() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/published)"
    git -C "$repo" update-ref refs/remotes/origin/task/published refs/heads/task/published

    run_wt_from "$worktree" sync
    assert_rc "published sync exits 1" 1
    assert_stderr_contains "published sync is explained" "matching remote-tracking ref"
}

test_land_fast_forwards_and_verifies_primary() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/land)"
    commit_path "$worktree" task.txt task task
    local task_head; task_head="$(git -C "$worktree" rev-parse HEAD)"

    run_wt_from "$worktree" land
    assert_rc "land exits 0" 0
    assert_eq "land returns primary path" "$(get_stdout)" "$(cd "$repo" && pwd -P)"
    assert_eq "primary advances to task" "$(git -C "$repo" rev-parse HEAD)" "$task_head"
    assert_stderr_contains "land verification is reported" "Verified local integration"
}

test_land_refuses_diverged_primary() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/diverged)"
    commit_path "$worktree" task.txt task task
    commit_path "$repo" primary.txt primary primary

    run_wt_from "$worktree" land
    assert_rc "diverged land exits 1" 1
    assert_stderr_contains "diverged land directs sync" "run wt sync"
}

test_close_removes_only_integrated_worktree_and_branch() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/close)"
    commit_path "$worktree" task.txt task task
    run_wt_from "$worktree" land
    assert_rc "pre-close land exits 0" 0

    run_wt_from "$repo" close task/close
    assert_rc "close exits 0" 0
    assert_eq "close returns primary path" "$(get_stdout)" "$(cd "$repo" && pwd -P)"
    assert_path_absent "worktree is removed" "$worktree"
    assert_dir_exists "shared worktree root remains" "$TEST_DIR/worktrees"
    git -C "$repo" show-ref --verify --quiet refs/heads/task/close
    assert_eq "task branch is deleted" "$?" 1
    assert_stderr_contains "close completion is reported" "Closed task/close"
}

test_close_refuses_unintegrated_work() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/unintegrated)"
    commit_path "$worktree" task.txt task task

    run_wt_from "$repo" close task/unintegrated
    assert_rc "unintegrated close exits 1" 1
    assert_stderr_contains "unintegrated close is explained" "commits not contained"
    assert_file_exists "unintegrated worktree remains" "$worktree/task.txt"
    git -C "$repo" show-ref --verify --quiet refs/heads/task/unintegrated
    assert_eq "unintegrated branch remains" "$?" 0
}

test_close_accepts_only_exact_replayed_tree() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/replayed)"
    commit_path "$worktree" task.txt task task
    local task_head; task_head="$(git -C "$worktree" rev-parse HEAD)"
    GIT_COMMITTER_DATE='2001-01-01T00:00:00Z' git -C "$repo" cherry-pick "$task_head" >/dev/null

    run_wt_from "$repo" close task/replayed
    assert_rc "ordinary close rejects replayed branch" 1
    run_wt_from "$repo" close --equivalent-tree task/replayed
    assert_rc "equivalent-tree close accepts matching replay" 0
    assert_path_absent "replayed worktree is removed" "$worktree"

    worktree="$(start_task "$repo" task/different)"
    commit_path "$worktree" other.txt other other
    run_wt_from "$repo" close --equivalent-tree task/different
    assert_rc "equivalent-tree close rejects a different tree" 1
    assert_file_exists "different worktree remains" "$worktree/other.txt"
}

test_close_accepts_matching_primary_ancestor_after_later_commits() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/delayed)"
    commit_path "$worktree" task.txt task task
    local task_head; task_head="$(git -C "$worktree" rev-parse HEAD)"
    GIT_COMMITTER_DATE='2001-01-01T00:00:00Z' git -C "$repo" cherry-pick "$task_head" >/dev/null
    local merged_head; merged_head="$(git -C "$repo" rev-parse HEAD)"
    commit_path "$repo" later.txt later later

    run_wt_from "$repo" close --equivalent-tree task/delayed
    assert_rc "current tree rejects delayed replay" 1
    run_wt_from "$repo" close --equivalent-tree-at "$(git -C "$repo" rev-parse HEAD)" task/delayed
    assert_rc "later tree rejects delayed replay" 1
    run_wt_from "$repo" close --equivalent-tree-at "$merged_head" task/delayed
    assert_rc "matching ancestor closes delayed replay" 0
    assert_path_absent "delayed worktree is removed" "$worktree"
}

test_close_refuses_dirty_files() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/files)"
    printf 'dirty\n' >> "$worktree/base.txt"

    run_wt_from "$repo" close task/files
    assert_rc "dirty close exits 1" 1
    assert_stderr_contains "dirty close is explained" "tracked or untracked changes"
    assert_file_exists "dirty worktree remains" "$worktree/base.txt"
}

test_close_removes_ignored_files_with_worktree() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/ignored)"
    mkdir -p "$worktree/ignored"
    printf 'generated\n' > "$worktree/ignored/artifact.txt"

    run_wt_from "$worktree" status
    assert_rc "ignored status exits 0" 0
    assert_stdout_contains "ignored files are reported" "IGNORED_FILES       yes"
    assert_stdout_contains "ignored files do not block close" "NEXT                 wt close task/ignored"

    run_wt_from "$repo" close task/ignored
    assert_rc "ignored close exits 0" 0
    assert_path_absent "worktree and ignored file are removed" "$worktree"
    git -C "$repo" show-ref --verify --quiet refs/heads/task/ignored
    assert_eq "ignored task branch is deleted" "$?" 1
}

test_close_refuses_locked_and_active_worktrees() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" task/protected)"
    git -C "$repo" worktree lock --reason test "$worktree"

    run_wt_from "$repo" close task/protected
    assert_rc "locked close exits 1" 1
    assert_stderr_contains "locked close is explained" "worktree is locked"
    git -C "$repo" worktree unlock "$worktree"

    local merge_head; merge_head="$(git -C "$worktree" rev-parse --path-format=absolute --git-path MERGE_HEAD)"
    git -C "$worktree" rev-parse HEAD > "$merge_head"
    run_wt_from "$repo" close task/protected
    assert_rc "active-operation close exits 1" 1
    assert_stderr_contains "active operation is explained" "MERGE_HEAD"
}

test_close_allows_unmapped_gitlink_outside_sparse_scope() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" selected/file.txt selected selected
    local head; head="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" update-index --add --cacheinfo 160000 "$head" orphan-submodule
    git -C "$repo" commit -q -m gitlink
    git -C "$repo" config wt.sparseWorktrees true

    run_wt_from "$repo/selected" --root "$TEST_DIR/worktrees" task/gitlink
    assert_rc "gitlink sparse start exits 0" 0
    local worktree; worktree="$(get_stdout)"
    local submodule_rc=0
    git -C "$worktree" submodule status --recursive >/dev/null 2>&1 || submodule_rc=$?
    assert_eq "fixture submodule status fails" "$submodule_rc" 128

    run_wt_from "$repo" close task/gitlink
    assert_rc "unmapped gitlink close exits 0" 0
    assert_path_absent "unmapped gitlink worktree is removed" "$worktree"
}

test_close_refuses_metadata_mismatch() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_legacy_task "$repo" task/metadata MISMATCH)"
    local marker="${worktree%/*}/.wt-metadata"
    git config --file "$marker" wt.branchref refs/heads/task/other

    run_wt_from "$repo" close task/metadata
    assert_rc "metadata mismatch exits 1" 1
    assert_stderr_contains "metadata mismatch is explained" "does not match"
    assert_file_exists "mismatched worktree remains" "$worktree/base.txt"
}

test_close_cleans_legacy_wrapper_parent() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_legacy_task "$repo" task/legacy LEGACY)"
    local parent="${worktree%/*}"

    run_wt_from "$repo" close task/legacy
    assert_rc "legacy close exits 0" 0
    assert_path_absent "legacy worktree is removed" "$worktree"
    assert_path_absent "legacy wrapper parent is removed" "$parent"
}

# Synthetic filter drivers exercise readiness without a git-crypt installation
configure_crypt() {
    local repo="$1"
    local key="${2:-default}"
    local filter=git-crypt
    [ "$key" = default ] || filter="git-crypt-$key"
    git -C "$repo" config "filter.$filter.required" true
    git -C "$repo" config "filter.$filter.clean" cat
    git -C "$repo" config "filter.$filter.smudge" cat
    mkdir -p "$repo/.git/git-crypt/keys"
    printf 'synthetic key\n' > "$repo/.git/git-crypt/keys/$key"
}

test_storage_configuration_and_explicit_override() {
    local repo; repo="$(init_repo)"
    git -C "$repo" config wt.root "$TEST_DIR/configured trees"
    run_wt_from "$repo" configured-root
    assert_rc "configured storage succeeds" 0
    assert_contains "configured root is used" "$(get_stdout)" "/configured trees/"
    run_wt_from "$repo" --root "$TEST_DIR/override" explicit-root
    assert_rc "explicit storage succeeds" 0
    assert_contains "explicit root overrides config" "$(get_stdout)" "/override/"
}

test_default_storage_uses_xdg_state() {
    local repo; repo="$(init_repo)"
    run_wt_from "$repo" xdg-root
    assert_rc "default storage succeeds" 0
    assert_contains "default storage is namespaced state" "$(get_stdout)" "/state/wt/worktrees/"
}

test_invalid_storage_refuses_before_creating_branch() {
    local repo; repo="$(init_repo)"
    git -C "$repo" config wt.root relative/path
    run_wt_from "$repo" bad-root
    assert_rc "relative configured root refuses" 2
    git -C "$repo" show-ref --verify --quiet refs/heads/bad-root
    assert_eq "invalid root does not create branch" "$?" 1
}

test_explicit_scope_enables_sparse_checkout() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" packages/ui/file.txt ui ui
    commit_path "$repo" packages/api/file.txt api api
    run_wt_from "$repo" start --root "$TEST_DIR/trees" --scope=packages/ui scoped
    assert_rc "explicit scope selects sparse mode" 0
    local worktree; worktree="$(get_stdout)"
    assert_file_exists "explicit scope exists" "$worktree/packages/ui/file.txt"
    assert_path_absent "other package is absent" "$worktree/packages/api/file.txt"
}

test_project_scope_inference_is_configurable() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" packages/ui/src/file.txt ui ui
    commit_path "$repo" packages/api/file.txt api api
    git -C "$repo" config wt.sparseWorktrees true
    git -C "$repo" config wt.projectRoot packages
    run_wt_from "$repo/packages/ui/src" --root "$TEST_DIR/trees" inferred
    assert_rc "configured project root succeeds" 0
    local worktree; worktree="$(get_stdout)"
    assert_file_exists "inferred child exists" "$worktree/packages/ui/src/file.txt"
    assert_path_absent "sibling project is absent" "$worktree/packages/api/file.txt"
}

test_protected_paths_require_explicit_selection() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" config/private/file.txt fixture fixture
    git -C "$repo" config wt.sparseWorktrees true
    git -C "$repo" config wt.protectedPath config/private
    run_wt_from "$repo/config" --root "$TEST_DIR/trees" implicit-protected
    assert_rc "inferred ancestor of protected path refuses" 1
    git -C "$repo" show-ref --verify --quiet refs/heads/implicit-protected
    assert_eq "refusal creates no branch" "$?" 1
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope config explicit-protected
    assert_rc "explicit ancestor permits protected scope" 0
    assert_file_exists "explicit protected file exists" "$(get_stdout)/config/private/file.txt"
}

test_protected_includes_cannot_select_sensitive_content_implicitly() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" public/file.txt public public
    commit_path "$repo" private/file.txt fixture fixture
    git -C "$repo" config wt.includeScope private
    git -C "$repo" config wt.protectedPath private
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope public implicit-include
    assert_rc "included protected scope needs explicit selection" 1
}

test_locked_crypt_is_checked_before_branch_creation() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" vault/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'vault/** filter=git-crypt' attributes
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope vault locked
    assert_rc "missing crypt key refuses" 1
    assert_stderr_contains "crypt refusal names filter" "git-crypt"
    git -C "$repo" show-ref --verify --quiet refs/heads/locked
    assert_eq "locked start creates no branch" "$?" 1
    configure_crypt "$repo"
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope vault unlocked
    assert_rc "configured default key permits checkout" 0
    assert_file_exists "unlocked fixture is checked out" "$(get_stdout)/vault/item.txt"
}

test_named_crypt_key_is_required_independently() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" team/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'team/** filter=git-crypt-team' attributes
    configure_crypt "$repo"
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope team named-locked
    assert_rc "default key does not unlock named filter" 1
    configure_crypt "$repo" team
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope team named-unlocked
    assert_rc "matching named key permits checkout" 0
}

test_crypt_required_filter_and_driver_cannot_be_disabled() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" vault/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'vault/** filter=git-crypt' attributes
    configure_crypt "$repo"
    git -C "$repo" config filter.git-crypt.required false
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope vault disabled-filter
    assert_rc "disabled required filter refuses" 1
    git -C "$repo" config filter.git-crypt.required true
    git -C "$repo" config --unset filter.git-crypt.smudge
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope vault missing-driver
    assert_rc "missing smudge driver refuses" 1
}

test_cone_ancestor_files_are_checked_for_encryption() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" packages/ui/file.txt ui ui
    commit_path "$repo" packages/credentials.txt synthetic fixture
    commit_path "$repo" .gitattributes 'packages/credentials.txt filter=git-crypt' attributes
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope packages/ui ancestor-crypt
    assert_rc "encrypted ancestor file refuses sparse checkout" 1
    assert_stderr_contains "ancestor file is diagnosed" "packages/credentials.txt"
}

test_excluded_crypt_paths_do_not_require_keys() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" public/file.txt public public
    commit_path "$repo" vault/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'vault/** filter=git-crypt' attributes
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope public public-only
    assert_rc "excluded locked content does not block" 0
    assert_path_absent "locked directory is absent" "$(get_stdout)/vault/item.txt"
    run_wt_from "$repo" --root "$TEST_DIR/trees" full-locked
    assert_rc "full checkout still checks encrypted files" 1
}

test_attaching_branch_uses_its_own_committed_attributes() {
    local repo; repo="$(init_repo)"
    git -C "$repo" checkout -qb encrypted-task
    commit_path "$repo" vault/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'vault/** filter=git-crypt' attributes
    git -C "$repo" checkout -q main
    run_wt_from "$repo" --root "$TEST_DIR/trees" encrypted-task
    assert_rc "attached task attributes are inspected" 1
    assert_contains "task remains unattached" "$(git -C "$repo" worktree list --porcelain)" "branch refs/heads/main"
    assert_not_contains "no task worktree is registered" "$(git -C "$repo" worktree list --porcelain)" "branch refs/heads/encrypted-task"
}

test_land_guards_receive_context_and_keep_stdout_clean() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" guarded)"
    commit_path "$worktree" feature.txt feature feature
    local before; before="$(git -C "$repo" rev-parse HEAD)"
    # shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- The configured command expands variables in its child process
    git -C "$repo" config wt.landGuard 'printf "guard output\n"; test "$2" = "$PWD" && test "$3" = main && test "$4" = guarded && test -d "$1"; exit 2'
    run_wt_from "$worktree" sync
    assert_rc "sync does not invoke land guard" 0
    run_wt_from "$worktree" land
    assert_rc "guard rejection is propagated" 2
    assert_eq "rejected guard leaves primary unchanged" "$(git -C "$repo" rev-parse HEAD)" "$before"
    assert_eq "guard stdout is not a result path" "$(get_stdout)" ""
    assert_stderr_contains "guard output is routed to stderr" "guard output"
    # shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- The configured command expands variables in its child process
    git -C "$repo" config wt.landGuard 'test "$2" = "$PWD" && test "$3" = main && test "$4" = guarded && test -d "$1"'
    git -C "$repo" config --add wt.landGuard 'printf "second guard\n"'
    run_wt_from "$worktree" land
    assert_rc "all configured guards accept context" 0
    assert_eq "accepted guard preserves path-only stdout" "$(get_stdout)" "$(cd "$repo" && pwd -P)"
    assert_stderr_contains "additional guard runs" "second guard"
}

test_invalid_sparse_policy_refuses_closed() {
    local repo; repo="$(init_repo)"
    git -C "$repo" config wt.sparseWorktrees maybe
    run_wt_from "$repo" --root "$TEST_DIR/trees" invalid-sparse
    assert_rc "invalid sparse boolean refuses" 2
    git -C "$repo" config wt.sparseWorktrees true
    git -C "$repo" config wt.includeScope ../outside
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope missing unsafe-include
    assert_rc "unsafe configured scope refuses" 2
}

test_extended_option_grammar() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" ui/file.txt ui ui
    run_wt_from "$repo" grammar --root="$TEST_DIR/trees" -sui
    assert_rc "interleaved glued and equal forms work" 0
    local worktree; worktree="$(get_stdout)"
    run_wt_from "$repo" close --equivalent-tree-at="$(git -C "$repo" rev-parse HEAD)" -- grammar
    assert_rc "equal recovery commit is accepted" 0
    run_wt_from "$repo" --root "$TEST_DIR/trees" start -- close
    assert_rc "reserved command can be an explicit branch" 0
    run_wt_from "$repo" close --equivalent-tree-at=
    assert_rc "empty recovery commit refuses" 2
}

write_failing_git() {
    export WT_REAL_GIT
    WT_REAL_GIT="$(command -v git)"
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
for argument in "$@"; do
    [ "$argument" != "${WT_FAIL_COMMAND:-}" ] || exit 128
done
exec "$WT_REAL_GIT" "$@"
SHIM
    chmod +x "$SHIM_DIR/git"
}

test_failed_branch_inspection_cannot_choose_the_wrong_checkout_commit() {
    local repo; repo="$(init_repo)"
    git -C "$repo" branch existing-task
    write_failing_git
    WT_FAIL_COMMAND=show-ref run_wt_from "$repo" --root "$TEST_DIR/trees" existing-task
    assert_rc "branch inspection error refuses start" 1
    assert_stderr_contains "branch inspection error is explained" "Cannot inspect local branch"
    assert_path_absent "failed branch inspection creates no storage" "$TEST_DIR/trees"
}

test_failed_git_inspection_never_reports_clean_or_rebases() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" inspection)"
    commit_path "$worktree" feature.txt feature feature
    write_failing_git
    WT_FAIL_COMMAND=status run_wt_from "$worktree" status
    assert_rc "status failure refuses state report" 1
    assert_not_contains "failed status does not claim clean" "$(get_stdout)" 'CLEAN               yes'
    WT_FAIL_COMMAND=status run_wt_from "$worktree" land
    assert_rc "failed cleanliness blocks land" 1
    WT_FAIL_COMMAND=--git-path run_wt_from "$worktree" sync
    assert_rc "failed operation inspection blocks rebase" 1
    WT_FAIL_COMMAND=for-each-ref run_wt_from "$worktree" sync
    assert_rc "failed publication inspection blocks rebase" 1
    WT_FAIL_COMMAND=merge-base run_wt_from "$worktree" status
    assert_rc "failed ancestry inspection refuses report" 1
    WT_FAIL_COMMAND=worktree run_wt_from "$worktree" status
    assert_rc "failed registry read refuses" 1
}

test_recovery_accepts_full_sha256_ancestor_ids() {
    local repo; repo="$(GIT_DEFAULT_HASH=sha256 init_repo)"
    local worktree; worktree="$(start_task "$repo" hash-recovery)"
    commit_path "$worktree" feature.txt feature feature
    commit_path "$repo" feature.txt feature replay
    local replay; replay="$(git -C "$repo" rev-parse HEAD)"
    commit_path "$repo" later.txt later later
    run_wt_from "$repo" close --equivalent-tree-at="$replay" hash-recovery
    assert_rc "full SHA-256 recovery succeeds" 0
    assert_path_absent "SHA-256 replay worktree is removed" "$worktree"
}

test_configured_directories_are_validated_at_checkout_commit() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" public/file.txt public public
    git -C "$repo" config wt.protectedPath missing/private
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope public invalid-protected
    assert_rc "missing protected directory refuses" 2
    git -C "$repo" config --unset wt.protectedPath
    git -C "$repo" config wt.projectRoot missing/packages
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope public invalid-project-root
    assert_rc "missing project root refuses" 2
}

test_protected_scope_inference_checks_cone_ancestor_files() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" private/ui/file.txt ui ui
    commit_path "$repo" private/top.txt fixture fixture
    git -C "$repo" config wt.projectRoot private
    git -C "$repo" config wt.protectedPath private
    run_wt_from "$repo/private/ui" --root "$TEST_DIR/trees" inferred-private
    assert_rc "nested inferred project still requires explicit selection" 1
}

test_failed_checkout_preserves_registered_worktree() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" vault/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'vault/** filter=git-crypt' attributes
    configure_crypt "$repo"
    git -C "$repo" config filter.git-crypt.smudge false
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope vault failed-checkout
    assert_rc "failed smudge is reported" 1
    assert_contains "failed worktree stays registered" "$(git -C "$repo" worktree list --porcelain)" 'branch refs/heads/failed-checkout'
    assert_stderr_contains "recovery is explained" 'preserved for inspection'
}

test_crypt_driver_can_find_shared_keys_in_linked_worktrees() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" vault/item.txt synthetic fixture
    commit_path "$repo" .gitattributes 'vault/** filter=git-crypt' attributes
    configure_crypt "$repo"
    # shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- The configured command expands variables in its child process
    git -C "$repo" config filter.git-crypt.smudge 'test -f "$(git rev-parse --git-dir)/git-crypt/keys/default" && cat'
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope vault sparse-crypt-state
    assert_rc "sparse crypt driver finds common key state" 0
    local worktree; worktree="$(get_stdout)"
    assert_file_exists "sparse encrypted fixture is checked out" "$worktree/vault/item.txt"
    run_wt_from "$repo" --root "$TEST_DIR/trees" full-crypt-state
    assert_rc "full crypt driver finds common key state" 0
    worktree="$(get_stdout)"
    assert_file_exists "full encrypted fixture is checked out" "$worktree/vault/item.txt"
    run_wt_from "$repo" close full-crypt-state
    assert_rc "crypt worktree cleanup succeeds" 0
    assert_file_exists "cleanup preserves shared key state" "$repo/.git/git-crypt/keys/default"
}

test_explicit_descendant_does_not_authorize_broader_protected_include() {
    local repo; repo="$(init_repo)"
    commit_path "$repo" private/chosen/file.txt chosen chosen
    commit_path "$repo" private/other/file.txt other other
    git -C "$repo" config wt.protectedPath private
    git -C "$repo" config wt.includeScope private
    run_wt_from "$repo" --root "$TEST_DIR/trees" --scope private/chosen too-broad
    assert_rc "narrow explicit scope cannot authorize protected siblings" 1
    git -C "$repo" show-ref --verify --quiet refs/heads/too-broad
    assert_eq "broader protected selection creates no branch" "$?" 1
}

test_failed_ancestry_inspection_preserves_exact_tree_recovery() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" failed-recovery)"
    commit_path "$worktree" feature.txt feature task
    commit_path "$repo" feature.txt feature replay
    write_failing_git
    WT_FAIL_COMMAND=merge-base run_wt_from "$repo" close --equivalent-tree failed-recovery
    assert_rc "ancestry inspection error refuses exact-tree cleanup" 1
    assert_dir_exists "failed ancestry keeps task worktree" "$worktree"
    git -C "$repo" show-ref --verify --quiet refs/heads/failed-recovery
    assert_eq "failed ancestry keeps task branch" "$?" 0
}

test_sourced_lifecycle_handles_inherited_errexit() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" source-task)"
    (
        cd "$worktree" || exit 1
        /bin/bash -ec '. "$1" status; printf "source-returned\n"; case "$-" in *e*) exit 0 ;; *) exit 9 ;; esac' bash "$UNDER_TEST"
    ) > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "sourced status succeeds under errexit" 0
    assert_stdout_contains "caller continues after sourcing" 'source-returned'
    (
        cd "$repo" || exit 1
        /bin/bash -e "$UNDER_TEST" --root "$TEST_DIR/other-trees" errexit-start
    ) > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "creation handles absent config under errexit" 0
}

test_ordered_storage_candidates_and_xdg_fallback() {
    local repo; repo="$(init_repo)"
    git -C "$repo" config --add wt.root "$TEST_DIR/first"
    git -C "$repo" config --add wt.root "$TEST_DIR/second"
    run_wt_from "$repo" root-first
    assert_rc "preferred root succeeds" 0
    assert_contains "first configured root wins" "$(get_stdout)" '/first/'
    git -C "$repo" config --unset-all wt.root
    printf 'blocked\n' > "$TEST_DIR/blocked-root"
    git -C "$repo" config --add wt.root "$TEST_DIR/blocked-root"
    run_wt_from "$repo" root-fallback
    assert_rc "unusable candidates fall back" 0
    assert_contains "XDG is the final fallback" "$(get_stdout)" '/state/wt/worktrees/'
}

test_explicit_storage_stays_strict_and_candidates_are_validated() {
    local repo; repo="$(init_repo)"
    git -C "$repo" config --add wt.root "$TEST_DIR/usable"
    printf 'blocked\n' > "$TEST_DIR/blocked-root"
    run_wt_from "$repo" --root "$TEST_DIR/blocked-root" strict-root
    assert_rc "explicit unavailable root refuses" 1
    assert_path_absent "explicit failure does not try fallback" "$TEST_DIR/usable"
    git -C "$repo" config --add wt.root relative/root
    run_wt_from "$repo" invalid-root-list
    assert_rc "invalid fallback list refuses" 2
    assert_path_absent "all candidates validate before creation" "$TEST_DIR/usable"
}

test_resuming_does_not_resolve_storage_candidates() {
    local repo; repo="$(init_repo)"
    local worktree; worktree="$(start_task "$repo" resume-storage)"
    git -C "$repo" config --add wt.root relative/root
    run_wt_from "$repo" resume-storage
    assert_rc "resume ignores unused root configuration" 0
    assert_eq "resume returns registered path" "$(get_stdout)" "$worktree"
}

test_program_name_override_preserves_wrapper_identity() {
    WT_PROGRAM_NAME=local-wt run_script --help
    assert_rc "wrapper display name help succeeds" 0
    assert_stdout_contains "help uses wrapper identity" 'local-wt - manage'
    WT_PROGRAM_NAME=local-wt run_script --unknown
    assert_rc "wrapper invalid argument refuses" 2
    assert_stderr_contains "diagnostic uses wrapper identity" '[ERR][local-wt]'
}

run_tests "$@"
