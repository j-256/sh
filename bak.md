# bak

Rename files in place by appending `.bak` to the name. When the `.bak` version already exists, it rotates recursively (`file.bak` → `file.bak.bak` → `file.bak.bak.bak`), so the single-`.bak` file is always the most recent backup.

Useful before editing a config file by hand, destructive operations on production code, or anytime you want a quick snapshot without involving git.

## Quick start

```bash
$ bak config.yaml
$ ls config*
config.yaml.bak
```

## Common examples

**Multiple files at once:**

```bash
bak database.sql server.conf
```

**Dry-run** to see what would happen first:

```bash
$ bak --dry-run report.pdf
bak: Would move: report.pdf -> report.pdf.bak
```

**Verbose** to see each rename:

```bash
$ bak -v notes.txt
bak: Moving notes.txt -> notes.txt.bak
```

**Existing `.bak` rotates automatically:**

```bash
$ bak config.yaml  # first time
$ ls config*
config.yaml.bak

$ bak config.yaml  # second time
$ ls config*
config.yaml.bak  config.yaml.bak.bak
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-v, --verbose` | Print filenames as they are backed up |
| `-d, --dry-run` | Simulate actions without making changes |
| `-h, --help` | Display help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | File not found or move failed |

### Behavior

- If the target file doesn't exist, fails with `bak: file: No such file`
- Backup rotation is recursive -- no limit on depth
- With multiple files, processes each in order; failure on one doesn't stop the rest
