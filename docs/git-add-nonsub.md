# git-add-nonsub

Stage a git repository inside another git repository without treating it as a submodule.

Git has a feature called **submodules** for linking one repo into another: when you `git add` a directory containing its own `.git`, git records only a pointer to a specific commit in the inner repo, not the actual files. Submodules are powerful but add workflow friction (everyone cloning the outer repo needs to run `git submodule update` to fetch the inner contents; updates require coordinated commits in both repos).

If you don't want that coordination overhead -- e.g. you've vendored a third-party library, you want to snapshot an external project's source into your tree, or you're copying code you'll modify independently -- you want the nested directory's files tracked as plain files in the outer repo. This script makes that work by temporarily moving the inner `.git` directory aside so git sees regular files during `git add`, then putting the inner `.git` back.

## Quick start

From your outer repository's working tree:

```bash
$ git-add-nonsub vendor/some-lib
[INF] Backup created at /var/folders/.../tmp.xxxxx.
[INF] Running git add on 'vendor/some-lib'...
[INF] git add completed successfully.
[INF] Restored .git directory.
```

Now `vendor/some-lib` is staged in your outer repo with all its files, not as a submodule pointer.

## Common examples

**Stage a vendored library:**

```bash
$ git-add-nonsub third_party/react
```

**Stage a cloned project you want to absorb:**

```bash
$ git-add-nonsub lib/parsing-lib
```

**Verify the directory has a `.git` before running:**

```bash
$ ls -la vendor/some-lib/.git
drwxr-xr-x  13 user  staff  416 Apr 21 10:00 .git

$ git-add-nonsub vendor/some-lib
```

## How it works

When you try to `git add` a directory that contains a `.git` subdirectory, git treats it as a submodule and only records a commit reference -- not the actual files. This script works around that by:

1. Moving the nested `.git` directory to a temporary location
2. Running `git add` on the now-`.git`-free directory (so git sees regular files)
3. Restoring the `.git` directory to its original location

The inner repository remains intact and functional after the operation completes. You can continue working in it or remove the `.git` entirely if you no longer need it as a separate repo.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Display help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Error (missing directory argument, directory doesn't exist, no `.git` found, backup/restore failed, or `git add` failed) |

### Dependencies

- `git`

### Warnings

**Do not interrupt the script while it's running.** If the script is killed after moving `.git` but before restoring it, your nested repository will be in an inconsistent state (its `.git` directory will be in a temp location). The script prints the temp directory path when it creates the backup -- you can manually move it back if needed.

**Do not run on uncommitted work in the nested repo.** The script doesn't check the inner repo's status before proceeding. If you have uncommitted changes in the nested repository, consider committing them first or understanding that you're staging whatever state the working tree is currently in.

**This doesn't remove the inner `.git` permanently.** After running this script, the nested directory still contains a `.git` subdirectory -- it's just been added to the outer repo. If you commit and then run `git status` again, git will still see the nested repo as a potential submodule. If you want to fully absorb the nested repo, you'll need to remove its `.git` directory manually after running this script.
