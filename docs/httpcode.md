# httpcode

Quick reference for HTTP status codes. Look up what any status code means without leaving the terminal.

This is a lookup tool that prints descriptions of HTTP status codes from embedded MDN reference data. Think of it as a cheat sheet: you see `418` in a log, run `httpcode 418`, and get the name and description instantly. For timing HTTP requests (phase breakdown, summary statistics, outlier detection), see [`curl-timing`](curl-timing.md?html).

## Quick start

```
$ httpcode 404
404 Not Found

The server cannot find the requested resource. In the browser, this means the URL is not recognized. In an API, this can also mean that the endpoint is valid but the resource itself does not exist. Servers may also send this response instead of 403 Forbidden to hide the existence of a resource from an unauthorized client. This response code is probably the most well known due to its frequent occurrence on the web.

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404
```

## Common examples

**Check what the teapot code means:**

```
$ httpcode 418
418 I'm a teapot

The server refuses the attempt to brew coffee with a teapot.

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/418
```

**Understand rate limiting:**

```
$ httpcode 429
429 Too Many Requests

The user has sent too many requests in a given amount of time (rate limiting).

https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/429
```

**Look up a Cloudflare-specific code:**

```
$ httpcode 522
522 Connection Timed Out (Cloudflare)

Non-standard Cloudflare code. Cloudflare could not negotiate a TCP handshake with the origin server.

https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/
```

## Coverage

All standard HTTP status codes from MDN are included:

- 1xx: Informational responses (100-103)
- 2xx: Successful responses (200-226)
- 3xx: Redirection messages (300-308)
- 4xx: Client error responses (400-451)
- 5xx: Server error responses (500-511)

Plus common non-standard vendor codes:

- Cloudflare: 520-527, 530
- nginx: 444, 494, 499
- IIS: 440, 449

The data is embedded in the script, so no network access is required. The current snapshot date is stored in the `_snapshot` field of the embedded JSON.

## Updating the data

The embedded data rarely changes — MDN occasionally tweaks descriptions, vendors occasionally add a new non-standard code. Aim to refresh once a year or after noticing stale wording.

### Step 1: Scrape MDN

Open <https://developer.mozilla.org/en-US/docs/Web/HTTP/Status> in a browser. Paste this into the DevTools console:

```js
copy(JSON.stringify(Object.fromEntries(
    [...document.querySelectorAll('article > section dt:not(.bc-legend-item-dt)')].map(dt => [
        dt.id.substring(0, 3),
        {
            name: dt.querySelector('code').innerText.substring(4),
            message: dt.nextElementSibling.innerText
        }
    ])
)));
```

This copies a JSON object keyed by status code to the clipboard. Paste it into a file:

```bash
pbpaste > /tmp/statuses-mdn.json
```

**If the scrape breaks** (MDN changed their HTML structure), the selectors to update are at the top of the snippet. The page layout is: each code is a `<dt>` with `id="NNN_name"`, containing a `<code>` with the text `NNN Name`, followed by a `<dd>` with the description. Inspect one `<dt>` in DevTools to re-derive the selectors.

### Step 2: Maintain the vendor codes by hand

Keep this JSON here in the doc — if a vendor adds or renames a code, edit it in place. Save as `/tmp/statuses-vendor.json`:

Each vendor entry includes a `source` field pointing at the authoritative docs for that code. The script prefers this per-entry URL over the default MDN base, which means lookups for vendor codes land on the vendor's own docs instead of a 404 on MDN.

```json
{
    "440": {"name": "Login Time-out (IIS)", "message": "Non-standard IIS code. The client's session has expired and must log in again.", "source": "https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#Internet_Information_Services"},
    "444": {"name": "No Response (nginx)", "message": "Non-standard nginx code. The server returns no information and closes the connection. Used to deter malicious clients.", "source": "https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#return"},
    "449": {"name": "Retry With (IIS)", "message": "Non-standard IIS code. The server cannot honor the request because the user has not provided the required information.", "source": "https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#Internet_Information_Services"},
    "494": {"name": "Request Header Too Large (nginx)", "message": "Non-standard nginx code. The client sent too large a request or too long a header line.", "source": "https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#nginx"},
    "499": {"name": "Client Closed Request (nginx)", "message": "Non-standard nginx code. The client closed the connection while the server was still processing the request.", "source": "https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#nginx"},
    "520": {"name": "Web Server Returned an Unknown Error (Cloudflare)", "message": "Non-standard Cloudflare code. Cloudflare encountered an empty, unknown, or unexpected response from the origin server.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "521": {"name": "Web Server Is Down (Cloudflare)", "message": "Non-standard Cloudflare code. The origin server refused connections from Cloudflare.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "522": {"name": "Connection Timed Out (Cloudflare)", "message": "Non-standard Cloudflare code. Cloudflare could not negotiate a TCP handshake with the origin server.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "523": {"name": "Origin Is Unreachable (Cloudflare)", "message": "Non-standard Cloudflare code. Cloudflare could not reach the origin server (DNS resolution failure or no route to host).", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "524": {"name": "A Timeout Occurred (Cloudflare)", "message": "Non-standard Cloudflare code. Cloudflare was able to complete a TCP connection but timed out waiting for an HTTP response.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "525": {"name": "SSL Handshake Failed (Cloudflare)", "message": "Non-standard Cloudflare code. Cloudflare could not negotiate a SSL/TLS handshake with the origin server.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "526": {"name": "Invalid SSL Certificate (Cloudflare)", "message": "Non-standard Cloudflare code. Cloudflare could not validate the SSL certificate on the origin server.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "527": {"name": "Railgun Error (Cloudflare)", "message": "Non-standard Cloudflare code. The request timed out or failed after the WAN connection was established.", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"},
    "530": {"name": "Origin DNS Error (Cloudflare)", "message": "Non-standard Cloudflare code. 1XXX error from Cloudflare (see the 1XXX code in the response body).", "source": "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/"}
}
```

Authoritative sources to spot-check:
- Cloudflare: <https://developers.cloudflare.com/support/troubleshooting/http-status-codes/> — rarely changes; 527 is now deprecated (Railgun is EOL); new 5xx codes appear every few years.
- nginx: <https://nginx.org/en/docs/http/ngx_http_core_module.html> — 444 is documented there; 494 and 499 are internal-use codes defined in `ngx_http_request.h`. Unlikely to change.
- IIS: Microsoft's docs are scattered; <https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#Internet_Information_Services> is the most convenient canonical list. Legacy, unlikely to change.

### Step 3: Merge and produce the final JSON

With `statuses-mdn.json` (from Step 1) and `statuses-vendor.json` (from Step 2):

```bash
jq -s --arg snapshot "$(date +%Y-%m-%d)" '
    .[0] * .[1] + {
        _source: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status",
        _snapshot: $snapshot,
        _sources: {
            mdn:        "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status",
            cloudflare: "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/",
            nginx:      "https://nginx.org/en/docs/http/ngx_http_core_module.html",
            iis:        "https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#Internet_Information_Services"
        }
    }
' -c /tmp/statuses-mdn.json /tmp/statuses-vendor.json > /tmp/statuses-merged.json
```

The `-s` slurps both files into one array; `.[0] * .[1]` deep-merges them (vendor entries win on conflict, so you can override MDN wording for a given code by adding an entry to the vendor JSON); the trailing object stamps the metadata; `-c` produces a single compact line, which is what the script expects.

### Step 4: Paste into `httpcode`

Copy `/tmp/statuses-merged.json` to your clipboard:

```bash
pbcopy < /tmp/statuses-merged.json
```

Open `/repo/sh/httpcode` and replace the single JSON line inside the heredoc (the line between `<<'EOF'` and `EOF`) with the new content. Keep the surrounding bash unchanged.

Then run the tests to confirm the script still parses everything correctly:

```bash
/bin/bash /repo/sh/test-runner.sh httpcode
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Display help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (code found and displayed) |
| 2 | Usage error (missing or unknown status code) |
| 3 | Dependency error (jq not installed) |

### Dependencies

- `jq` (jqlang.github.io) — required for parsing the embedded JSON
