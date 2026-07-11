# Shell Utilities

A mixed catalog of small shell utilities for everyday development, infrastructure, and command-line work.

**Jump to:** [Shell scripting](#shell-scripting) · [Text & data](#text--data) · [Web & HTTP](#web--http) · [DNS & networking](#dns--networking) · [File operations](#file-operations) · [Security & auth](#security--auth) · [Development](#development) · [macOS](#macos) · [Salesforce B2C Commerce](#salesforce-b2c-commerce) · [Meta](#meta)

Each row's primary link opens the doc; the `script` link opens the raw script.

## Shell scripting

| Tool | Description |
|------|-------------|
| [`dbg`](docs/dbg.md?html) · [script](dbg) | Sourced variable inspector: print scalars, arrays, and array elements as name=value pairs to stderr |
| [`prompt`](docs/prompt.md?html) · [script](prompt) | Sourced interactive prompt with default value and placeholder |
| [`progress`](docs/progress.md?html) · [script](progress) | Single-line progress bar with percentage completion |

## Text & data

| Tool | Description |
|------|-------------|
| [`tsd`](docs/tsd.md?html) · [script](tsd) | Paste any number, get back a timestamp or a duration (auto-detected) |
| [`inflate`](docs/inflate.md?html) · [script](inflate) | Adjust historical USD amounts for inflation (what was $X in YEAR worth today?) |
| [`stats`](docs/stats.md?html) · [script](stats) | Count, total, average, range, and outliers from integers on stdin |
| [`colorize-url`](docs/colorize-url.md?html) · [script](colorize-url) | Apply distinct ANSI colors to URL components for readability |
| [`render-md`](docs/render-md.md?html) · [script](render-md) | Render markdown to HTML and open it in your browser (Node-based — see notes) |
| [`convert-size`](docs/convert-size.md?html) · [script](convert-size) | Convert file sizes between SI (1000-based) and binary (1024-based) units |
| [`baseconv`](docs/baseconv.md?html) · [script](baseconv) | Convert a number between numeral bases (binary, octal, decimal, hexadecimal) |

## Web & HTTP

| Tool | Description |
|------|-------------|
| [`pin-dns`](docs/pin-dns.md?html) · [script](pin-dns) | curl wrapper that overrides DNS resolution for a hostname without touching /etc/hosts |
| [`chrome-ua`](docs/chrome-ua.md?html) · [script](chrome-ua) | Print a realistic Chrome User-Agent from the local install or Google's live API |
| [`chrome-debug`](docs/chrome-debug.md?html) · [script](chrome-debug) | Launch a Chromium browser in remote-debugging mode for MCP/CDP attach, with an auto-picked port from your .mcp.json pool |
| [`httpcode`](docs/httpcode.md?html) · [script](httpcode) | Quick HTTP status code lookup — standard codes plus Cloudflare, nginx, and IIS non-standard codes, all offline |
| [`curl-timing`](docs/curl-timing.md?html) · [script](curl-timing) | Time HTTP requests and compare URLs head-to-head with IQR-aware outlier detection |
| [`slow-server`](docs/slow-server.md?html) · [script](slow-server) | Local HTTP server that responds after a configurable delay, for testing timeout logic |

## DNS & networking

| Tool | Description |
|------|-------------|
| [`spf`](docs/spf.md?html) · [script](spf) | Recursively resolve and inspect SPF records – find whether an IP is authorized, check record health, flatten to all addresses, or print the include tree |
| [`dkim-pubkey`](docs/dkim-pubkey.md?html) · [script](dkim-pubkey) | Extract the base64-encoded public key from a DKIM DNS record |
| [`cf-ddns`](docs/cf-ddns.md?html) · [script](cf-ddns) | Update a Cloudflare DNS A record to match this machine's current outbound IP |
| [`cf-ips-subnets`](docs/cf-ips-subnets.md?html) · [script](cf-ips-subnets) | Expand Cloudflare IPv4 ranges into /16 or /24 subnets for picky firewalls |

## File operations

| Tool | Description |
|------|-------------|
| [`explode`](docs/explode.md?html) · [script](explode) | Move a directory's contents up one level and remove the empty directory (fixes nested-folder unzips) |
| [`snippet`](docs/snippet.md?html) · [script](snippet) | Extract lines between start and end patterns, with built-in trimming to exclude the marker lines |
| [`swap`](docs/swap.md?html) · [script](swap) | Atomically swap two files by renaming |
| [`bak`](docs/bak.md?html) · [script](bak) | Back up a file in place by appending `.bak` (rotates recursively so the single-`.bak` is always most recent) |
| [`unbak`](docs/unbak.md?html) · [script](unbak) | Inverse of `bak`: restore `file.ext.bak` to `file.ext` |

## Security & auth

| Tool | Description |
|------|-------------|
| [`pkce`](docs/pkce.md?html) · [script](pkce) | Generate a PKCE code verifier and its SHA256 challenge for OAuth2 authorization flows |
| [`genpw`](docs/genpw.md?html) · [script](genpw) | Generate random passwords or strings with configurable length, charset, and exclusions |
| [`client-credentials`](docs/client-credentials.md?html) · [script](client-credentials) | Fetch an OAuth2 access token via the `client_credentials` grant (defaults tuned for SFCC, works against any token URL) |

## Development

| Tool | Description |
|------|-------------|
| [`git-backup`](docs/git-backup.md?html) · [script](git-backup) | Push tracked + untracked changes to a timestamped remote tag, then restore local state |
| [`git-add-nonsub`](docs/git-add-nonsub.md?html) · [script](git-add-nonsub) | Stage a git repository inside another git repository without treating it as a submodule |
| [`find-cc-tool-output`](docs/find-cc-tool-output.md?html) · [script](find-cc-tool-output) | Recover full, untruncated tool output from Claude Code session transcripts |
| [`scdef`](docs/scdef.md?html) · [script](scdef) | Look up a ShellCheck warning or error by code or message – brief fix examples, full page, or raw markdown |

## macOS

| Tool | Description |
|------|-------------|
| [`notify`](docs/notify.md?html) · [script](notify) | Show a macOS notification via osascript (useful when long-running commands finish) |
| [`screenshot-rename`](docs/screenshot-rename.md?html) · [script](screenshot-rename) | Rename macOS screenshots from the verbose default format to a clean timestamp-only name |
| [`install-bash`](docs/install-bash.md?html) · [script](install-bash) | Install the latest Bash from Homebrew and set it as your login shell |

## Salesforce B2C Commerce

| Tool | Description |
|------|-------------|
| [`generate-p12`](docs/generate-p12.md?html) · [script](generate-p12) | Generate a PKCS#12 client certificate for B2C staging code uploads that require mTLS |
| [`dot-project`](docs/dot-project.md?html) · [script](dot-project) | Generate `.project` files for B2C cartridge directories so Eclipse-based tooling picks them up |
| [`verify-p12`](docs/verify-p12.md?html) · [script](verify-p12) | Smoke-test WebDAV `/Cartridges` access with Bearer or Basic auth, with optional `.p12` mTLS |
| [`propfind-p12`](docs/propfind-p12.md?html) · [script](propfind-p12) | WebDAV PROPFIND with Bearer token + `.p12` client cert + CA validation against a specific code version |
| [`dw-jwt`](docs/dw-jwt.md?html) · [script](dw-jwt) | Generate an RS256-signed JWT for authenticating to B2C APIs via OAuth2 client credentials |
| [`find-zone-by-name`](docs/find-zone-by-name.md?html) · [script](find-zone-by-name) | Page through the SCAPI zones/info endpoint to find a CDN zone by name substring |
| [`ods-usage`](docs/ods-usage.md?html) · [script](ods-usage) | Calculate On-Demand Sandbox credits used from an ODS API response |
| [`gen-catalog`](docs/gen-catalog.md?html) · [script](gen-catalog) | Generate SFCC catalog XML (base products, variants, relationships) for seeding sandboxes or QA |
| [`pwa-prereqs`](docs/pwa-prereqs.md?html) · [script](pwa-prereqs) | Check or install PWA Kit development prerequisites on macOS (Xcode CLT, nvm, Node LTS) |
| [`s`](docs/s.md?html) · [script](s) | `sfcc-ci` wrapper with shortcuts, enhanced output, and human-readable token expiration |

## Meta

| Tool | Description |
|------|-------------|
| [`get`](docs/get.md?html) · [script](get) | Install scripts from this catalog into a directory on your $PATH |

---

**Notes**

- `render-md` is the one non-bash tool in this catalog: a self-contained Node.js CLI. Requires Node ≥ 18 on `$PATH`.
