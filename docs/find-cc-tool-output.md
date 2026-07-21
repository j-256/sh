# find-cc-tool-output

[View script](../find-cc-tool-output)

Recover the full, untruncated output of any tool call from a Claude Code session by searching the on-disk transcripts. Useful when the CLI's `+N lines (ctrl+o to expand)` indicator can't actually expand -- the underlying transcript JSONL stores the complete payload, and this script pulls it back out.

Claude Code records every session as a JSONL file under `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl`. Each `tool_result` entry holds the full stdout/stderr verbatim; the truncation you see in the UI is a display cap, not storage. Pass any unique substring of the output you remember and the script will find the matching entry and print it.

## Quick start

```
$ find-cc-tool-output 'PARENS ACRONYMS'
landings on disk: 19

=== PARENS ACRONYMS in landing titles ===
  'OCI'           3 hit(s)
    commerce_commerce-api :: Inventory Availability (OCI) :: inventory-availability
    ...
```

When all matches share the same body (the common case -- e.g. you ran the same command twice), the body is printed to stdout. When bodies differ, each unique body is listed on stderr with all its locations:

```
$ find-cc-tool-output 'PARENS ACRONYMS'
[INF][find-cc-tool-output] 3 unique output(s) across 5 occurrence(s) (pick one with --match, narrow with --session/--dir, or pass --all):
  [1] 1 occurrence(s):
    -Users-me--x/abc123...  L34
      "first variant snippet..."
  [2] 2 occurrence(s):
    -Users-me--x/def456...  L42
    -Users-me--x-repo-foo/...  L408
      "second variant snippet..."
  [3] 1 occurrence(s):
    -Users-me--x/abc123...  L260
      "third variant snippet..."
```

Pick one with `--match N` (1-based), narrow with `--session`/`--dir`, or pass `--all` to dump every unique body.

## Common examples

**Pick a specific output from the listing:**

```bash
find-cc-tool-output --match 2 'PARENS ACRONYMS'
```

**Narrow to a renamed session** (custom titles set with `/rename` are searchable by name):

```bash
find-cc-tool-output -s 'dsc-scrape audit' 'landings on disk'
```

**Narrow to one project directory** (absolute path, encoded automatically):

```bash
find-cc-tool-output -d /x 'sips -Z'
```

**Narrow by session UUID** (UUIDs work too -- copy from the file path):

```bash
find-cc-tool-output -s 1d3bb58c-4011-4672-9c7d-2c95b2ff39f5 'landings on disk'
```

**Dump every unique body** (instead of listing):

```bash
find-cc-tool-output --all 'curl -fSsiL'
```

## How matching works

The script walks every `*.jsonl` under `~/.claude/projects/`, parses each line, and inspects entries whose shape is:

```json
{"type":"user","message":{"content":[{"type":"tool_result","content":[{"text":"..."}]}]}}
```

The `text` (or, for older transcripts, the string-form `content`) is decoded and tested for the substring. Matches are then deduplicated by exact body text -- if a command was run multiple times and produced byte-identical output, those occurrences collapse into one group whose locations all appear together.

Friendly session names come from `custom-title` events recorded when you run `/rename`. The latest one wins, so if you've renamed a session multiple times, only the current title resolves.

### Self-match filtering

This script's own listing output starts with `[INF][find-cc-tool-output]`. When that listing is captured by a later tool call (you ran the script earlier in a session and now the transcript contains the listing), it would re-match on subsequent runs with the same substring. By default those are filtered out; pass `--include-meta` if you actually want them.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-s, --session <name\|uuid>` | Limit to one session. Friendly names (set via `/rename`) are resolved by latest `customTitle` event |
| `-d, --dir <path>` | Limit to one project directory. Accepts absolute paths (encoded automatically) or the already-encoded basename |
| `-m, --match <N>` | Print the Nth unique output from a multi-match listing (1-based). Mutex with `--all` |
| `-a, --all` | Dump every unique body, separated by headers |
| `-i, --include-meta` | Don't filter out this script's own listing output |
| `-v, --verbose` | Verbose progress output |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Match found and printed (or all dumped) |
| `1` | No matches |
| `2` | Usage error, or multiple unique outputs without `--match`/`--all` |
| `3` | Missing dependency |

### Dependencies

- `python3` (for JSONL parsing)

### Warnings

**Encoded basenames and `--dir`.** Project directory basenames start with `-` (e.g. `-Users-me--x`), which collides with the short-flag bundling syntax. Use the `=` form for the encoded basename:

```bash
find-cc-tool-output --dir=-Users-me--x 'foo'    # works
find-cc-tool-output --dir -Users-me--x 'foo'    # parsed as bundled flags
```

Absolute paths (`--dir /x`) are encoded internally and have no such issue -- prefer them.

**Substring matching is literal.** The substring is compared against the decoded JSON `text` value, so anything you'd see in the terminal -- including embedded newlines -- matches as-is. Substrings containing literal backslashes (rare in tool output) may need escaping.
