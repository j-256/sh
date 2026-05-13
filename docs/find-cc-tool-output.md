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

When exactly one tool_result contains the substring, its full body goes to stdout. When several do, the script lists them on stderr and exits 2 -- narrow with `--session` or `--dir`, or pass `--all` to dump every match.

## Common examples

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

**Dump every match's full body** (instead of listing):

```bash
find-cc-tool-output --all 'curl -fSsiL'
```

## How matching works

The script walks every `*.jsonl` under `~/.claude/projects/`, parses each line, and inspects entries whose shape is:

```json
{"type":"user","message":{"content":[{"type":"tool_result","content":[{"text":"..."}]}]}}
```

The `text` (or, for older transcripts, the string-form `content`) is decoded and tested for the substring. Listings show the project directory, session UUID, line number, friendly title (if any), and a one-line snippet -- enough to identify the match before re-running with `--all` or a tighter filter.

Friendly session names come from `custom-title` events recorded when you run `/rename`. The latest one wins, so if you've renamed a session multiple times, only the current title resolves.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-s, --session <name\|uuid>` | Limit to one session. Friendly names (set via `/rename`) are resolved by latest `customTitle` event |
| `-d, --dir <path>` | Limit to one project directory. Accepts absolute paths (encoded automatically) or the already-encoded basename |
| `-a, --all` | Dump every matching tool_result body, separated by headers, instead of listing |
| `-v, --verbose` | Verbose progress output |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Match found and printed (or all dumped) |
| `1` | No matches |
| `2` | Usage error, or multiple matches without `--all` |
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
