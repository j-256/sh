# scdef

[View script](../scdef)

Look up a ShellCheck warning or error definition without leaving the terminal. Pass any code shape (`SC2155`, `sc2155`, `2155`, `#SC2155`, `[SC2155]`) and `scdef` fetches the relevant wiki page and prints a brief summary -- title, problematic example, correct example, URL. Use `--full` when you want the rationale and exceptions; use `--raw` to pipe the markdown source into a renderer of your choice.

ShellCheck's wiki is the authoritative reference for every check it emits, but jumping to a browser to look up `SC2155` for the hundredth time is friction. `scdef` keeps the loop tight: a single command, brief output by default, the full page one keystroke away.

## Quick start

```bash
$ scdef 2155
SC2155: Declare and assign separately to avoid masking return values

Problematic
    export foo="$(mycmd)"
    local foo="$(mycmd)"
    readonly foo="$(mycmd)"

Correct
    foo="$(mycmd)"
    export foo
    local foo
    foo=$(mycmd)
    foo="$(mycmd)"
    readonly foo

https://github.com/koalaman/shellcheck/wiki/SC2155
```

## Common examples

**Forgot the code, but remember the message:**

```bash
$ scdef -s 'declare and assign'
[INF][scdef] 1 match: SC2155 -- fetching wiki page
SC2155: Declare and assign separately to avoid masking return values
...
```

**Browse the index for a topic:**

```bash
$ scdef -s quoting
SC2086  Double quote to prevent globbing and word splitting.
SC2090  Quote expansions in this `awk` snippet to prevent splitting.
SC2098  This expansion will not see the mentioned assignment.
SC2211  This is a glob used as a command name. Was it supposed to be in `${..}`, array, or is it missing quoting?
SC2248  Prefer double quoting even when variables don't contain special characters.
...
```

**Want the rationale and exceptions:**

```bash
$ scdef --full 2155
```

**Pipe markdown to your preferred renderer:**

```bash
$ scdef --raw 2155 | glow -
$ scdef --raw 2155 | mdcat
```

**Just give me the URL:**

```bash
$ scdef -u 2086
https://github.com/koalaman/shellcheck/wiki/SC2086
```

**Open in a browser:**

```bash
$ scdef -o SC2155
```

**Dump the full index for grep, fzf, etc.:**

```bash
$ scdef --list | fzf
```

## Output forms

`scdef` has three output modes for a code lookup:

- **Brief (default)**: title + Problematic block + Correct block + URL. Extracted from the wiki markdown by walking ATX headings and capturing fenced code blocks under sections whose name starts with "Problematic" or "Correct". Fast to skim, useful for lookups when you mostly need to remember the fix.
- **Full (`--full`)**: the whole wiki page, rendered. Includes Rationale, Exceptions, and any other sections the page provides.
- **Raw (`--raw`)**: the markdown source verbatim, no extraction, no rendering. For piping into any renderer (`glow`, `mdcat`, `pandoc`, etc.) or further processing.

Both Brief and Full pass through a renderer. Raw bypasses everything.

## Renderer auto-detection

When rendering markdown, `scdef` picks one of these in priority order:

1. `glow` (if on PATH)
2. `render-md` (if on PATH)
3. Built-in plaintext converter

You can force a specific choice with `SCDEF_RENDERER`:

```bash
$ SCDEF_RENDERER=text scdef 2155       # always use the built-in plaintext converter
$ SCDEF_RENDERER=glow scdef 2155       # require glow
$ SCDEF_RENDERER=render-md scdef 2155  # require render-md
$ SCDEF_RENDERER=none scdef 2155       # emit the (extracted, if brief) markdown unrendered
```

If a forced renderer isn't installed, `scdef` warns and falls back to text. The same happens if a TTY-only renderer (glow, render-md) is selected when stdout isn't a TTY -- those tools detect a pipe/redirect and emit nothing, so `scdef` falls back to text rather than producing silent empty output.

## Code argument flexibility

Any of these resolve to `SC2155`:

- `SC2155`, `sc2155`, `Sc2155`, `sC2155`
- `2155` (bare digits)
- `SC-2155`, `SC_2155`, `'SC 2155'` (separators between `SC` and digits)
- `'#SC2155'`, `'[SC2155]'`, `'#2155'` (common surrounding characters)

So you can paste a code from anywhere -- a comment, linter output, chat -- without reformatting first.

## How it works

`scdef` keeps a 7-day cached index of every SC#### code and its short description, fetched from `https://www.shellcheck.net/wiki/`. The index lives at `${XDG_CACHE_HOME:-$HOME/.cache}/scdef/index.tsv` -- one TSV row per code (`SC####<TAB>description`).

When you ask for a code directly, it skips the index and fetches the wiki's raw markdown for that page from `raw.githubusercontent.com/wiki/koalaman/shellcheck/SC####.md`. By default it walks the markdown to extract just the brief sections; `--full` skips that step.

When you `--search`, it greps the cached index. A single match auto-fetches the wiki page; multiple matches print the rows (column-aligned on a TTY, raw TSV when piped).

If a refresh fails (network down, wiki HTML changed) and a cache file already exists, `scdef` falls back to the existing cache with a warning -- you can keep working offline. Force a refresh with `--refresh`.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-r, --raw` | Raw markdown source (skip extraction and rendering) |
| `--full` | Full wiki page (rendered) instead of brief |
| `-u, --url` | Print the wiki URL and exit (no fetch) |
| `-o, --open` | Open the wiki page in a browser |
| `-s, --search <pattern>` | Search index by description (case-insensitive substring) |
| `-l, --list` | Print the full index (`SC####<TAB>description`) |
| `--refresh` | Force refresh of the cached index (7-day TTL) |
| `-h, --help` | Show help message |

`--raw` and `--full` are mutually exclusive (raw is unrendered source; full is rendered output -- conflicting requests). `-u`, `-o`, `-s`, `-l` are mutually exclusive (each is a distinct mode).

### Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `SCDEF_RENDERER` | Force a specific renderer: `glow`, `render-md`, `text`, or `none` | auto (priority chain) |
| `XDG_CACHE_HOME` | Cache root directory | `$HOME/.cache` |

The cache file lives at `$XDG_CACHE_HOME/scdef/index.tsv`.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime failure (network failed and no cache to fall back to; parse failure with no cache) |
| 2 | Usage error (missing arg, unknown flag, bad value, mutually-exclusive flags) |
| 3 | Dependency error (`curl` missing; `open`/`xdg-open` missing for `--open`) |
| 4 | No matches for `--search` |
| 5 | Code not found on the ShellCheck wiki (404) |

### Dependencies

| Tool | Purpose | Notes |
|---|---|---|
| `curl` | Fetch wiki content | Required for any path that fetches; `-h`, `-u`, `-o`, and cached `--list`/`--search` work without it |
| `column` | Align `--search` output | Optional; falls back to raw TSV when missing or stdout is not a TTY |
| `glow` | Markdown rendering | Optional; preferred renderer when present |
| `render-md` | Markdown rendering | Optional; fallback renderer when glow is not present |
| `open` (macOS) or `xdg-open` (Linux) | Open the wiki in a browser | Required only for `--open` |

### Caching

- The index is cached for 7 days at `$XDG_CACHE_HOME/scdef/index.tsv`
- A stale cache (older than 7 days) triggers a refresh on the next call
- If the refresh fails (network, parse, etc.) and a cache file exists, `scdef` warns and serves the stale cache rather than failing
- `--refresh` forces a refetch regardless of cache age
- Individual wiki pages (e.g. `SC2155`) are not cached -- they're small and Cloudflare/GitHub are fast enough that re-fetching is fine

### Future-proofing

The index parser strips every HTML tag and walks `SC####` markers, so it survives wiki HTML changes (different tags, restructured layouts) as long as the page contains visible "SC#### - description" text.

The brief extractor walks ATX headings looking for sections whose name starts with "Problematic" or "Correct" (case-insensitive). If those section names ever change, brief output gracefully degrades to title + URL only -- the script still works, you just won't see the example blocks.
