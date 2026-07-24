# daemons

[View script](../daemons)

Observe your homegrown launchd daemons. A LaunchAgent or LaunchDaemon runs in the background and tells you almost nothing: `launchctl` knows whether it is loaded and what its last exit code was, but not what it actually did over time - did the trigger fire? did it do work, or no-op? has it been quietly erroring for a week?

`daemons` closes that gap. Each daemon appends one-line JSON records to its own activity log (the `append` write path daemons call), and four read commands turn those logs plus live `launchctl` state into a picture you can act on: `status` (a per-daemon glance), `check` (a nonzero-on-problem health gate for your login shell or a monitor), `log` (human-readable rendering), and `query` (filter and extract the raw JSONL). Two more commands act on daemons rather than just observe them: `load` and `unload` bootstrap/bootout a daemon into launchd (and log a `load`/`unload` record so the timeline explains gaps in its fires), and `registry` reveals the registry file.

## Quick start

The common flow is a quick triage: glance at all daemons, skim recent activity, then isolate anything that errored.

```
$ daemons status
reconcile                loaded      last change @ 2026-07-16T04:30:12Z (18 change, 402 noop, 0 error)
screenshot-rename        loaded      last error @ 2026-07-16T05:12:44Z (5 change, 88 noop, 1 error)
backup                   NOT LOADED  never fired

$ daemons log --all
2026-07-16T04:30:12Z reconcile CHANGE reconciled 3 drifted keys
2026-07-16T05:00:03Z screenshot-rename NOOP no new screenshots
2026-07-16T05:12:44Z screenshot-rename ERROR sips exited 1 on Screen Shot 2026-07-16.png

$ daemons query --all --event error --since 1h
{"ts":"2026-07-16T05:12:44Z","daemon":"screenshot-rename","event":"error","detail":"sips exited 1 on Screen Shot 2026-07-16.png"}
```

`status`, `check`, `load`, and `unload` read a small registry you set up once (see [The registry](#the-registry) below). `append`, `log`, and `query` work straight from the log files and need no registry at all.

## Logging activity from a daemon (`append`)

`append` is the write path: a daemon calls it once per run to record what happened.

```bash
daemons append reconcile change "reconciled 3 drifted keys"
```

The `<event>` argument is one of six fixed values, so activity is countable and filterable:

- `trigger` - the daemon woke up (a WatchPaths event, a scheduled interval)
- `noop` - it ran, but there was nothing to do
- `change` - it ran and did work / made a change
- `error` - it failed
- `load` - the daemon was bootstrapped into launchd (via `daemons load` or an install that delegates to it)
- `unload` - the daemon was booted out of launchd

Always call `append` guarded, so a logging failure never takes the daemon down with it:

```bash
daemons append reconcile change "reconciled 3 drifted keys" 2>/dev/null || :
```

The `2>/dev/null || :` swallows any failure (jq missing under the daemon's minimal PATH, a full disk, a read-only log dir) - the record is best-effort, and the daemon's real work proceeds regardless.

For a large or multi-line detail (a captured command output, say), pass `--detail-stdin` in place of the detail argument and pipe the payload in:

```bash
some-command 2>&1 | daemons append reconcile error --detail-stdin 2>/dev/null || :
```

Newlines and tabs in the detail round-trip intact: the record stays one physical line, with the detail JSON-escaped inside it.

## Reading and filtering (`log` and `query`)

`log` renders records for humans - one header line per record (`<ts> <daemon> <EVENT> <first detail line>`), with any further detail lines indented beneath. Name a single daemon, or use `--all` to merge every daemon's records in timestamp order:

```
$ daemons log reconcile
2026-07-16T04:30:12Z reconcile CHANGE reconciled 3 drifted keys
```

Because timestamps are ISO-8601 UTC they sort lexically, which is how `-a`/`--all` interleaves daemons correctly. Add `-f`/`--follow` to follow the log as new records land, like `tail -f`:

```bash
daemons log --all -f
```

`query` is the machine-readable counterpart: it emits the raw JSONL records that survive its filters, so you can pipe them onward.

Unlike `log --all` (which merge-sorts every daemon's records by timestamp), `query --all` emits records grouped by daemon, in log-file order - not globally time-sorted. Pipe through `jq -s 'sort_by(.ts)'` if you need one global time order across daemons.

**Keep one event type** with `-e`/`--event`:

```bash
daemons query reconcile --event error
```

**Keep recent records** with `-s`/`--since`, which accepts three forms:

- a relative span, `NNN[smh]` - `1h`, `30m`, `90s` (that long before now)
- a bare date, `YYYY-MM-DD` - midnight UTC that day
- a full ISO-8601 UTC timestamp - used as-is

```bash
daemons query --all --event error --since 1h
```

**Reshape the output** by piping matches through a jq expression with `-j`/`--jq`:

```bash
daemons query reconcile --event change --jq '.detail'
```

A bare `log` or `query` with no name (and no `-a`/`--all`) defaults to all daemons. Querying a daemon that has never logged is not an error - it simply prints nothing and exits 0.

## Health-checking (`check`)

`check` is a gate: it reads the registry and exits nonzero, printing a loud alert to stdout, for any daemon that is not loaded in launchd, points at a script that no longer exists, or whose last launchd run exited nonzero.

```
$ daemons check
[daemons] com.example.backup not loaded in launchd!
$ echo $?
1
```

Because it exits nonzero only on a problem and is silent when everything is healthy, it drops cleanly into a login-shell startup snippet or a monitoring job:

```bash
daemons check || echo "a daemon needs attention - run: daemons status"
```

## Loading and unloading (`load` and `unload`)

`load` and `unload` drive `launchctl` directly, so you don't need to remember the domain/label/plist incantation for a daemon you already registered.

`load` always reloads: it boots the daemon out first (ignoring "not loaded", since there's nothing to boot out on a first load), then bootstraps it fresh from its plist. That makes it safe to re-run after editing a plist or a script - the old instance is gone before the new one starts.

The plist path is resolved by precedence: the `--plist` flag, then the registry's `plist` column, then convention derived from the domain and label - `gui/$UID/` daemons resolve to `~/Library/LaunchAgents/<label>.plist`, `system/` daemons to `/Library/LaunchDaemons/<label>.plist`. Whichever way it's resolved, `load` verifies the file exists before touching launchd.

`unload` boots the daemon out and is idempotent: if it's already not loaded, it says so and exits 0 rather than treating that as an error.

Both accept `-n`/`--dry-run` to print the `launchctl` commands they would run without running them:

```bash
daemons load reconcile --dry-run
```

A `system/` target needs root, so `load`/`unload` elevate just the `launchctl` call (and the lifecycle record append) via `sudo` when you're not already root - expect a password prompt:

```
$ daemons load reconcile
$ daemons load reconcile --plist /custom/path.plist
$ daemons unload reconcile
$ daemons load managed-settings-patch   # system/ target: prompts for sudo password
```

Each successful `load`/`unload` appends its own `load`/`unload` record to the daemon's log, so `log`/`query` show not just what the daemon did but when it was (re)loaded or pulled - useful for explaining a gap in its activity.

## The registry

`status`, `check`, `load`, and `unload` need to know which daemons exist and how to address them in launchd. That lives in a small registry file (see [`DAEMONS_REGISTRY`](#environment-variables) for its location). It is a header row plus one whitespace-separated row per daemon:

```
name              domain     label                          script
reconcile         gui/$UID/  com.example.reconcile          /usr/local/bin/reconcile
screenshot-rename gui/$UID/  com.example.screenshot-rename  /usr/local/bin/screenshot-rename
```

- `name` - the log name; matches the `<name>` the daemon passes to `append`
- `domain` - the launchd domain target: `gui/$UID/` for a per-user LaunchAgent (the `$UID` token is replaced with your numeric uid) or `system/` for a LaunchDaemon
- `label` - the launchd label; `check` and `status` read state with `launchctl print <domain><label>`
- `script` - path to the script the daemon runs; `check` flags it if the file is missing
- `plist` - (optional) the daemon's plist path, used by `load`. When omitted, `load` derives it from the domain and label by convention

`status`, `check`, `load`, and `unload` consult the registry. The write and read paths (`append`, `log`, `query`) operate purely on log files, so a daemon can log before it is ever registered.

## Revealing the registry (`registry`)

`registry` prints the resolved `$DAEMONS_REGISTRY` path, so you don't have to remember or recompute it:

```
$ daemons registry
/Users/you/.config/daemons/daemons.tsv
```

Pass `--edit` to open it straight in your editor - `$VISUAL`, then `$EDITOR`, then `vi` (default), and the editor string may carry arguments (e.g. `VISUAL="code --wait"`) - or `--open` to open it with macOS `open` (whatever app is registered for the file type). The two are mutually exclusive:

```bash
daemons registry --edit
daemons registry --open
```

## The JSONL record

Each daemon owns one log file, `<name>.log`, in [`DAEMONS_LOG_DIR`](#environment-variables). Every line is a self-contained JSON object (JSONL):

```json
{"ts":"2026-07-16T05:12:44Z","daemon":"screenshot-rename","event":"error","detail":"sips exited 1 on Screen Shot 2026-07-16.png"}
```

| Field | Value |
|---|---|
| `ts` | ISO-8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`), stamped by `append` at write time |
| `daemon` | the `<name>` passed to `append` |
| `event` | one of `trigger`, `noop`, `change`, `error`, `load`, `unload` |
| `detail` | free-form string; may contain newlines and tabs (JSON-escaped, so the record stays one line) |

---

## Reference

### Subcommands

| Subcommand | Description |
|---|---|
| `append <name> <event> [detail]` | Append one record to `<name>`'s log (creating the log dir on first write). `<event>` is `trigger`, `noop`, `change`, `error`, `load`, or `unload`. Pass `--detail-stdin` in place of `[detail]` to read the detail from stdin |
| `status` | Per-daemon summary from the registry: loaded in launchd? plus last activity (event + timestamp) and all-time event counts. Shows `never fired` when a daemon has no log yet |
| `check` | Health gate: exits nonzero with a loud alert for any daemon not loaded, pointing at a missing script, or whose last run exited nonzero |
| `log [name\|-a\|--all] [-f\|--follow]` | Render a log human-readably. `-a`/`--all` (or no name) merges every daemon in timestamp order; `-f`/`--follow` follows like `tail -f` |
| `query [name\|-a\|--all] [-e\|--event E] [-s\|--since T] [-j\|--jq EXPR]` | Emit raw JSONL records matching the filters. `-e`/`--event` keeps one event type; `-s`/`--since` keeps records at or after a time; `-j`/`--jq` pipes matches through a jq expression |
| `load <name> [--plist PATH] [-n\|--dry-run]` | Bootstrap (reload) a daemon into launchd, resolving its plist by `--plist` > registry column > convention. Logs a `load` record. Elevates via `sudo` for a `system/` target |
| `unload <name> [-n\|--dry-run]` | Bootout a daemon from launchd (idempotent). Logs an `unload` record |
| `registry [--edit\|--open]` | Print the resolved registry path; `--edit` opens `$VISUAL`/`$EDITOR` (default `vi`), `--open` uses macOS `open` |
| `-h, --help` | Show help |

`-s`/`--since T` accepts a relative span (`NNN[smh]`, e.g. `1h`), a bare date (`YYYY-MM-DD`, midnight UTC), or a full ISO-8601 UTC timestamp.

### Environment variables

| Variable | Meaning |
|---|---|
| `DAEMONS_LOG_DIR` | Directory holding the `<name>.log` files. Default: `$XDG_STATE_HOME/daemons`, or `~/.local/state/daemons` when `XDG_STATE_HOME` is unset |
| `DAEMONS_REGISTRY` | Registry file that `status`, `check`, `load`, and `unload` read (and `registry` prints). Default: `$XDG_CONFIG_HOME/daemons/daemons.tsv`, or `~/.config/daemons/daemons.tsv` when `XDG_CONFIG_HOME` is unset |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (and, for `check`, all daemons healthy) |
| 1 | Runtime failure; also `check` when it detects a health problem |
| 2 | Usage error (unknown or missing subcommand, missing argument, invalid event, unknown option) |
| 3 | `jq` is not installed |

### Dependencies

- `jq` (required by every subcommand - the records are JSON). The script prepends `/opt/homebrew/bin:/usr/local/bin` to `PATH` so it can find `jq` under the minimal `PATH` a launchd job inherits.
- `launchctl` (macOS built-in; used by `status` and `check` to read loaded state and last exit code, and by `load`/`unload` to bootstrap/bootout)
- `sudo` (required only for `load`/`unload` of a `system/` daemon when not run as root)

macOS only for `status`/`check`/`load`/`unload`, which are launchd-specific. `append`, `log`, `query`, and `registry` are portable - just files (and `jq`, for the JSON ones).
