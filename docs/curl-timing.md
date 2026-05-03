# curl-timing

[View script](../curl-timing)

Time HTTP requests with curl and get a quick statistics summary -- count, total, average, range, and IQR-based outliers -- in milliseconds. Point it at one URL to spot-check latency, or at several to compare endpoints head-to-head.

Designed for the kind of quick-and-dirty measurement where you don't want to reach for `wrk` or `ab`, but "time it with a stopwatch five times" isn't rigorous enough. Timings are written to a text file so you can re-run `stats` or diff between runs later.

## Quick start

```
$ curl-timing https://example.com
Sending 10 requests to 1 URL(s):
[1]: https://example.com

[1/1] Sending 10 requests to URL 1 of 1...
https://example.com
[1/1] Time logged to: /tmp/curl-timing.txt

[1/1](01/10) 142ms
[1/1](02/10) 138ms
...
[1/1](10/10) 141ms
Statistics saved to: /tmp/curl-timing_stats.txt

140, 138, 142, 141, 139, 143, 140, 141, 138, 142
Count: 10
Total: 1404
Average: 140
Range: 5 (138 to 143)
Outliers: 
          0 of 10 (0.0%)
```

## Common examples

**Change the number of requests:**

```bash
curl-timing -n 50 https://example.com
```

**Add warmup requests** (don't count the first few, to exclude cold-cache effects):

```bash
curl-timing -w 3 -n 20 https://example.com
```

**Compare two URLs side by side:**

```bash
curl-timing https://example.com https://example.org/path
```

Each URL gets its own log (`curl-timing-1.txt`, `curl-timing-2.txt`) and its own stats block, so you can eyeball averages in one run.

**Add a delay between requests** (avoid hammering the origin):

```bash
curl-timing -s 0.5 https://example.com
```

**Send a POST with a JSON body:**

```bash
curl-timing -d '{"q":"shoes"}' -H 'Content-Type: application/json' https://example.org/search
```

`-X POST` is inferred from `-d`. Override with `-X PUT`, `-X PATCH`, etc.

**Send custom headers** (auth, tracing, etc.):

```bash
curl-timing -H 'Authorization: Bearer abc123' -H 'X-Debug: 1' https://api.example.com/me
```

**Quiet mode** -- skip per-request lines, just print the summary:

```bash
curl-timing -q -n 100 https://example.com
```

**Ephemeral run** -- don't write log or stats files:

```bash
curl-timing --no-save https://example.com
```

## How timings are measured

curl-timing uses curl's `%{time_total}` write-out variable, which is the wall-clock time from the moment curl starts processing the URL until the transfer finishes. That includes DNS, TCP/TLS handshake, request send, server processing, and response download.

The response body is piped to `/dev/null` -- only the timing matters, not the content. If you need the body as well, run curl directly.

## Output files

By default curl-timing writes two files per URL to the current directory:

| File | Contents |
|---|---|
| `curl-timing.txt` | One timing per line, in milliseconds, in the order captured |
| `curl-timing_stats.txt` | Dataset listing plus count/total/average/range/outliers |

With multiple URLs, filenames are numbered: `curl-timing-1.txt`, `curl-timing-1_stats.txt`, `curl-timing-2.txt`, and so on.

Existing files are backed up to `.bak` before being overwritten. Use `--no-save` to skip writing anything.

## Outlier detection

Outliers are flagged using the Interquartile Range (IQR) method: anything below `Q1 - 1.5 * IQR` or above `Q3 + 1.5 * IQR` is called an outlier. Useful for spotting the one slow request in twenty that'll skew your average.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-n, --num N` | Number of timed requests per URL (default: 10) |
| `-w, --warmup N` | Warmup requests before timing (not logged, default: 0) |
| `-s, --sleep SECONDS` | Sleep between requests (default: none) |
| `-X, --method METHOD` | HTTP method (default: GET; POST inferred if `-d` is given) |
| `-H, --header HEADER` | Extra request header, repeatable |
| `-d, --data DATA` | Request body (implies POST unless `-X` is set) |
| `-A, --user-agent UA` | User-Agent header (default: `curl-timing/1.0`) |
| `--no-save` | Do not write per-URL log or stats files |
| `-q, --quiet` | Suppress per-request output; only show summary |
| `-h, --help` | Show built-in help |

Options may appear in any order, and may be placed before or after URLs. Use `--` to stop option parsing if a URL starts with `-`.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All requests sent successfully |
| `2` | Usage / argument error |
| `3` | Dependency error (`curl` or `bc` missing) |

### Dependencies

- `curl` -- used for the actual requests and timing measurement
- `bc` -- used by the stats summary for IQR and outlier math

### Caveats

- curl-timing does not assert on HTTP status. A 500 response is timed the same as a 200. For endpoint health checks, pair with curl's `-f` / `--fail` via `-X` or run the summary alongside a separate status check.
- Timings include network variance from your machine. Run from a stable network (or a cloud VM close to the target) if you want repeatable numbers.
- Sub-millisecond responses round down to 0ms -- expected for local servers. Add `-s 0.05` or warm up with `-w 5` if you're seeing implausibly tight results.

### See also

- `stats` -- run on an existing timing file to re-compute the summary
- `pin-dns` -- time a request against a specific edge/origin IP, bypassing DNS
- `httpcode` -- explain HTTP status codes
