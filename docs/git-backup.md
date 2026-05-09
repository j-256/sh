# git-backup

[View script](../git-backup)

Save work in progress to a remote tag without polluting your current branch. This creates a timestamped backup tag on the remote, pushes everything (tracked and untracked), then cleans up locally and restores your working state.

Useful before risky operations like interactive rebases, hard resets, or experimental checkouts where you want an offsite safety copy but don't want the backup cluttering your local branch history. The remote acts as offsite storage -- you can pull the backup tag back later if something goes wrong.

Tags (rather than branches) are used because backups are point-in-time snapshots that shouldn't move, shouldn't appear in branch listings or PR base/compare dropdowns, and are harder to clobber by accident.

## Quick start

```bash
$ git-backup .
Starting git repo backup 2026-04-21-1830.42
Saved working directory and index state WIP on main: 1a39f82 Update claude-settings.json
HEAD is now at 1a39f82 Update claude-settings.json
...
[detached HEAD 3f8e901] Backup 2026-04-21-1830.42
 2 files changed, 45 insertions(+), 3 deletions(-)
Enumerating objects: 7, done.
...
To github.com:user/repo.git
 * [new tag]         backup-2026-04-21-1830.42 -> backup-2026-04-21-1830.42
Switched to branch 'main'
On branch main
...
Deleted tag 'backup-2026-04-21-1830.42' (was 3f8e901)
```

The backup tag remains on the remote, but your local branch, local tag, and working directory are back to their original state.

## Common examples

**Back up before a risky rebase:**

```bash
$ git-backup /path/to/repo
# ... backup completes ...
$ git rebase -i HEAD~10
```

If the rebase goes wrong, fetch and checkout the backup tag to recover.

**Push to a non-default remote:**

```bash
$ git-backup . backup-remote
```

Useful if you have a separate backup remote configured or want to avoid pushing to `origin`.

## How it works

1. Stashes all tracked and untracked changes with `git stash save --include-untracked`
2. Detaches HEAD so the backup commit lands on no branch
3. Applies the stash onto the detached HEAD
4. Commits everything with message "Backup YYYY-MM-DD-HHMM.SS"
5. Tags that commit `backup-YYYY-MM-DD-HHMM.SS` (UTC timestamp)
6. Pushes the tag to the remote
7. Switches back to your original branch
8. Restores your working state from the stash
9. Deletes the local tag (the remote tag persists)

If `git stash apply` encounters conflicts during step 3, the script automatically resolves them by keeping the stashed changes (`git checkout --theirs`).

## Recovery

To restore from a backup:

```bash
$ git fetch origin tag backup-2026-04-21-1830.42
$ git checkout backup-2026-04-21-1830.42
```

`git checkout <tag>` drops you into a detached HEAD at the tagged commit; branch off it with `git checkout -b recover-foo` if you want to commit on top.

Or merge it into your current branch:

```bash
$ git fetch origin tag backup-2026-04-21-1830.42
$ git merge backup-2026-04-21-1830.42
```

Delete the remote backup tag when you no longer need it:

```bash
$ git push origin :refs/tags/backup-2026-04-21-1830.42
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

- **Requires write access to the remote** -- the script pushes a tag to the specified remote. Make sure you have push permission.
- **Backup tags persist on the remote** -- they won't be deleted automatically. Clean them up periodically with `git push origin :refs/tags/backup-...` or via your remote's UI.
- **Not a replacement for proper version control** -- use feature branches and commits for real work. This is for emergency backups and "just in case" snapshots.
