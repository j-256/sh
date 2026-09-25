# slow-server

[View script](../scripts/slow-server)

Keep existing numeric-path delay tests working through [flaky-server](flaky-server.md), the unified HTTP origin for delays, partial responses, status errors, empty closes, and trickles. `slow-server` is a compatibility launcher with no separate HTTP implementation. Use `flaky-server` for new tests.

## Quick start

```sh
$ slow-server 9000
[INF][flaky-server] Starting server at http://localhost:9000 (all IPv4 interfaces)

# In another terminal
$ curl http://localhost:9000/2500
2500
```

The reply arrives after approximately 2.5 seconds. Omitting the port still selects 8080. Numeric final segments such as `/service/2500` also work, and unknown non-numeric paths return 404.

## Common examples

**Run without installing:**

```sh
$ curl -fsS https://toolio.sh/slow-server | bash -s -- 9000
```

The launcher uses a sibling `flaky-server` first, then an executable on PATH. If neither exists, it downloads `https://toolio.sh/flaky-server` with curl and runs the complete successful download. Install both scripts together or put `flaky-server` on PATH for offline startup. Help works offline.

**Test a client timeout:**

```sh
$ curl --max-time 1 http://localhost:9000/3000
curl: (28) Operation timed out ...
```

**Move a connection-close test to the unified command:**

```sh
$ flaky-server 9000

# In another terminal
$ curl -i http://localhost:9000/drop/2000
```

The behavior is selected by the request URL. There is no `drop` startup subcommand.

## Compatibility

Durations are decimal integers from 0 through 2147483647 milliseconds. Leading zeroes are decimal. Fractional-second conversion preserves milliseconds, including values below 100. Query strings and trailing slashes do not change a legacy delay. Explicit behavior paths take precedence over the legacy numeric-segment rule; invalid values return 400.

See [flaky-server](flaky-server.md) or run `flaky-server -h` for the complete request interface, including error fixtures and stream controls.

The server speaks plain HTTP on all IPv4 interfaces. Use a tunnel for HTTPS and verify its actual buffering and error handling. It tests transport failures, not valid SOAP replies. POST bodies with `Content-Length` and `Expect: 100-continue` are accepted; chunked requests return 501. HEAD and statuses 204, 205, and 304 have no body.

Request bodies are limited to 1 MiB, request/header lines to 8192 bytes, and headers to 100 lines. Reads have a ten-second timeout. Invalid framing, incomplete reads, and exceeded read limits close the connection with a diagnostic. Startup and request diagnostics go to stderr; stdout stays clean. Stop with Ctrl-C; active connections can finish after the listener stops. See [flaky-server](flaky-server.md) for worked examples and request diagnostics.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `port` | Optional decimal TCP port from 1 through 65535; default 8080 |
| `-h, --help` | Display help without starting or downloading a server |
| `--` | End option parsing |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Help or clean listener exit |
| 1 | Download, listener, or runtime failure |
| 2 | Invalid arguments |
| 3 | Missing dependency |

### Dependencies

- `flaky-server` beside the launcher or on PATH, or `curl` and network access to download it
- `socat` and `sleep` with fractional-second support, required by `flaky-server`
