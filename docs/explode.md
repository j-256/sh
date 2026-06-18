# explode

[View script](../explode)

Move a directory's contents up one level, then remove the now-empty directory. The classic use case: you unzip `package-v1.2.3.zip` and it extracts to a single top-level folder `package-v1.2.3/` wrapping all the files you actually wanted at the current level.

By default, `explode` aborts without changes if any item would collide with an existing file at the destination. Use `--force` to overwrite or `--dry-run` to preview what would happen.

## Quick start

```bash
$ ls
package-v1.2.3/

$ explode package-v1.2.3

$ ls
file1.txt  file2.txt  README.md
```

The directory `package-v1.2.3/` is removed after its contents are moved up.

## Common examples

**Preview first:**

```bash
$ explode -n package-v1.2.3
Would move to .:
file1.txt
file2.txt
README.md
Would remove: package-v1.2.3
```

**See each file as it moves:**

```bash
$ explode -v package-v1.2.3
file1.txt -> ./
file2.txt -> ./
README.md -> ./
```

**Overwrite conflicts:**

```bash
$ explode package-v1.2.3
[ERR][explode] Aborting -- the following items already exist in .:
  README.md

$ explode -f package-v1.2.3
(overwrites existing files)
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-f, --force` | Overwrite existing files at the destination |
| `-n, --dry-run` | Show what would happen without making changes |
| `-v, --verbose` | List each item as it is moved |
| `-h, --help` | Show help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (or help/dry-run completed) |
| 1 | Runtime failure: a move failed, or directory removal failed (items remain after attempted moves) |
| 2 | Usage error or precondition not met: bad/unknown/duplicate args, missing directory argument, directory doesn't exist, not a directory, or collision without `--force` |

### Dependencies

None -- uses only standard Unix utilities.
