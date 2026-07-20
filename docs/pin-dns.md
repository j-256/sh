# pin-dns

[View script](../pin-dns)

curl wrapper that overrides DNS resolution for a hostname -- bypass CDNs, hit origin servers, or pin requests to a specific IP, without touching /etc/hosts or system DNS.

It also makes the request *look like a real browser*. By default `pin-dns` sends a full, internally consistent Chrome request -- not just a User-Agent, but client hints (`Sec-CH-UA*`), `Sec-Fetch-*`, and correctly ordered `Accept` headers, with the Chrome version auto-detected from your local install. That defeats header-based bot filtering; when [`curl-impersonate`](#tls-fingerprinting-curl-impersonate) is installed, it also matches Chrome's TLS/JA3 and HTTP-2 fingerprint.

Under the hood it builds a `curl --resolve` command for you and adds sensible defaults (silent mode, curlrc disabled).

## Quick start

**Drop-in curl replacement** -- take a curl command, swap `curl` for `pin-dns`, add a target:

```bash
# Before
curl https://www.example.com/page -H "X-Debug: 1"

# After -- same request, but forced through a specific edge hostname
pin-dns https://www.example.com/page -H "X-Debug: 1" edge.cdn.example.net
```

The target can go anywhere -- right after the URL, at the end, or as `--target`.

## Common examples

**Positional shorthand** -- hostname, target, path:

```bash
pin-dns www.example.com edge.cdn.example.net /page?q=test
```

**Pin to a CDN edge hostname:**

```bash
pin-dns www.example.com commcloud.prod-xxxx.cc-ecdn.net
```

**Pin to a specific IP:**

```bash
pin-dns www.example.com 203.0.113.50
```

**Pin with a path and query string:**

```bash
pin-dns www.example.com origin.example.net "/search?q=hello&lang=en"
```

**Use a specific DNS server to resolve the target:**

```bash
pin-dns www.example.com origin.example.net --resolver 8.8.8.8
```

**HTTP instead of HTTPS:**

```bash
pin-dns --scheme http --port 80 www.example.com origin.example.net
```

Or just pass an `http://` URL:

```bash
pin-dns http://www.example.com:8080/path --target origin.example.net
```

**Dry run -- see the curl command without executing:**

```bash
pin-dns --dry-run www.example.com origin.example.net /path
```

**Pass extra curl options:**

```bash
pin-dns https://www.example.com 1.2.3.4 -H "X-Debug: 1" -o /dev/null -D -
```

**Suppress pin-dns info messages (keep only errors):**

```bash
pin-dns -q www.example.com origin.example.net
```

## What TARGET means

TARGET is "where to actually connect." It can be:

- **A hostname** (e.g. an edge/origin CNAME) -- pin-dns resolves it to an IP via `dig`
- **An IP address** (IPv4 or IPv6) -- used directly

If TARGET is omitted, pin-dns runs curl normally (no `--resolve`), which is fine for testing that your command works before adding pinning.

## Defaults you get for free

| Behavior | Default | Override |
|---|---|---|
| Silent mode (`curl -sS`) | On | `--no-silent` |
| curlrc disabled (`curl -q`) | On | `--curlrc` |
| Chrome User-Agent | Auto-detected from local Chrome install | Pass `-A "..."` or `-H "User-Agent: ..."` |
| Scheme | `https` | `--scheme http` or pass an `http://` URL |
| Port | `443` (or `80` for http) | `--port 8080` or include port in URL |

## Browser impersonation

By default `pin-dns` sends a full, internally consistent Chrome request, not just
a User-Agent: client hints (`Sec-CH-UA*`), `Sec-Fetch-*`, and correctly ordered
`Accept` / `Accept-Encoding` / `Accept-Language`. This defeats header-based bot
filtering. The Chrome major version is resolved from your local Chrome install,
falling back to Google's Version History API (cached under
`$XDG_CACHE_HOME/pin-dns` (default `$HOME/.cache/pin-dns`)), then a pinned constant.

```bash
# Full Chrome headers, navigate profile (default)
pin-dns https://example.com edge.example.com

# API/XHR profile for a JSON endpoint
pin-dns --fetch-mode cors https://api.example.com/v1/things edge.example.com

# Impersonate a Windows Chrome
pin-dns --platform win https://example.com edge.example.com

# Bare request, no impersonation
pin-dns --no-impersonate https://example.com edge.example.com
```

Any header you pass wins (pin-dns never duplicates it). A non-Chrome `-A`/`User-Agent`
suppresses the Chrome-only client hints so the request stays self-consistent.

`--no-impersonate` is the master off-switch: combining `--client impersonate` with
`--no-impersonate` produces a bare request rather than a client error, because
`--no-impersonate` wins.

For a decodable stdout response, `pin-dns` advertises `Accept-Encoding: gzip, deflate, br, zstd`
and decodes the body before printing. On macOS, `deflate` is best-effort: the system has no
standalone raw-deflate decoder, so a `deflate`-encoded body may be emitted raw. `gzip` decodes
with the system tool; `br` and `zstd` decode only when the `brotli`/`zstd` binaries are installed
(otherwise the raw body is emitted with a warning).

### TLS fingerprinting (curl-impersonate)

Stock curl matches Chrome's *headers* but not its *TLS/JA3 or HTTP-2 fingerprint*.
Advanced detectors (Akamai, DataDome, some Cloudflare modes) check those. To defeat
them, install [`lexiforest/curl-impersonate`](https://github.com/lexiforest/curl-impersonate)
(prebuilt binaries on its Releases page). When a `curl-impersonate` binary is on your
`PATH`, `pin-dns` uses it automatically (`--client auto`) to match the TLS + HTTP-2
signature as well; `--client impersonate` (or its `curl-impersonate` alias) requires it,
`--client curl` forces stock curl.

curl-impersonate ships a fixed roster of browser profiles (e.g. `chrome131`, `chrome133a`)
that lags live Chrome and skips versions, and a `--impersonate` target it doesn't have
fails hard. `pin-dns` handles this for you: it discovers the installed profiles (from the
`curl_chrome*` wrappers beside the binary) and maps your detected Chrome major to the
nearest available target at or below it, warning when the two differ. Nothing to configure.

To keep stock curl (and its live, un-mapped version string) as the default without typing
`--client curl` every time, set `PIN_DNS_CLIENT=curl`; a `--client` flag still wins per call.

> **Warning:** the npm package named `curl-impersonate` (v0.0.0) is an unrelated stub,
> not the real tool. Do not install it. Use the GitHub Releases binaries.

## Argument placement

A bare hostname or IP anywhere in the arguments is recognized as the target -- put it wherever is convenient:

```bash
pin-dns https://www.example.com origin.example.net -o out.html
pin-dns https://www.example.com -o out.html origin.example.net
pin-dns https://www.example.com -o out.html --target origin.example.net
```

Everything after `--` goes to curl verbatim and pin-dns stops looking for its own options:

```bash
pin-dns --target origin.example.net -- https://www.example.com -v
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `--host HOSTNAME` | Explicit hostname (overrides any host inferred from URL) |
| `--target TARGET` | Hostname or IP to pin to. Also: `--target=VALUE`. Required when using curl's `--url` |
| `--path PATH_OR_URL` | Request path or full URL. Also: `--path=VALUE` |
| `--resolver DNS_SERVER_IP` | DNS server for `dig` to use when resolving TARGET |
| `--scheme SCHEME` | URL scheme (default: `https`) |
| `--port PORT` | Port (default: `443`) |
| `--platform mac\|win\|linux` | UA shape and `Sec-CH-UA-Platform` (default: `mac`) |
| `--fetch-mode navigate\|cors\|no-cors` | Request profile: `Accept` + `Sec-Fetch-*` set (default: `navigate`). `navigate` = page load; `cors`/`no-cors` = in-page fetch/XHR |
| `--client curl\|impersonate\|auto` | `auto` (default) uses curl-impersonate if on `PATH`, else stock curl. `impersonate` requires it (exit 3 if absent); `curl` forces stock curl. `curl-impersonate` is accepted as an alias for `impersonate` |
| `--chrome-major N` | Pin the Chrome major version; skips all version detection |
| `--no-impersonate` | Send a bare request (DNS pin only); emit no impersonation headers. Master off-switch (overrides `--client`) |
| `--dry-run` | Print the curl command without executing |
| `--no-silent` | Don't add `curl -sS` |
| `-q, --quiet` | Suppress info/warning messages (errors still shown) |
| `--curlrc` | Allow curl to read `~/.curlrc` (normally disabled) |
| `-h, --help` | Show built-in help |

### Providing the target

**With a URL** -- a lone bare hostname or IP anywhere in the arguments is used as the target:

```
pin-dns [OPTS...] URL [CURL_OPTS...] TARGET [CURL_OPTS...]
```

If there are multiple bare hostnames (ambiguous), use `--target` explicitly.

**Positional mode** -- when the first non-option argument is a bare hostname (not an `http(s)://` URL):

```
pin-dns HOSTNAME [TARGET] [PATH_OR_URL] [CURL_OPTS...]
```

1. **HOSTNAME** -- the host for the URL and TLS SNI (e.g. `www.example.com`)
2. **TARGET** -- hostname or IP to connect to (optional)
3. **PATH_OR_URL** -- request path, query string, or full URL (optional, defaults to `/`)

### PATH_OR_URL flexibility

PATH_OR_URL accepts several formats -- pin-dns extracts just the path:

```bash
pin-dns host target /path                              # plain path
pin-dns host target "path?q=1"                         # no leading slash (added automatically)
pin-dns host target "?q=1"                             # query only
pin-dns host target https://host/path?q=1              # full URL (host stripped, path kept)
pin-dns host target host/path                          # host/path (host stripped)
```

### Environment variables

| Variable | Description |
|---|---|
| `PIN_DNS_CHROME_APP` | Override Chrome app path for User-Agent detection. Default: `/Applications/Google Chrome.app` |
| `PIN_DNS_CHROME_MAJOR` | Pin the Chrome major (same as `--chrome-major`; the flag wins) |
| `PIN_DNS_CLIENT` | Default client when `--client` is absent: `curl\|impersonate\|auto` (same as `--client`; the flag wins). `auto` is the default, so `PIN_DNS_CLIENT=auto` is a no-op |
| `PIN_DNS_UA_OFFLINE` | Disable the network version fallback (Version History API) |
| `PIN_DNS_UA_CACHE_TTL` | Version-cache freshness in seconds. Default: `86400` |
| `PIN_DNS_VERSION_API_URL` | Override the Chrome Version History API base URL (advanced/testing) |
| `XDG_CACHE_HOME` | Cache root; the version cache lives under `$XDG_CACHE_HOME/pin-dns` (default `$HOME/.cache/pin-dns`) |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | Usage / argument error |
| `3` | Dependency error (curl or dig missing; or --client impersonate set but curl-impersonate not on PATH) |
| `4` | Resolution error (dig returned no results for TARGET) |

### Dependencies

- `curl` (required)
- `dig` (required only when TARGET is a hostname, not when it's an IP)
- Google Chrome (for local version detection; falls back to the Version History API, then a pinned major, if unavailable)
- `jq` (only for the network version fallback)
- `brotli` / `zstd` (only to decode those encodings on stdout; absence warns and emits raw)
- `curl-impersonate` (optional; enables TLS/HTTP-2 fingerprint matching -- see [Browser impersonation](#browser-impersonation))

### Warnings

pin-dns warns about two common mistakes:

1. **"pin-dns-looking token as curl operand"** -- if `-H --target` appears, `-H` consumes `--target` as a header value. Fix: reorder, use `--target=VALUE`, or use `--`.

2. **"useless -s / -S"** -- pin-dns already adds `-sS`. Passing them again is harmless but probably unintended. Fix: use `--no-silent` if you want control over curl's silent mode.
