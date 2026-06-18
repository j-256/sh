# swap

[View script](../swap)

Atomically swap two files by renaming. Useful for rotating config files (`config.prod` ↔ `config.dev`), A/B testing file variants, or any quick swap without a temporary directory.

Works in place using a temp file as intermediary. On partial failure, attempts to restore the original state.

## Quick start

```bash
$ ls
config.prod  config.dev

$ swap config.prod config.dev

$ ls
config.prod  config.dev
# Now config.prod has dev content, config.dev has prod content
```

## Common examples

**Rotate active config with backup:**

```bash
swap nginx.conf nginx.conf.old
```

**Swap test data files for different test runs:**

```bash
swap dataset-A.csv dataset-B.csv
```

**Restore a previous version** (when you've been swapping back and forth):

```bash
# First time: current ↔ backup
swap app.js app.js.backup

# Later: swap back
swap app.js app.js.backup
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Display help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Not enough arguments (usage error) |
| 4 | First file does not exist |
| 5 | First file is a directory |
| 6 | Second file does not exist |
| 7 | Second file is a directory |
| 8 | Failed to move first file to temp |
| 9 | Failed to move second file to first location |
| 10 | Failed to move temp to second location |

### Dependencies

None (uses only bash built-ins and `mv`).

### Behavior

- Both files must exist; swap does not create missing files
- Directories are not supported
- Uses `/tmp/temp-swap-<basename>` as the temporary location (adds PID and random suffix if that path already exists)
- On failure during the swap sequence (exit codes 8-10), attempts to restore the original file locations
