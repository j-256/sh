# pin-dns

curl wrapper that overrides DNS resolution for a hostname -- bypass CDNs, hit origin servers, or pin requests to a specific IP, without touching /etc/hosts or system DNS.

Under the hood it builds a `curl --resolve` command for you and adds sensible defaults (silent mode, realistic User-Agent, curlrc disabled).

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

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | Usage / argument error |
| `3` | Dependency error (curl or dig missing) |
| `4` | Resolution error (dig returned no results for TARGET) |

### Dependencies

- `curl` (required)
- `dig` (required only when TARGET is a hostname, not when it's an IP)
- Google Chrome (for User-Agent detection; falls back to `sfcc-test` if unavailable)

### Warnings

pin-dns warns about two common mistakes:

1. **"pin-dns-looking token as curl operand"** -- if `-H --target` appears, `-H` consumes `--target` as a header value. Fix: reorder, use `--target=VALUE`, or use `--`.

2. **"useless -s / -S"** -- pin-dns already adds `-sS`. Passing them again is harmless but probably unintended. Fix: use `--no-silent` if you want control over curl's silent mode.
