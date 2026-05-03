# unbak

[View script](../unbak)

Restore backed-up files by renaming `file.ext.bak` to `file.ext`. This is the inverse of `bak` — when you've backed something up and want to undo that change, `unbak` puts the backed-up version back in place.

The script won't overwrite an existing file at the destination — if `file.ext` already exists, it skips with an error. When you have multiple backup generations in a chain (`file.bak`, `file.bak.bak`, `file.bak.bak.bak`), `unbak` restores from the oldest to newest recursively, so you get back the entire history.

## Quick start

```bash
$ ls
config.yaml.bak

$ unbak config.yaml.bak
$ ls
config.yaml
```

## Common examples

**Multiple files at once:**

```bash
unbak notes.txt.bak report.pdf.bak
```

**Dry-run** to see what would happen without making changes:

```bash
$ unbak --dry-run server.conf.bak
unbak: Would move: server.conf.bak -> server.conf
```

**Verbose** to see each restore operation:

```bash
$ unbak -v database.sql.bak
unbak: Moving: database.sql.bak -> database.sql
```

**Restore a backup chain** (oldest first, recursively):

```bash
$ ls config*
config.yaml  config.yaml.bak  config.yaml.bak.bak

$ unbak config.yaml.bak.bak
$ ls config*
config.yaml  config.yaml.bak
```

**Won't overwrite existing files:**

```bash
$ ls
report.pdf  report.pdf.bak

$ unbak report.pdf.bak
[ERR][unbak] report.pdf: File already exists, skipping
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-v, --verbose` | Print filenames as they are restored |
| `-d, --dry-run` | Simulate actions without making changes |
| `-h, --help` | Display help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime failure (source file missing, destination exists, `mv` failed) |
| 2 | Usage error (unknown option) |

### Behavior

- If the source `.bak` file doesn't exist, fails with `[ERR][unbak] file: No such file`
- If the destination (without `.bak`) already exists, skips with `[ERR][unbak] file: File already exists, skipping`
- Restores backup chains recursively from oldest to newest — `file.bak.bak.bak` restores to `file.bak.bak`, then to `file.bak`, then to `file`
- With multiple files, processes each in order; failure on one doesn't stop the rest
