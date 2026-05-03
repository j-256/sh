# chrome-ua

[View script](../chrome-ua)

Print a realistic Chrome User-Agent string for scripted HTTP requests. Two modes:

- **Default** — reads the version of Chrome installed on this machine and emits a UA matching it. Zero network. Useful when you want to mimic *your* browser for endpoints that return different content for Chrome vs. curl, or when reproducing a request as-if from your own session.
- **`--latest`** — fetches the current stable Chrome version from Google's official Version History API. No local Chrome required. Useful when you want the globally current Chrome UA (scrapers, generic bot-bypass, CI environments without Chrome installed).

Under Chrome's reduced-UA policy, only the major version segment actually changes — the rest of the UA string is frozen per platform. This script emits what real Chrome would send.

## Quick start

```
$ chrome-ua
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
```

Use it with `curl` to mimic real Chrome:

```bash
curl -A "$(chrome-ua)" https://example.com
```

## Common examples

**Get the latest Chrome version without a local install** — useful on Linux, in CI, or when your installed Chrome is stale:

```bash
curl -A "$(chrome-ua --latest)" https://example.com
```

**Emit a Windows Chrome UA from your Mac** — matches Chrome's actual UA on Windows, not what you'd see in a Mac browser:

```
$ chrome-ua --platform win
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
```

**Fetch the latest Linux Chrome UA:**

```
$ chrome-ua --latest --platform linux
Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36
```

**Point at a specific Chrome install** (e.g. Canary, Beta, or a non-standard path):

```bash
chrome-ua --app "/Applications/Google Chrome Canary.app"
```

**Pipe from the web** (since this is published at toolio.sh):

```bash
curl -A "$(curl -s toolio.sh/chrome-ua | bash)" https://example.com
```

## Local vs latest: which should you use?

- Use the **default** (local) when you want the UA to match *your* browser. Most useful for reproducing requests from your own browser session, debugging site-specific behavior, or matching the browser a site has already seen from your machine.
- Use **`--latest`** when you want the current realistic Chrome UA globally. Useful for scrapers, generic bot-bypass, or any context where "a current Chrome" is the intent rather than "my Chrome."

Both modes honor Chrome's reduced-UA policy — the platform string is frozen per-OS regardless of the actual machine. `--platform` lets you override which platform shape is emitted.

## Fallback behavior

The default (local) mode has a three-step fallback chain:

1. **Read local Chrome** via `defaults read Chrome.app/Contents/Info.plist` — this is the happy path on macOS.
2. **Auto network fallback** — if the local read fails (Chrome not installed, non-macOS host, permissions, unreadable plist) and `curl` + `jq` are available, the script silently fetches the latest major from Google's API. Warns to stderr that it did so.
3. **Pinned fallback** — if the local read failed *and* the network fetch failed (no curl, no network, API broken), the script uses a hardcoded `fallback_major` constant and warns to stderr. The constant is set in the script source (`fallback_major=`) and needs periodic refreshing.

The explicit `--latest` mode skips step 1 entirely — it goes straight to step 2, then falls back to step 3 if that fails.

This means `curl -A "$(chrome-ua)" ...` is always usable; it will always emit *some* plausible UA, even on a fresh Linux container with no Chrome.

### Disabling the automatic network fallback

Set `CHROME_UA_OFFLINE=1` (or any non-empty value) to block the automatic network fallback. When this is set:

- Default mode: local read → pinned fallback (skips step 2).
- Explicit `--latest`: still fetches. `--latest` is an explicit request for network; the env var only blocks the *automatic* fallback.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `--latest` | Fetch the latest stable Chrome major version from Google's Version History API |
| `--platform mac\|win\|linux` | UA shape (and, with `--latest`, the API path). Default: `mac` |
| `--app PATH` | Path to Chrome.app for local mode (default: `/Applications/Google Chrome.app`) |
| `-h, --help` | Display help |

### Environment variables

| Variable | Meaning |
|---|---|
| `CHROME_UA_OFFLINE` | If set (any non-empty value), disables the automatic network fallback when local read fails. Does not affect explicit `--latest`. |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (always, when flags are valid — the script always emits some UA, falling back to a pinned version with a warning if all else fails) |
| 2 | Usage error (unknown flag, missing `--app`/`--platform` value, invalid `--platform`) |

### Dependencies

- `defaults` (macOS built-in) — for local mode
- `curl` — for `--latest` and the automatic network fallback
- `jq` — for `--latest` and the automatic network fallback (to parse the API response)

### Caveats

- Local version detection is macOS only; on other platforms, default mode will hit the automatic network fallback (or go straight to the pinned constant if `CHROME_UA_OFFLINE` is set).
- Only the major version is accurate; minor/build/patch are intentionally zeroed to match real Chrome's reduced UA.
- The platform string is frozen per-OS family (e.g. `Intel Mac OS X 10_15_7` even on Apple Silicon, `Windows NT 10.0` even on Windows 11). This matches what real Chrome emits — the OS version in a modern Chrome UA is not meaningful.
- The pinned fallback constant goes stale. If you see a major version that's obviously behind reality, grep the script for `fallback_major=` and bump it, or just use `--latest`.
