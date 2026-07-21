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
SC2211  This is a glob used as a command name. Was it supposed to be in `${..}`, array, or is it missing quoting?
SC2217  Redirecting to `echo`, a command that doesn't read stdin. Bad quoting or missing `xargs`?
SC2248  Prefer double quoting even when variables don't contain special characters.
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

## How much detail -- what to reach for

For a code lookup, the content axis runs least to most detail:

| Invocation | Output | Fetches? |
|---|---|---|
| `scdef -u <code>` | URL only | No |
| `scdef <code>` *(default, brief)* | Title + Problematic + Correct + URL | Yes |
| `scdef --full <code>` | Whole page rendered: brief **plus** Rationale, Exceptions, notes | Yes |
| `scdef --raw <code>` | Raw markdown source, unprocessed | Yes |

Reach for `-u` when you just want the link; the bare command when brief's example is enough; `--full` when you need the *why* (rationale, exceptions); `--raw` to pipe markdown elsewhere or read the literal source.

Brief and Full both pass through a renderer (see below); `--raw` bypasses extraction and rendering entirely. Brief extraction walks the markdown's ATX headings and captures fenced code under sections named "Problematic" or "Correct".

**Diagnostics** are an orthogonal axis -- `-v/--verbose` composes with any of the above, adding `[DBG]` lines on stderr (renderer choice, fetch URL + HTTP status, cache decisions) without changing stdout:

| Add | Effect |
|---|---|
| `-v` | `[DBG]` diagnostics to stderr; stdout content unchanged |

**Non-content modes** answer "what am I looking up", not "how much detail":

| Invocation | Output |
|---|---|
| `scdef -o <code>` | Opens the wiki page in a browser (nothing on stdout) |
| `scdef -l` | Full index dump (`SC####<TAB>description`) |
| `scdef -s <pattern>` | Matching index rows; a unique match auto-fetches and applies the content axis above |

`--full` and `--raw` compose with a unique `-s` match (e.g. `scdef --full -s 'globbing'` full-renders the single hit). On a multi-match search they're ignored -- you just get the row list.

## Choosing a renderer

By default (`SCDEF_RENDERER` unset), `scdef` auto-selects: [`glow`](https://github.com/charmbracelet/glow) if it's on PATH and stdout is a TTY, otherwise the built-in plaintext converter. `glow` is blessed only in the sense that auto-detection knows to invoke it as `glow -`; it holds no other special status.

`SCDEF_RENDERER` works like `EDITOR` or `PAGER` -- set it to whatever you want the markdown piped to. Two reserved values name the built-in behaviors that have no command form:

```bash
$ SCDEF_RENDERER=text scdef 2155        # built-in plaintext converter (persistent)
$ SCDEF_RENDERER=none scdef 2155        # raw markdown, unrendered (a persistent --raw)
$ SCDEF_RENDERER=mdcat scdef 2155       # pipe markdown to mdcat
$ SCDEF_RENDERER='bat -l md' scdef 2155 # ...or any command, with args
$ SCDEF_RENDERER='glow -' scdef 2155    # force glow even when piped (glow decides what to do)
```

Any value other than `text`/`none` is treated as a command: `scdef` pipes the fetched markdown to it via `sh -c`, so commands with arguments and even pipelines work. Consequences are the caller's -- `scdef` doesn't second-guess whether your renderer needs a TTY. The one safety check: if the command's first token isn't found on PATH, `scdef` warns and falls back to text rather than piping into the void.

Auto-detected `glow` keeps its TTY guard (glow emits nothing when stdout is piped, so auto-selection uses text in that case). That guard is specific to auto-detection; an explicit `SCDEF_RENDERER=glow` is just a command like any other and won't get the TTY safety net -- use `SCDEF_RENDERER=text` if you want plaintext when piping.

If you're unsure which renderer was chosen, `-v` shows the decision:

```bash
$ scdef -v 2155
[DBG][scdef] GET https://raw.githubusercontent.com/wiki/koalaman/shellcheck/SC2155.md
[DBG][scdef] curl exit 0, HTTP 200
[DBG][scdef] renderer: text (auto; glow not on PATH)
SC2155: Declare and assign separately to avoid masking return values
...
```

`-v` prints `[DBG]` lines to stderr (so they don't pollute piped stdout) covering the renderer decision, each fetch and its HTTP status, and index cache hits/refreshes.

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
| `-F, --full` | Full wiki page (rendered) instead of brief |
| `-u, --url` | Print the wiki URL and exit (no fetch) |
| `-o, --open` | Open the wiki page in a browser |
| `-s, --search <pattern>` | Search index by description (case-insensitive substring) |
| `-l, --list` | Print the full index (`SC####<TAB>description`) |
| `-R, --refresh` | Force refresh of the cached index (7-day TTL) |
| `-v, --verbose` | Print `[DBG]` diagnostics to stderr (renderer choice, fetches, cache decisions) |
| `-h, --help` | Show help message |

`--raw` and `--full` are mutually exclusive (raw is unrendered source; full is rendered output -- conflicting requests). `-u`, `-o`, `-s`, `-l` are mutually exclusive (each is a distinct mode).

### Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `SCDEF_RENDERER` | `text` (built-in plaintext), `none` (raw markdown), or any command to pipe markdown to (e.g. `mdcat`, `bat -l md`) | auto (glow if on PATH + TTY, else text) |
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
| `glow` | Markdown rendering in the terminal | Optional; used automatically on a TTY when present, else built-in text |
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
