# chrome-debug

[View script](../scripts/chrome-debug)

Launch any Chromium-family browser (Chrome, Edge, Brave, Chrome for Testing) in remote-debugging mode so an MCP server – like [`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp) – or any other CDP client can attach to it. The browser runs in its own terminal tab with a lifecycle independent of the MCP server, so it survives server restarts and is there before and after your automation work.

It kills two forms of busywork. First, the **deep bundle path**: hand it a `.app`, an executable, or just a *directory* (like a freshly-downloaded Chrome for Testing) and it finds the right binary – no `…/Contents/MacOS/Google Chrome for Testing` archaeology. Second, **port bookkeeping**: the debug port is the identity key that ties a running browser to its MCP server entry, so `chrome-debug` reads your `.mcp.json` (discovered by walking up from the current directory), picks a free configured port, and prints exactly which MCP server can attach.

## Quick start

```
$ chrome-debug "/Applications/Microsoft Edge.app"
chrome-debug: launched Microsoft Edge/150.0.0.0, listening on :9222
  → attach via MCP server 'chrome-devtools-9222'
  profile: /tmp/chrome-debug-9222
```

The command holds the foreground – the browser lives in that terminal tab. Ctrl-C closes it. In another tab (or from your MCP client) attach to the printed server. The port was chosen automatically as the lowest free port in your `.mcp.json` chrome-devtools pool.

## Common examples

**Pin a specific port** (e.g. you want the browser tied to MCP server `chrome-devtools-9223`):

```bash
chrome-debug -p 9223 "/Applications/Microsoft Edge.app"
```

**Point at a freshly-downloaded Chrome for Testing by directory** – no deep path. After `npx @puppeteer/browsers install chrome@stable` drops a build under, say, `~/chrome`, just hand over the directory:

```bash
chrome-debug ~/chrome
```

It searches downward, ignores the nested helper bundles, and picks the newest version's `.app`.

**Dry run** – resolve everything and print what *would* launch, without launching:

```
$ chrome-debug -n ~/chrome
[DRY][chrome-debug] Would launch browser with:
  browser: '~/chrome/mac_arm-150.0.7871.115/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'
  port: '9222'
  server: 'chrome-devtools-9222'
  profile: '/tmp/chrome-debug-9222'
  command: ~/chrome/mac_arm-150.0.7871.115/chrome-mac-arm64/Google\ Chrome\ for\ Testing.app/Contents/MacOS/Google\ Chrome\ for\ Testing --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-debug-9222 --no-first-run --no-default-browser-check --disable-sync
  devtools-prefs:
    [synced] network.show-options-to-generate-har-with-sensitive-data //= true
    [global] cache-disabled //= true
```

**Clean slate** – wipe the port's profile and launch with no extensions:

```bash
chrome-debug -f --no-extensions -p 9222 "/Applications/Microsoft Edge.app"
```

**Pass extra flags through** to the browser unchanged:

```bash
chrome-debug "/Applications/Microsoft Edge.app" -- --incognito --lang=en-GB
```

## How the port pool works

The set of *meaningful* debug ports is exactly the set of `chrome-devtools-mcp` servers configured in your `.mcp.json`. `chrome-debug` parses those entries – keying off each server's actual attach target (`--browser-url=http://127.0.0.1:<port>` or `--wsEndpoint ws://127.0.0.1:<port>/…`), not its name – and treats those ports as the pool.

**Where `.mcp.json` comes from.** `chrome-debug` discovers it the way an MCP client discovers a project-scoped config: it walks up from the current directory to `$HOME` (inclusive), collecting every `.mcp.json` it finds and unioning their entries, nearest first (so a closer file wins when two define the same port). This means running from inside a project that has its own `.mcp.json` picks up that project's pool, while a `~/.mcp.json` at the top of your home directory acts as a global default. Set `CHROME_DEBUG_MCP_JSON=/path/to/.mcp.json` to bypass discovery and use one explicit file.

- **No `-p`** → the lowest pool port with nothing currently listening. The linkage line names the true server key for that port, so you always know which MCP server to attach.
- **`-p <port>` in the pool** → use it.
- **`-p <port>` not in the pool** → a warning that `chrome-devtools-mcp` can't attach (no matching entry), but it proceeds – useful for Playwright, `chrome://inspect`, or a raw CDP script.
- **All pool ports busy** → an error listing them, so you free one or add an entry.

Keying off the attach target means the linkage message stays correct no matter how you've named your MCP servers. To see the parsed pool, `chrome-debug --print-pool`.

## Idempotent by port: launch vs. attach

The port identifies one debug browser, so there should be exactly one per port. If the port you target is **already serving** a DevTools endpoint, `chrome-debug` doesn't try to start a second browser – it prints the linkage and exits, telling you it's already there:

```
$ chrome-debug -p 9222 "/Applications/Microsoft Edge.app"
chrome-debug: Microsoft Edge/150.0.0.0 already serving on :9222
  → attach via MCP server 'chrome-devtools-9222'
  profile: /tmp/chrome-debug-9222
```

This is why re-running the same command is safe: the first call launches, subsequent calls attach. It also sidesteps a Chrome behavior that would otherwise bite – Chrome refuses to start a second instance against a profile that's already in use (it aborts to avoid profile corruption), so a naive relaunch would fail. `chrome-debug` turns that into a clean "already serving."

## Clean sessions: sync, profiles, and extensions

A debug browser should be a clean automation target, not your daily driver, so `chrome-debug` bakes in `--disable-sync` on every launch – a debug session never pulls in your synced bookmarks, history, passwords, or extensions.

The profile directory defaults to `/tmp/chrome-debug-<port>`, one per port. It **persists** across relaunches by default, so a browser on a given port keeps whatever state you built up (a login you set up for testing, say). Two levers reset it:

- **`-f` / `--fresh`** wipes the port's profile directory before launching, for a genuinely clean slate.
- **`--no-extensions`** launches with `--disable-extensions`, suppressing any externally-installed or policy extensions. (It's a discoverable alias for `-- --disable-extensions`; both work.)

## DevTools settings

There's no command-line switch for DevTools *frontend* settings (the Settings-panel toggles) – DevTools reads them from the profile's `Default/Preferences` when it opens. `chrome-debug` seeds that file before launch, so a fresh debug browser opens with the settings you want. Two are on by default:

- **Generate HAR with sensitive data** – lets you export un-sanitized HARs (cookies, auth headers) from the Network panel.
- **Disable cache (while DevTools is open)** – the Network panel's "Disable cache" toggle.

Each is seeded *only if the profile doesn't already carry a value*, so toggling one off inside a session sticks on the next launch. Force one off with `--no-har-sensitive` / `--no-disable-cache`, or skip all built-in seeding with `--no-devtools-prefs`.

Seed any other setting with `--devtools-pref KEY=VALUE` (repeatable):

```bash
# preset a dark DevTools theme (the theme is a synced setting -- use synced:)
chrome-debug --devtools-pref synced:ui-theme=dark "/Applications/Microsoft Edge.app"

# silence the self-XSS console warning, and preset a numeric setting
chrome-debug --devtools-pref disable-self-xss-warning=true --devtools-pref foo=3 ~/chrome
```

`VALUE` is encoded the way DevTools stores settings, and the subtlety is that DevTools keeps *every* setting as a JSON **string** in `Preferences` – the stored string's content is `JSON.stringify(value)`. So `=true` is stored as `"true"`, `=42` as `"42"`, and `=dark` as `"\"dark\""` (a string whose content is the quoted `"dark"`); DevTools reads each back with `JSON.parse`. The dry-run plan prints that inner `JSON.stringify` content – `true`, `42`, `"dark"` – for readability, not the outer quotes. Settings are bucketed by their `storageType`: most are **global** (in `devtools.preferences`), but a handful – the DevTools theme, "generate HAR with sensitive data", "preserve log", and others registered `SYNCED` – live in a separate synced bucket. A bare `KEY` targets the global bucket (which still applies at launch, since DevTools merges both buckets on read, and is re-seeded each run); prefix with `synced:` (or `global:`) to choose explicitly. The synced bucket is the `_sync_disabled` variant because `chrome-debug` always passes `--disable-sync`.

Seeding happens on the launch path only; when `chrome-debug` attaches to an already-running browser it can't seed (and warns if you asked it to). `-n`/`--dry-run` prints the planned seeds without writing.

## Managed browsers (org policy)

If your browser is managed by an organization (MDM/cloud policy), two things can surprise you:

- **Remote debugging may be disabled outright.** Some managed Chrome installs block `--remote-debugging-port` via cloud policy; the browser launches but the debug endpoint never comes up, and `chrome-debug` reports that. If your primary browser is managed, try Edge (often unmanaged) or install **Chrome for Testing**, which is unmanaged by design.
- **The account may be force-signed-in.** On a managed browser, `--fresh` wipes the profile but the org's SSO re-signs the account in on the next launch. `--disable-sync` still stops synced data and extensions from coming down, but the account itself may persist. For a fully account-free session, use Chrome for Testing (no account, no sync).

## Manual verification

The launch/attach/lifecycle behavior – a real window opening, the Dock, Ctrl-C ownership, the debug endpoint responding – isn't covered by the automated test suite (which uses a fast-exit fake browser and shimmed `curl`, since a real browser can't run hermetically). To verify a real launch:

```bash
chrome-debug -p 9222 "/Applications/Microsoft Edge.app"
```

1. Stdout prints the `launched … listening on :9222` confirmation + linkage + profile lines.
2. A browser window opens and appears in the Dock.
3. In another tab, `curl -s http://127.0.0.1:9222/json/version` returns JSON with a `"Browser"` field.
4. Ctrl-C in the launching tab closes the browser.
5. Re-running the same command prints `already serving on :9222` and attaches without opening a second window.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-p, --port PORT` | Debug port. Default: lowest free port in the discovered `.mcp.json` chrome-devtools pool |
| `-d, --user-data-dir DIR` | Chrome profile directory. Default: `/tmp/chrome-debug-<port>` |
| `-n, --dry-run` | Resolve and print what would launch, but don't launch |
| `-f, --fresh` | Wipe the port's profile directory before launching (clean session) |
| `--no-extensions` | Launch with extensions disabled (passes `--disable-extensions`) |
| `--no-har-sensitive` | Force off the default-on DevTools "generate HAR with sensitive data" setting |
| `--no-disable-cache` | Force off the default-on DevTools "disable cache (while DevTools is open)" setting |
| `--no-devtools-prefs` | Skip all built-in DevTools setting seeding |
| `--devtools-pref KEY=VALUE` | Seed a DevTools setting (repeatable); prefix `KEY` with `synced:` for the synced bucket. See [DevTools settings](#devtools-settings) |
| `-v, --verbose` | Verbose resolution output |
| `-h, --help` | Show help |
| `-- extra-chrome-args` | Everything after `--` is passed to the browser verbatim |

`<browser-location>` (required positional) is a `.app` bundle, a raw executable, or a directory to search downward for the newest `.app`.

Baked into every launch: `--remote-debugging-port`, `--user-data-dir`, `--no-first-run`, `--no-default-browser-check`, `--disable-sync`. Two DevTools settings are seeded on by default – see [DevTools settings](#devtools-settings).

### Environment variables

| Variable | Meaning |
|---|---|
| `CHROME_DEBUG_MCP_JSON` | Path to a single `.mcp.json`, overriding the default cwd-to-`$HOME` walk-up discovery |
| `CHROME_DEBUG_PROBE_TRIES` | *(advanced/testing)* Number of `/json/version` probe attempts after launch (default: 20) |
| `CHROME_DEBUG_PROBE_SLEEP` | *(advanced/testing)* Seconds between probe attempts (default: 0.25) |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (launched and serving, attached to an already-serving port, or dry-run resolved) |
| 1 | Runtime failure (resolution failed, port busy but not serving, debug endpoint never came up) |
| 2 | Usage error (missing/invalid browser-location, non-numeric port, unknown flag, bad flag value) |
| 3 | Dependency error (`jq`, `nc`, or `curl` not installed) |

### Dependencies

- `jq` – parse `.mcp.json` for the port pool
- `nc` – check whether a candidate port is already in use
- `curl` – probe the debug endpoint (only needed to launch, not for `--dry-run` or `--help`)
- `defaults` (macOS built-in) – resolve `.app` bundle metadata

### Caveats

- macOS only (uses `defaults` for bundle resolution).
- Managed browsers may block remote debugging or force account sign-in – see [Managed browsers](#managed-browsers-org-policy). Chrome for Testing sidesteps both.
- The default per-port profile persists across relaunches. Use `-f`/`--fresh` for a clean slate, or `-d` to point at your own directory.
- On probe failure the browser is deliberately left running (it may just be slow to start, or a browser is already open on the profile) – the error message says so and suggests `--fresh`.
