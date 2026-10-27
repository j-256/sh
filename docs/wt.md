# wt

Create a task worktree, update it from your integration branch, land it with a fast-forward, and remove it when the work is integrated. `wt` checks the Git state around each step and keeps conflicts or failed checkouts available for inspection.

The workflow uses one primary checkout on its integration branch and disposable worktrees for tasks. Storage, sparse checkout, protected directories, git-crypt readiness, and integration guards work across repositories through Git configuration. The built-in lifecycle uses local state and never fetches, pushes, stashes, resets, prunes, or force-removes a worktree.

## Quick start

Run from a Git repository with its primary checkout on the integration branch:

```bash
$ task_worktree="$(wt improve-search)"
$ cd "$task_worktree"
# Edit, test, and commit the task
$ task_worktree="$(wt sync)"
# Inspect and test the synchronized result
$ primary_worktree="$(wt land)"
$ cd "$primary_worktree"
# Verify the integrated checkout
$ wt close improve-search
```

`start` is the default command. Successful mutating commands print only the directory to use next; progress and errors go to stderr. Capturing that path does not change your shell's directory. Use `cd` explicitly.

An existing task resumes its registered worktree. An existing branch without a worktree is attached. A new branch starts at the primary checkout's local `HEAD`, even when the command runs from another task. Uncommitted edits are left in their original checkout.

## Common examples

**Keep worktrees in a chosen directory**

```bash
$ git config --local wt.root "$HOME/worktrees"
$ wt improve-search
# Override that setting for one task
$ wt start --root "$HOME/review-trees" review-search
```

**Check a task from the primary checkout**

```bash
$ wt status improve-search
# From the task worktree, the branch argument is optional
$ wt status
```

**Select several directories without a full checkout**

```bash
$ wt start --scope packages/search --scope tools improve-search
```

**Infer one project and include its hooks**

```bash
$ git config --local wt.sparseWorktrees true
$ git config --local --add wt.projectRoot packages
$ git config --local --add wt.includeScope .githooks
$ cd packages/search/src
$ wt improve-search
# Selects packages/search and .githooks
```

**Require a deliberate selection for a sensitive directory**

```bash
$ git config --local --add wt.protectedPath private
$ wt start --scope packages/search improve-search
# To work on the protected directory explicitly
$ wt start --scope private update-private-config
```

## Sparse checkout and protected paths

`--scope` selects cone-mode sparse checkout. The `wt.sparseWorktrees=true`, `wt.includeScope`, and `wt.protectedPath` settings also enable sparse mode. Without them a repository receives a full checkout.

With no explicit scope, the caller's top-level directory is inferred. A configured `wt.projectRoot` changes that inference to the immediate child of that directory. For nested project roots, the longest matching root wins. Run from below a project or pass `--scope` at the repository or project root.

`wt.includeScope` adds mandatory directories, such as hooks or shared tooling. Every configured directory must be present as a tree at the checkout commit; paths are repository-relative, with no absolute paths, traversal, or newline characters. An attached branch is checked against its own commit.

`wt.protectedPath` prevents an inferred scope or included directory from bringing in a protected subtree implicitly. An explicit `--scope` must cover the selected protected content, including when a broader selected directory contains that subtree. Selecting one protected child does not authorize an include to bring in its protected siblings. This is a workflow guard; it does not change Git permissions or replace access control.

Cone mode also checks out files at the repository root and files beside ancestor directories of each selected scope. A narrow scope therefore does not guarantee that every file outside its subtree is absent.

## git-crypt handling

Before creating a worktree, `wt` reads the checkout commit's file paths and Git attributes. It recognizes `filter=git-crypt` and named filters such as `filter=git-crypt-team` without assuming where encrypted files live. Excluded files need no key; root and ancestor files included by cone mode are checked too.

Each selected git-crypt filter needs its matching key file under the Git common directory's `git-crypt/keys/`, its `filter.<name>.required` setting enabled, and configured clean and smudge drivers. The unnamed key uses `default`; the named example uses `team`. Key contents are never read or printed by `wt`.

Linked worktrees receive a symlink from their Git administration directory to the common git-crypt state before encrypted checkout. Keys are shared rather than copied. Locking removes shared key availability, but it does not remove plaintext already checked out in other worktrees. Inspect and manage every affected worktree when locking; shared key state does not coordinate plaintext cleanup or provide independent locks for each worktree.

Full checkouts without selected git-crypt files use native `git worktree add` checkout, including its `post-checkout` hook arguments. Sparse and encrypted checkouts defer checkout until their sparse selection or shared key state is ready.

This preflight checks key availability and filter configuration. Git's checkout runs the actual smudge driver and validates the key material. `wt` never disables a required filter. If deferred sparse or encrypted checkout fails, the registered worktree and branch remain available for recovery. Ordinary full checkouts retain Git's native failure cleanup, which can remove the new worktree registration while retaining its branch. No unlock operation runs automatically.

Use `wt.protectedPath` as well when an encrypted directory should require explicit selection even while unlocked.

## Synchronization and integration

The primary checkout's checked-out branch is the integration target. It can be called `main`, `trunk`, or another name; it is not resolved from a remote default branch. Keep that checkout on the intended branch.

`sync` requires a clean, available, unlocked task without an active Git operation. It refuses a configured upstream or a matching remote-tracking ref because rebasing could rewrite published history. Those checks use local refs and do not prove that a branch was never published.

Synchronization uses `git rebase --fork-point` to avoid replaying old copies of integration commits after that branch was rewritten. This depends on the primary branch's reflog. Commits once present there and then discarded can be excluded from the task as well; an expired reflog falls back to ordinary rebase behavior. Inspect conflicts and recover excluded commits from the task's reflog when needed.

Linear task history is the default. To preserve intentional merge topology, set `git config --local wt.linearHistory false`; `sync` then uses `--rebase-merges`, and `land` permits task merge commits. Inspect the resulting resolutions and tree.

`land` requires clean task and primary worktrees with no active Git operation. It fast-forwards the integration branch and verifies matching task and primary commits and trees. An already integrated task returns the primary path without moving it. Approval belongs to your workflow; the executable does not prompt for confirmation.

## Integration guards

Use repeated `wt.landGuard` values to run trusted Bash commands before local integration. This can enforce a repository's PR workflow or another local policy without installing a companion beside the script:

```bash
$ git config --local --add wt.landGuard '/path/to/local-policy "$1" "$2" "$3" "$4"'
```

Each command runs through `/bin/bash -c` from the primary checkout. Its positional arguments are the Git common directory (`$1`), primary checkout (`$2`), integration branch (`$3`), and task branch (`$4`). `$0` identifies the land guard. Every guard must succeed; the first nonzero status is propagated and prevents integration. Both output streams go to stderr, preserving path-only command results.

Only configure commands you trust: guards execute as your user and can have their own side effects. No adjacent program is discovered implicitly. `start`, `status`, `sync`, and `close` do not invoke land guards or require their programs.

## Cleanup and replayed commits

`close` checks linked worktree identity, cleanliness, locks, active Git operations, and containment in the integration branch. It uses non-forcing `git worktree remove`, retaining Git's refusal for initialized submodules, and deletes the integrated local branch. It also recognizes matching metadata from the older nested worktree layout.

Tracked, staged, and untracked changes block cleanup. Ignored files are informational and are deleted with the disposable worktree. Keep durable data elsewhere.

After an external rebase or squash integration, commit ancestry may differ while the content is identical. Explicit recovery options permit cleanup only after exact Git tree equality:

```bash
$ wt close --equivalent-tree improve-search
# If integration has advanced, compare against a specific ancestor instead
$ wt close --equivalent-tree-at "$merge_commit" improve-search
```

`--equivalent-tree-at` requires a full SHA-1 or SHA-256 commit ID that is an ancestor of integration. These options can delete an uncontained local branch after establishing identical content. A failure after removing the worktree but before deleting its branch is reported as a partial result; inspect the remaining branch.

---

## Reference

### Commands and options

| Command or flag | Behavior |
| --- | --- |
| `wt [options] <branch>` | Start, attach, or resume a task |
| `wt start [options] <branch>` | Explicit form of the default command |
| `wt status [branch]` | Report lifecycle state and the next step |
| `wt sync [branch]` | Rebase the clean task onto local integration |
| `wt land [branch]` | Run guards and fast-forward clean local integration |
| `wt close [options] [branch]` | Remove an integrated task and its local branch |
| `-r`, `--root PATH` | Absolute storage directory for start |
| `-s`, `--scope PATH` | Sparse directory relative to the repository; repeatable |
| `-e`, `--equivalent-tree` | Compare a replayed task with the integration tree for close |
| `-a`, `--equivalent-tree-at COMMIT` | Compare a replayed task with a full ancestor commit ID for close |
| `-h`, `--help` | Show self-contained usage |

Value-taking flags also accept `--root=PATH`, `--scope=PATH`, `--equivalent-tree-at=COMMIT`, and glued short values. Options and positionals may be interleaved. `--` ends option parsing; use explicit `start` for a branch whose name is a command, such as `wt start -- close`.

### Git configuration

| Key | Value |
| --- | --- |
| `wt.root` | Repeatable absolute preferred directories in order; followed by XDG fallback and overridden strictly by `--root` |
| `wt.sparseWorktrees` | Boolean; default `false` |
| `wt.projectRoot` | Repeatable relative directory whose immediate children are projects |
| `wt.includeScope` | Repeatable relative directory included in every sparse task |
| `wt.protectedPath` | Repeatable relative directory requiring explicit scope selection |
| `wt.linearHistory` | Boolean; default `true` |
| `wt.landGuard` | Repeatable trusted Bash command invoked before land |

### Environment variables

| Variable | Meaning |
| --- | --- |
| `WT_PROGRAM_NAME` | Optional displayed command name supplied by a caller wrapper |
| `XDG_STATE_HOME` | Absolute storage base when no root is supplied; tasks use `wt/worktrees/` beneath it |
| `HOME` | Supplies the default state base, `$HOME/.local/state` |

Configured `wt.root` directories are tried in order, followed by the XDG storage directory. An unavailable candidate is skipped; an invalid relative or empty candidate refuses creation. `--root` is a strict override and does not fall back. Resume returns its existing path before storage selection.

Each new directory is named `<repository>-<branch-name>.XXXXXX`, with unsafe name characters replaced by hyphens and a random suffix. Returned paths use Git's registered spelling.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Runtime failure or safety refusal |
| `2` | Invalid usage, configuration, or unsupported repository state |
| `3` | Missing dependency or unsupported Git version |
| Other nonzero status | Propagated rejection from a configured land guard |

### Dependencies

- Bash 3.2+ and Git 2.43+, including [committed attribute inspection](https://git-scm.com/docs/git-check-attr/2.43.0)
- The configured Git filter drivers when their files are selected, including git-crypt for a git-crypt repository
- Programs referenced by a land guard, only when that guard runs
