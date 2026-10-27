#!/bin/bash
# git-remote-audit.test.sh - Live-ref audits against isolated local Git fixtures
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../scripts/git-remote-audit"
AUDIT_REAL_GIT="$(command -v git)"
export AUDIT_REAL_GIT

write_shims() {
    # Use real object graphs, but prevent fixture Git from using host configuration
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Audit GIT_COMMITTER_NAME=Audit
    export GIT_AUTHOR_EMAIL=audit@example.invalid GIT_COMMITTER_EMAIL=audit@example.invalid
    export GIT_TERMINAL_PROMPT=0
    unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
    unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    cat > "$SHIM_DIR/git" <<'SHIM'
#!/bin/bash
query=0
origin=0
for arg in "$@"; do
    if [ "$arg" = ls-remote ]; then query=1; fi
    if [ "$arg" = origin ]; then origin=1; fi
    if [ "$arg" = fetch ] && [ -f "$TEST_DIR/fail-fetch" ]; then
        printf 'fatal: https://user:private-token@example.invalid failed\n' >&2
        exit 128
    fi
done
if [ "$query" -eq 1 ] && [ "$origin" -eq 1 ] && [ -f "$TEST_DIR/invalid-advertisement" ]; then
    printf 'not-an-object-id\trefs/heads/main\n'
    exit 0
fi
exec "$AUDIT_REAL_GIT" "$@"
SHIM
    chmod +x "$SHIM_DIR/git"
}

run_detailed() { run_script -v "$@"; }

fixture_git() { "$AUDIT_REAL_GIT" "$@"; }

new_repo() {
    fixture_git init -q -b main "$1" || return
    printf '%s\n' "${2:-base}" > "$1/file"
    fixture_git -C "$1" add file || return
    fixture_git -C "$1" commit -qm base -- file
}

commit_change() {
    printf '%s\n' "$2" >> "$1/file"
    fixture_git -C "$1" commit -qm "$2" -- file
}

make_pair() {
    new_repo "$TEST_DIR/source" || return
    fixture_git clone -q --bare "$TEST_DIR/source" "$TEST_DIR/remote-a" || return
    fixture_git clone -q --bare "$TEST_DIR/source" "$TEST_DIR/remote-b" || return
    fixture_git clone -q "$TEST_DIR/remote-a" "$TEST_DIR/scan/project" || return
    fixture_git -C "$TEST_DIR/scan/project" remote add mirror "$TEST_DIR/remote-b"
}

publish_fixture() {
    fixture_git -C "$1" fetch -q --no-tags "$2" '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
}

fingerprint() {
    find "$1" -type f -exec cksum {} + | LC_ALL=C sort
}

test_help_and_usage() {
    run_detailed --help
    assert_rc 'long help succeeds' 0
    assert_stdout_contains 'help documents live refs' 'live'
    assert_stdout_contains 'help documents exit statuses' 'EXIT STATUS'
    assert_eq 'help has no diagnostics' "$(get_stderr)" ''
    run_detailed -h
    assert_rc 'short help succeeds' 0
    run_detailed --unknown
    assert_rc 'unknown option is usage error' 2
    assert_stderr_contains 'usage diagnostic names the option' "Unknown argument '--unknown'"
    run_detailed . .
    assert_rc 'extra directory is usage error' 2
    run_detailed "$TEST_DIR/missing"
    assert_rc 'missing directory is usage error' 2
    mkdir "$TEST_DIR/empty"
    run_detailed "$TEST_DIR/empty"
    assert_rc 'empty scan is not a successful audit' 2
    assert_stderr_contains 'empty scan explains absence' 'No Git repositories'
}

test_missing_git_dependency() {
    rm "$SHIM_DIR/git"
    ln -s /usr/bin/basename "$SHIM_DIR/basename"
    env PATH="$SHIM_DIR" /bin/bash "$UNDER_TEST" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc 'missing Git is a dependency error' 3
    assert_stderr_contains 'missing dependency is named' 'git is required'
}

test_matching_remotes_and_verbose() {
    make_pair || return
    run_script "$TEST_DIR/scan"
    assert_rc 'matching refs and clean checkout succeed' 0
    assert_stdout_contains 'compact report labels its columns' 'STATE'
    assert_stdout_contains 'checkout equality explicit' 'main matches'
    assert_stdout_not_contains 'default hides per-ref blocks' 'Local vs origin:'
    run_script "$TEST_DIR/scan" -v
    assert_rc 'interleaved verbose option succeeds' 0
    assert_stdout_contains 'verbose shows matching branch' 'branch main: match'
    assert_stdout_contains 'verbose retains remote equality' 'Remotes: match'
    assert_stdout_contains 'verbose retains clean working-tree state' 'Working tree: clean'
}

test_local_ahead() {
    make_pair || return
    commit_change "$TEST_DIR/scan/project" local || return
    run_detailed "$TEST_DIR/scan"
    assert_rc 'local-only commit is a finding' 4
    assert_stdout_contains 'ahead direction is local' 'branch main: ahead 1, behind 0'
    assert_stdout_contains 'remotes still agree' 'Remotes: match'
}

test_live_remote_behind_and_read_only_fetch() {
    make_pair || return
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    publish_fixture "$TEST_DIR/remote-b" "$TEST_DIR/source" || return
    local repo="$TEST_DIR/scan/project"
    local remote_tip; remote_tip="$(fixture_git -C "$TEST_DIR/source" rev-parse HEAD)"
    printf 'preserve FETCH_HEAD\n' > "$repo/.git/FETCH_HEAD"
    fixture_git -C "$repo" config fetch.prune true
    fixture_git -C "$repo" config fetch.pruneTags true
    fixture_git -C "$repo" config remote.origin.mirror true
    fixture_git -C "$repo" config remote.origin.fetch '+refs/*:refs/*'
    local before; before="$(fingerprint "$repo")"
    run_detailed "$repo"
    assert_rc 'live remote advance is found' 4
    assert_stdout_contains 'live state overrides stale tracking refs' 'branch main: ahead 0, behind 1'
    assert_eq 'entire repository contents unchanged' "$(fingerprint "$repo")" "$before"
    if fixture_git -C "$repo" cat-file -e "$remote_tip" 2>/dev/null; then
        _fail 'temporary history must not enter the local object store'
    else
        _ok 'temporary history stays outside the local object store'
    fi
}

test_diverged_history() {
    make_pair || return
    commit_change "$TEST_DIR/source" remote || return
    commit_change "$TEST_DIR/scan/project" local || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_detailed "$TEST_DIR/scan"
    assert_rc 'divergence is a finding' 4
    assert_stdout_contains 'remote disagreement is found' 'Remotes: differ'
    assert_stdout_contains 'both sides counted' 'branch main: diverged (ahead 1, behind 1)'
}

test_missing_branches_in_both_directions() {
    make_pair || return
    fixture_git -C "$TEST_DIR/source" branch remote-only
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    fixture_git -C "$TEST_DIR/scan/project" branch local-only
    run_detailed "$TEST_DIR/scan"
    assert_rc 'missing branches are findings' 4
    assert_stdout_contains 'remote-only branch identified' 'branch remote-only: missing locally'
    assert_stdout_contains 'local-only branch identified' 'branch local-only: missing on remote'
    assert_stdout_contains 'remote mismatch lists absence' 'mirror=missing'
}

test_tag_objects_and_missing_tags() {
    make_pair || return
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" tag -a release -m first
    fixture_git -C "$repo" tag local-only
    publish_fixture "$TEST_DIR/remote-a" "$repo" || return
    fixture_git -C "$TEST_DIR/source" tag -a release -m second
    fixture_git -C "$TEST_DIR/source" tag remote-only
    publish_fixture "$TEST_DIR/remote-b" "$TEST_DIR/source" || return
    run_detailed "$repo"
    assert_rc 'tag differences are findings' 4
    assert_stdout_contains 'annotation object mismatch is found' 'tag release: differs'
    assert_stdout_contains 'missing remote tag identified' 'tag local-only: missing on remote'
    assert_stdout_contains 'missing local tag identified' 'tag remote-only: missing locally'
}

test_dirty_tree_is_separate_from_ref_equality() {
    make_pair || return
    printf 'unstaged\n' >> "$TEST_DIR/scan/project/file"
    printf 'untracked\n' > "$TEST_DIR/scan/project/private-name"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'dirty worktree is a finding' 4
    assert_stdout_contains 'dirty state reported separately' 'Working tree: dirty'
    assert_stdout_contains 'refs still equal' 'Local vs origin: match'
    assert_stdout_not_contains 'private file names not exposed' 'private-name'
}

test_unreachable_remote_continues_without_false_parity() {
    make_pair || return
    fixture_git -C "$TEST_DIR/scan/project" remote add broken "$TEST_DIR/absent"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'unreachable remote makes audit incomplete' 1
    assert_stdout_contains 'remote parity is unknown' 'Remotes: unknown'
    assert_stdout_contains 'healthy remote still compared' 'Local vs origin: match'
    assert_stderr_contains 'failed remote named' "remote 'broken'"
    assert_stdout_not_contains 'no successful full parity claim' 'Remotes: match'
}

test_fetch_failure_is_unknown_and_redacts_credentials() {
    make_pair || return
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    touch "$TEST_DIR/fail-fetch"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'history failure makes audit incomplete' 1
    assert_stdout_contains 'unavailable counts not invented' 'ahead/behind unknown'
    assert_stdout_contains 'other remote still compared' 'Local vs mirror: match'
    assert_stderr_not_contains 'credential omitted from diagnostics' 'private-token'
    assert_stdout_not_contains 'credential omitted from report' 'private-token'
}

test_discovery_default_recursive_and_symlinks() {
    make_pair || return
    fixture_git clone -q "$TEST_DIR/remote-a" "$TEST_DIR/scan/group/deep"
    fixture_git clone -q "$TEST_DIR/remote-a" "$TEST_DIR/scan/project/nested"
    ln -s "$TEST_DIR/scan/project" "$TEST_DIR/scan/alias"
    run_detailed "$TEST_DIR/scan"
    assert_stdout_contains 'immediate root discovered' 'Repository: ./project'
    assert_stdout_not_contains 'deeper repo omitted by default' 'Repository: ./group/deep'
    assert_stdout_not_contains 'nested repo omitted by default' 'Repository: ./project/nested'
    run_detailed -rv "$TEST_DIR/scan"
    assert_stdout_contains 'recursive group discovered' 'Repository: ./group/deep'
    assert_stdout_contains 'recursive nested repo discovered' 'Repository: ./project/nested'
    assert_stdout_not_contains 'symlink not followed' 'Repository: ./alias'
    assert_stdout_not_contains 'Git metadata not traversed' '/.git/'
}

test_default_current_directory_and_dash_path() {
    make_pair || return
    (cd "$TEST_DIR/scan" && run_detailed)
    assert_rc 'omitted directory uses cwd' 0
    assert_stdout_contains 'cwd child found' 'Repository: ./project'
    mv "$TEST_DIR/scan" "$TEST_DIR/-scan"
    (cd "$TEST_DIR" && run_detailed -- -scan)
    assert_rc 'dash-prefixed positional accepted' 0
}

test_bare_and_linked_worktree_roots() {
    make_pair || return
    fixture_git clone -q --bare "$TEST_DIR/remote-a" "$TEST_DIR/scan/archive"
    fixture_git -C "$TEST_DIR/scan/project" worktree add -q -b task "$TEST_DIR/scan/linked"
    local before; before="$(fingerprint "$TEST_DIR/scan")"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'local task branch is a finding' 4
    assert_stdout_contains 'bare root found without suffix' 'Repository: ./archive'
    assert_stdout_contains 'bare state explicit' 'Working tree: bare'
    assert_stdout_contains 'linked root found' 'Repository: ./linked'
    assert_eq 'shared repository and worktrees unchanged' "$(fingerprint "$TEST_DIR/scan")" "$before"
}

test_no_remotes_and_detached_head() {
    new_repo "$TEST_DIR/solo" || return
    run_detailed "$TEST_DIR/solo"
    assert_rc 'no remotes is a finding' 4
    assert_stdout_contains 'no remotes explicit' 'Remotes: none'
    make_pair || return
    fixture_git -C "$TEST_DIR/scan/project" checkout -q --detach
    run_detailed "$TEST_DIR/scan"
    assert_rc 'detached head is a finding' 4
    assert_stdout_contains 'detached state explicit' 'HEAD: detached'
}

test_unborn_head_and_empty_remote() {
    fixture_git init -q --bare -b main "$TEST_DIR/empty-remote"
    fixture_git init -q -b main "$TEST_DIR/empty-local"
    fixture_git -C "$TEST_DIR/empty-local" remote add origin "$TEST_DIR/empty-remote"
    run_detailed "$TEST_DIR/empty-local"
    assert_rc 'empty named refs match' 0
    assert_stdout_contains 'unborn head explicit' 'HEAD: unborn main'
    assert_stdout_contains 'one remote not claimed as multi-remote parity' 'Remotes: not comparable (1 remote)'
    assert_stdout_contains 'empty refs stated' 'Local vs origin: match (0 refs)'
}

test_shallow_counts_are_not_invented() {
    make_pair || return
    commit_change "$TEST_DIR/source" second || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    fixture_git clone -q --depth 1 "file://$TEST_DIR/remote-a" "$TEST_DIR/shallow"
    run_detailed "$TEST_DIR/shallow"
    assert_rc 'equal shallow tips can be verified' 0
    commit_change "$TEST_DIR/source" third || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    local before; before="$(fingerprint "$TEST_DIR/shallow")"
    run_detailed "$TEST_DIR/shallow"
    assert_rc 'unequal shallow history is incomplete' 1
    assert_stdout_contains 'shallow limitation explicit' 'ahead/behind unknown: shallow history'
    assert_eq 'shallow state unchanged' "$(fingerprint "$TEST_DIR/shallow")" "$before"
}

test_special_directory_names_and_alternates() {
    make_pair || return
    local repo
    repo="$TEST_DIR/scan/space : quote\" and
newline"
    mv "$TEST_DIR/scan/project" "$repo"
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_detailed "$TEST_DIR/scan"
    assert_rc 'special directory name audited' 4
    assert_stdout_contains 'alternate object path quoted safely' 'branch main: ahead 0, behind 1'
}

test_shallow_remote_cannot_modify_full_local_repository() {
    make_pair || return
    commit_change "$TEST_DIR/source" second || return
    commit_change "$TEST_DIR/source" third || return
    fixture_git clone -q --bare --depth 1 "file://$TEST_DIR/source" "$TEST_DIR/shallow-remote"
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" remote set-url origin "$TEST_DIR/shallow-remote"
    local before; before="$(fingerprint "$repo")"
    run_detailed "$repo"
    assert_rc 'truncated remote history is incomplete' 1
    assert_stdout_contains 'truncated counts explicit' 'ahead/behind unknown'
    assert_eq 'shallow remote cannot change local Git metadata' "$(fingerprint "$repo")" "$before"
}

test_temporary_storage_cleanup_after_failed_fetch() {
    make_pair || return
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    touch "$TEST_DIR/fail-fetch"
    mkdir "$TEST_DIR/temporary"
    TMPDIR="$TEST_DIR/temporary" run_detailed "$TEST_DIR/scan"
    assert_rc 'fetch failure returned' 1
    assert_eq 'private temporary files removed on failure' "$(find "$TEST_DIR/temporary" -mindepth 1 -print)" ''
}

test_inherited_repository_environment_does_not_redirect_audit() {
    make_pair || return
    new_repo "$TEST_DIR/other" || return
    GIT_DIR="$TEST_DIR/other/.git" GIT_WORK_TREE="$TEST_DIR/other" run_detailed "$TEST_DIR/scan"
    assert_rc 'discovered repository inspected independently' 0
    assert_stdout_contains 'actual remotes inspected' 'Local vs origin: match'
}

test_broken_repository_does_not_hide_other_results() {
    make_pair || return
    mkdir -p "$TEST_DIR/scan/broken/.git"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'broken Git metadata makes audit incomplete' 1
    assert_stderr_contains 'broken repository identified' 'Repository ./broken:'
    assert_stdout_contains 'healthy repository still checked' 'Local vs origin: match'
}

test_unrelated_history_counts() {
    make_pair || return
    new_repo "$TEST_DIR/unrelated" 'unrelated root' || return
    commit_change "$TEST_DIR/unrelated" unrelated || return
    fixture_git -C "$TEST_DIR/scan/project" remote set-url origin "$TEST_DIR/unrelated"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'unrelated branch history is a finding' 4
    assert_stdout_contains 'both histories counted from their roots' 'branch main: diverged (ahead 1, behind 2)'
}

test_bundle_configuration_cannot_write_refs_or_config() {
    make_pair || return
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    fixture_git -C "$TEST_DIR/source" bundle create "$TEST_DIR/history.bundle" --branches || return
    cat > "$TEST_DIR/bundles" <<EOF
[bundle]
version = 1
mode = all
heuristic = creationToken
[bundle "history"]
uri = $TEST_DIR/history.bundle
creationToken = 1
EOF
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" config fetch.bundleURI "$TEST_DIR/bundles"
    local before; before="$(fingerprint "$repo")"
    run_detailed "$repo"
    assert_rc 'ordinary comparison works with bundle configuration' 4
    assert_stdout_contains 'remote count still available' 'branch main: ahead 0, behind 1'
    assert_eq 'bundle optimization cannot change refs or configuration' "$(fingerprint "$repo")" "$before"
    fixture_git -C "$repo" fsck --full > "$TEST_DIR/fsck" 2>&1
    assert_eq 'repository remains valid after temporary objects are removed' "$?" 0
}

test_broken_nested_git_cannot_inherit_parent_identity() {
    make_pair || return
    mkdir -p "$TEST_DIR/scan/project/nested/.git"
    run_detailed "$TEST_DIR/scan/project"
    assert_rc 'broken nested root makes audit incomplete' 1
    assert_stderr_contains 'broken nested root identified' 'Repository ./nested:'
    assert_stdout_contains 'real root still compared' 'Local vs origin: match'
    assert_stdout_not_contains 'no duplicate successful comparison' 'Summary: 2 repositories, 0 with findings, 0 errors'
}

test_comparison_failure_cannot_claim_remote_match() {
    make_pair || return
    printf '#!/bin/bash\nexit 1\n' > "$SHIM_DIR/sort"
    chmod +x "$SHIM_DIR/sort"
    run_detailed "$TEST_DIR/scan"
    assert_rc 'failed comparison is incomplete' 1
    assert_stdout_contains 'remote parity explicitly unknown' 'Remotes: unknown'
    assert_stdout_not_contains 'failed comparison cannot claim parity' 'Remotes: match'
}

test_compact_deduplicates_ref_name_gaps() {
    make_pair || return
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" branch private-topic-one
    fixture_git -C "$repo" branch private-topic-two
    fixture_git -C "$repo" tag old-backup-tag
    fixture_git -C "$TEST_DIR/source" branch remote-topic
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/scan"
    assert_rc 'ref gaps retain findings status' 4
    assert_eq 'name gaps distinguished from tip differences' "$(get_stdout | awk '$2 == "./project" { print $1 }')" REFS
    assert_stdout_contains 'checkout still explicitly matches' 'main matches'
    assert_stdout_contains 'branch gaps counted once across comparisons' '3 branch-name gaps'
    assert_stdout_contains 'tag gap counted once across remotes' '1 tag-name gap'
    assert_stdout_not_contains 'topic inventory hidden by default' 'private-topic-one'
    assert_stdout_not_contains 'tag inventory hidden by default' 'old-backup-tag'
    assert_stdout_contains 'inspection command provided' 'git-remote-audit -v'
}

test_compact_keeps_branch_direction_and_tag_mismatches() {
    make_pair || return
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" tag -a release -m first
    publish_fixture "$TEST_DIR/remote-b" "$repo" || return
    fixture_git -C "$TEST_DIR/source" tag -a release -m second
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/scan"
    assert_rc 'compact differences retain findings status' 4
    assert_stdout_contains 'tip differences require review' 'REVIEW'
    assert_stdout_contains 'behind direction and remote preserved' 'behind 1 vs origin'
    assert_stdout_contains 'matching other remote preserved' 'matches mirror'
    assert_stdout_contains 'annotated tag mismatch visible' '1 tag differs'
    local oid; oid="$(fixture_git -C "$TEST_DIR/source" rev-parse HEAD)"
    assert_stdout_not_contains 'hashes omitted from compact output' "${oid:0:12}"
}

test_compact_prioritizes_failures_and_counts_queries() {
    make_pair || return
    fixture_git clone -q "$TEST_DIR/remote-a" "$TEST_DIR/scan/a-matching"
    fixture_git -C "$TEST_DIR/scan/project" remote set-url origin "$TEST_DIR/missing-origin"
    fixture_git -C "$TEST_DIR/scan/project" remote set-url mirror "$TEST_DIR/missing-mirror"
    run_script "$TEST_DIR/scan"
    assert_rc 'compact incomplete state retained' 1
    assert_stdout_contains 'failed remotes identified in the result' 'unavailable: mirror, origin'
    assert_stdout_contains 'incomplete repositories counted' '1 incomplete'
    assert_stdout_contains 'failed queries counted separately' '2 remote queries failed'
    local error_line; error_line="$(get_stdout | awk '$1 == "ERROR" && $2 == "./project" { print NR }')"
    local ok_line; ok_line="$(get_stdout | awk '$1 == "OK" && $2 == "./a-matching" { print NR }')"
    if [ -n "$error_line" ] && [ -n "$ok_line" ] && [ "$error_line" -lt "$ok_line" ]; then
        _ok 'failures sorted ahead of matching repositories'
    else
        _fail 'failures must sort ahead of matching repositories'
    fi
    assert_eq 'one compact row per repository' "$(get_stdout | awk '$2 ~ /^\.\// { n++ } END { print n+0 }')" 2
}

test_compact_keeps_dirty_detached_and_shallow_unknown_visible() {
    make_pair || return
    printf 'dirty\n' >> "$TEST_DIR/scan/project/file"
    run_script "$TEST_DIR/scan"
    assert_rc 'dirty remains a finding' 4
    assert_stdout_contains 'dirty state visible' 'dirty worktree'
    assert_stdout_contains 'ref equality independent of dirty state' 'main matches'
    fixture_git -C "$TEST_DIR/scan/project" checkout -q --detach
    run_script "$TEST_DIR/scan"
    assert_stdout_contains 'detached state visible' 'detached HEAD'
    fixture_git clone -q --depth 1 "file://$TEST_DIR/remote-a" "$TEST_DIR/shallow"
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/shallow"
    assert_rc 'unknown shallow history remains incomplete' 1
    assert_stdout_contains 'unknown counts explicit' 'history unknown vs origin'
}

test_compact_noncurrent_tip_difference_is_not_downgraded_to_names() {
    make_pair || return
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" branch topic
    fixture_git -C "$TEST_DIR/source" checkout -qb topic
    commit_change "$TEST_DIR/source" topic-change || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/scan"
    assert_rc 'other branch difference remains a finding' 4
    assert_stdout_contains 'checkout equality visible' 'main matches'
    assert_stdout_contains 'noncurrent branch tip difference surfaced' '1 other branch differs'
    assert_stdout_contains 'tip difference requires review' 'REVIEW'
}

test_compact_invalid_advertisement_is_an_unavailable_remote() {
    make_pair || return
    touch "$TEST_DIR/invalid-advertisement"
    run_script "$TEST_DIR/scan"
    assert_rc 'invalid remote snapshot is incomplete' 1
    assert_stdout_contains 'matching claim limited to checked remotes' 'main matches reachable remotes'
    assert_stdout_contains 'invalid snapshot remote identified' 'unavailable: origin'
    assert_stdout_contains 'invalid query counted as failed' '1 remote query failed'
}

test_compact_detects_values_missing_from_the_baseline() {
    make_pair || return
    fixture_git clone -q --bare "$TEST_DIR/remote-a" "$TEST_DIR/baseline"
    fixture_git -C "$TEST_DIR/scan/project" remote add aaa "$TEST_DIR/baseline"
    fixture_git -C "$TEST_DIR/source" checkout -qb topic
    commit_change "$TEST_DIR/source" first || return
    publish_fixture "$TEST_DIR/remote-b" "$TEST_DIR/source" || return
    commit_change "$TEST_DIR/source" second || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/scan"
    assert_rc 'differences between later remotes are findings' 4
    assert_stdout_contains 'checked-out branch still matches' 'main matches'
    assert_stdout_contains 'later remote values require review' 'REVIEW'
    assert_stdout_contains 'later remote values are compared' '1 other branch differs'
    assert_stdout_contains 'missing copies are counted independently' '1 branch-name gap'
}

test_compact_head_name_is_not_confused_by_a_tag() {
    make_pair || return
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" tag main
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/scan"
    assert_rc 'ambiguous short name still reports findings' 4
    assert_stdout_contains 'current branch direction preserved with same-named tag' 'main: behind 1 vs origin'
    assert_stdout_not_contains 'short-name disambiguation does not leak into branch identity' 'heads/main'
    fixture_git -C "$TEST_DIR/remote-a" update-ref -d refs/heads/main
    run_script "$TEST_DIR/scan"
    assert_stdout_contains 'missing current branch requires review' 'REVIEW'
    assert_stdout_contains 'missing current branch identifies remote' 'absent on origin'
}

test_compact_unborn_state_survives_remote_comparison() {
    make_pair || return
    fixture_git init -q -b main "$TEST_DIR/unborn"
    fixture_git -C "$TEST_DIR/unborn" remote add origin "$TEST_DIR/remote-a"
    run_script "$TEST_DIR/unborn"
    assert_rc 'missing unborn branch is a finding' 4
    assert_stdout_contains 'unborn state remains explicit' 'main (unborn)'
    assert_stdout_contains 'remote branch presence remains explicit' 'absent locally (origin)'
}

test_compact_failed_local_comparison_cannot_claim_a_match() {
    make_pair || return
    cat > "$SHIM_DIR/sort" <<'SHIM'
#!/bin/bash
if [ "$#" -eq 0 ]; then
    count=0
    if [ -f "$TEST_DIR/comparisons" ]; then read -r count < "$TEST_DIR/comparisons"; fi
    count=$((count + 1))
    printf '%s\n' "$count" > "$TEST_DIR/comparisons"
    if [ "$count" -eq 2 ]; then exit 1; fi
fi
exec /usr/bin/sort "$@"
SHIM
    chmod +x "$SHIM_DIR/sort"
    run_script "$TEST_DIR/scan"
    assert_rc 'local comparison failure is incomplete' 1
    assert_stdout_contains 'unchecked remote remains explicit beside checked matches' 'main: not checked vs mirror; matches origin'
    assert_stdout_not_contains 'partial comparison cannot claim all remotes match' 'main matches'
}

test_compact_numeric_remote_names_remain_visible() {
    make_pair || return
    local repo="$TEST_DIR/scan/project"
    fixture_git -C "$repo" remote rename mirror 0
    fixture_git -C "$repo" remote set-url 0 "$TEST_DIR/missing"
    run_script "$TEST_DIR/scan"
    assert_rc 'unreachable numeric remote is incomplete' 1
    assert_stdout_contains 'zero-named remote limits the matching claim' 'main matches reachable remotes'
    assert_stdout_contains 'single repository uses singular wording' 'Summary: 1 repository,'
    fixture_git -C "$repo" remote set-url 0 "$TEST_DIR/remote-b"
    fixture_git -C "$repo" remote add 1 "$TEST_DIR/remote-b"
    commit_change "$TEST_DIR/source" remote || return
    publish_fixture "$TEST_DIR/remote-a" "$TEST_DIR/source" || return
    run_script "$TEST_DIR/scan"
    assert_rc 'numeric matching remotes coexist with a difference' 4
    assert_stdout_contains 'numeric matching remotes are individually named' 'matches 0, 1'
}

run_tests "$@"
