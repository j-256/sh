# snippet

Extract lines between start and end patterns from files or stdin. Like `sed -n '/START/,/END/p'` but easier to remember and with built-in trimming to exclude marker lines.

Useful when you need to pull a specific section from a log, config, or document without copying the boundary lines themselves. Works with regex patterns and handles cases where the end marker is optional (extract from start to EOF).

## Quick start

```
$ snippet -s "BEGIN CERTIFICATE" -e "END CERTIFICATE" cert.pem
MIIBkTCB+wIJAKHHCgVZU1p0MA0GCSqGSIb3DQEBCwUAMBQxEjAQBgNVBAMMCWxv
Y2FsaG9zdDAeFw0yMDAxMDEwMDAwMDBaFw0zMDAxMDEwMDAwMDBaMBQxEjAQBgNV
...
```

Or pipe directly:

```
$ cat logfile.txt | snippet -s "Error:"
```

## Common examples

**Extract a section and trim the markers:**

```
$ snippet -s "START CONFIG" -e "END CONFIG" -t 1 config.txt
database=prod
timeout=30
```

The `-t 1` flag excludes the first and last line of the match (the marker lines themselves).

**Pull everything from a marker to end of file:**

```
$ snippet -s "=== SUMMARY ===" report.txt
=== SUMMARY ===
Total errors: 3
Total warnings: 12
Build time: 2m 15s
```

**Extract from a piped log:**

```
$ docker logs my-container | snippet -s "Stack trace:" -e "^$"
Stack trace:
  at handleRequest (/app/server.js:142:15)
  at processTicksAndRejections (node:internal/process:12:3)
```

The end pattern `^$` matches the first blank line after the start.

**Trim only the start marker:**

```
$ snippet -s "# BEGIN SECTION" -e "# END SECTION" -f 1 notes.md
Item 1
Item 2
Item 3
# END SECTION
```

The `-f 1` flag excludes the first line only.

## Pattern matching

Start and end patterns are passed to `sed` as regular expressions. Use literal strings for simple markers or regex patterns for more complex matching:

```
$ snippet -s "^Error:" -e "^[A-Z]" application.log
```

This extracts from lines starting with "Error:" up to the next line starting with a capital letter.

Patterns are case-sensitive by default (sed default behavior).

## Trimming

Three flags control which matched lines are excluded:

- `-f N` / `--trim-first N` -- drop the first N lines of the match
- `-l N` / `--trim-last N` -- drop the last N lines of the match
- `-t N` / `--trim N` -- drop the first and last N lines (shorthand for `-f N -l N`)

Trimming happens after matching, so the boundary lines are used to find the section but then optionally removed from output.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-s, --start PATTERN` | Start pattern (required) |
| `-e, --end PATTERN` | End pattern (optional; if omitted, reads to EOF) |
| `-f, --trim-first N` | Exclude the first N lines of the matched snippet |
| `-l, --trim-last N` | Exclude the last N lines of the matched snippet |
| `-t, --trim N` | Exclude the first and last N lines of the matched snippet |
| `-h, --help` | Display help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Error (missing required flag value, no start pattern provided, unknown option) |

### Dependencies

None -- uses only standard Unix utilities.
