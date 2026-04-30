# git-backup

Save work in progress to a remote branch without polluting your current branch. This creates a timestamped backup branch on the remote, pushes everything (tracked and untracked), then cleans up locally and restores your working state.

Useful before risky operations like interactive rebases, hard resets, or experimental checkouts where you want an offsite safety copy but don't want the backup cluttering your local branch history. The remote acts as offsite storage -- you can pull the backup branch back later if something goes wrong.

## Quick start

```bash
$ git-backup .
Starting git repo backup 2026-04-21-1830.42
Saved working directory and index state WIP on main: 1a39f82 Update claude-settings.json
Switched to a new branch 'backup-2026-04-21-1830.42'
On branch backup-2026-04-21-1830.42
...
[backup-2026-04-21-1830.42 3f8e901] Backup 2026-04-21-1830.42
 2 files changed, 45 insertions(+), 3 deletions(-)
Enumerating objects: 7, done.
...
To github.com:user/repo.git
 * [new branch]      backup-2026-04-21-1830.42 -> backup-2026-04-21-1830.42
Switched to branch 'main'
On branch main
...
Deleted branch backup-2026-04-21-1830.42 (was 3f8e901).
```

The backup branch remains on the remote, but your local branch and working directory are back to their original state.

## Common examples

**Back up before a risky rebase:**

```bash
$ git-backup /path/to/repo
# ... backup completes ...
$ git rebase -i HEAD~10
```

If the rebase goes wrong, fetch and checkout the backup branch to recover.

**Push to a non-default remote:**

```bash
$ git-backup . backup-remote
```

Useful if you have a separate backup remote configured or want to avoid pushing to `origin`.

## How it works

1. Stashes all tracked and untracked changes with `git stash save --include-untracked`
2. Creates a new branch named `backup-YYYY-MM-DD-HHMM.SS` (UTC timestamp)
3. Applies the stash to the new branch
4. Commits everything with message "Backup YYYY-MM-DD-HHMM.SS"
5. Pushes the branch to the remote
6. Switches back to your original branch
7. Restores your working state from the stash
8. Deletes the backup branch locally (it remains on the remote)

If `git stash apply` encounters conflicts during step 3, the script automatically resolves them by keeping the stashed changes (`git checkout --theirs`).

## Recovery

To restore from a backup:

```bash
$ git fetch origin backup-2026-04-21-1830.42
$ git checkout backup-2026-04-21-1830.42
```

Or merge it into your current branch:

```bash
$ git fetch origin backup-2026-04-21-1830.42
$ git merge backup-2026-04-21-1830.42
```

Delete the remote backup branch when you no longer need it:

```bash
$ git push origin --delete backup-2026-04-21-1830.42
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `repo_directory` | Path to the git repository (e.g., `.` for current directory) |
| `remote` | Remote name to push to (default: `origin`) |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Error during backup process (stash, checkout, push, etc.) |

### Dependencies

- `git`

### Warnings

- **Requires write access to the remote** -- the script pushes a branch to the specified remote. Make sure you have push permission.
- **Backup branches persist on the remote** -- they won't be deleted automatically. Clean them up periodically with `git push origin --delete backup-*` or via your remote's UI.
- **Not a replacement for proper version control** -- use feature branches and commits for real work. This is for emergency backups and "just in case" snapshots.
