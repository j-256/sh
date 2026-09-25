# flaky-server

[View script](../scripts/flaky-server)

Run one deliberately unreliable HTTP origin to test client timeouts, retries, HTTP errors, connections that close mid-response, and slow body delivery. Each request path chooses its behavior, so a fixed tunnel hostname can serve every test without restarting the origin.

The server uses Bash and socat. It accepts SOAP-style POST requests, but its replies are transport fixtures, not valid SOAP responses. Use it to distinguish a client read timeout from an origin that starts responding and then closes.

## Quick start

```sh
$ flaky-server 9000
[INF][flaky-server] Starting server at http://localhost:9000 (all IPv4 interfaces)

# In another terminal, wait two seconds, receive partial XML, then lose the connection
$ curl -i http://localhost:9000/drop/2000
HTTP/1.1 200 OK
...
Content-Length: 100000

<?xml version="1.0"?><soapenv:Envelope><partial
curl: (18) end of response with bytes missing
```

The exact curl diagnostic varies by version. The origin advertises a large body, writes only the XML fragment, and closes. The listener stays available for the next request.

Run without installing:

```sh
$ curl -fsS https://toolio.sh/flaky-server | bash -s -- 9000
```

The local command and curl-pipe command start the same server. Request paths select behavior in both cases; there is no startup `drop` subcommand. Omit the port for `8080`. Read the complete interface with `flaky-server -h` or `curl -fsS https://toolio.sh/flaky-server | bash -s -- -h`.

## Common examples

**Delay the complete response until a client times out:**

```sh
$ curl --max-time 1 http://localhost:9000/delay/2500
curl: (28) Operation timed out ...
```

**Exercise an HTTP failure without a transport failure:**

```sh
$ curl -i http://localhost:9000/status/503
HTTP/1.1 503 Test status
...
503
```

Use `curl -f` when you want an HTTP error status to produce a nonzero curl exit. Without `-f`, receiving a complete 503 response is a successful transfer.

**Close without sending an HTTP response:**

```sh
$ curl -i http://localhost:9000/reset
```

This closes after the request line. Depending on the socket state, curl can report an empty reply or a connection reset. A TCP RST is not guaranteed.

**Test response-body read timeouts with a slow stream:**

```sh
$ curl -Ni http://localhost:9000/trickle/5000
```

Headers arrive first, followed by ten dots distributed over the requested duration. `-N` disables curl's output buffering. No extra settings are needed.

**Set a data rate with sensible defaults:**

```sh
$ curl -Ni http://localhost:9000/rate/1024
```

This sends 10 KiB of dots at approximately 1 KiB per second, in 1 KiB writes. It takes approximately ten seconds. The rate is in bytes per second.

**Control body size, content, and delivery shape:**

```sh
$ curl -N 'http://localhost:9000/trickle/5000?bytes=1024&chunk=128&type=json'
$ curl -N 'http://localhost:9000/rate/1024?bytes=4096&chunk=2048&type=xml'
```

The first example spreads a complete 1024-byte JSON document over five seconds in 128-byte writes. The second sends a complete 4096-byte XML document in two bursts, each after approximately two seconds. Smaller chunks produce steadier delivery; larger chunks create longer pauses between bursts. Quote URLs containing query parameters so the shell passes the `&` characters literally.

**Keep using a numeric delay URL:**

```sh
$ curl http://localhost:9000/2500
2500
$ curl http://localhost:9000/service/2500
2500
```

**Send a SOAP-style POST through the existing tunnel:**

```sh
$ curl -i -H 'Content-Type: text/xml' \
    --data '<Envelope/>' \
    https://YOUR-EXISTING-TUNNEL/drop/2000
```

Replace the example hostname with your tunnel's hostname and keep its origin pointed at `http://localhost:9000`. The delay belongs in the URL and is measured in milliseconds. Change the SOAP client's endpoint path to `/drop/2000` for a two-second delay before the partial response.

## Request paths

| Path | Behavior |
|---|---|
| `/delay/<ms>` | Wait, then return 200 with the supplied value and a newline |
| `/drop/<ms>` | Wait, send partial XML advertising `Content-Length: 100000`, then close |
| `/status/<code>` | Return a final status from 200 through 599 immediately |
| `/reset` | Close after the request line without a response |
| `/trickle/<ms>` | Send headers immediately, then a complete body spread over the duration |
| `/rate/<bps>` | Send headers immediately, then a complete body at approximately `bps` bytes per second |
| `/<ms>` | Legacy delay, also accepted as the last segment of other unrecognized paths |

Durations are decimal integers from `0` through `2147483647` milliseconds. Rates are decimal integers from `1` through `1048576` bytes per second. Leading zeroes are decimal, so `/delay/005` waits five milliseconds. Timing starts after reading the request, including any framed body. Trailing slashes and unrelated query keys are ignored.

Explicit behavior names take precedence: `/status/503` returns 503; it does not wait 503 milliseconds. Missing or invalid behavior values return 400. Unknown non-numeric paths return 404. Informational statuses below 200 are not accepted as final responses.

## Stream controls

Only `/trickle` and `/rate` use these optional query parameters. All other behaviors ignore query parameters.

| Parameter | Meaning | Default |
|---|---|---|
| `bytes=<n>` | Exact encoded body size, including XML/JSON wrappers; 1 through 1048576 bytes | `/trickle`: 10 for text, 1024 for XML/JSON; `/rate`: 10240 |
| `chunk=<n>` | Bytes per write; 1 through 1048576, with at most 1024 writes | `ceil(bytes / 10)`, giving about ten writes |
| `type=text` | Dots with `text/plain; charset=utf-8` | Default format |
| `type=xml` | `<data>...</data>` with `application/xml; charset=utf-8` | At least 13 bytes |
| `type=json` | `{"data":"..."}` with `application/json` | At least 11 bytes |

XML and JSON contain dot padding inside a complete document; the dots shown above stand for the padding. Setting only `?type=json` or `?type=xml` works without choosing a size. Invalid, out-of-range, or duplicate controls return 400. Numeric values are decimal integers; no unit suffixes are accepted.

Headers are immediate. The handler waits before each write in proportion to that write's byte count. A final short write has a proportionally shorter wait. A chunk larger than the body produces one write at the end. `/trickle/0` sends the whole body without sleeping. `/rate` derives the duration from total bytes and the requested rate, rounded up to a millisecond.

This controls application writes, not TCP packet boundaries. Scheduling and process startup add overhead, so measured rates are approximate and tiny chunks increase the overhead. Millisecond scheduling can coalesce writes with zero-length intervals. Use these controls for timeout and buffering tests; measure the actual arrival pattern at the client, especially through a tunnel.

## HTTP and tunnel behavior

The origin speaks plain HTTP/1.0 and HTTP/1.1 over IPv4. Use your tunnel for HTTPS. Each accepted connection gets its own handler; one delayed request does not block another. Replies include `Connection: close`, and each connection serves one request.

Requests with `Content-Length` bodies are read and discarded, including SOAP POSTs. `Expect: 100-continue` is supported. Chunked request bodies return 501, and unsupported expectations return 417. Invalid or duplicate content lengths close the connection and produce a diagnostic. Request bodies are limited to 1 MiB, request/header lines to 8192 bytes, and headers to 100 lines. Each request read has a ten-second timeout; a timeout, incomplete upload, or exceeded read limit closes the connection.

HEAD requests return headers without a body, so use GET or POST for truncated-body and trickle tests. Statuses 204, 205, and 304 have no body. The XML fragment from `/drop` is deliberately incomplete; successful delay and status replies use plain text.

A tunnel or proxy may buffer the trickled body, substitute a gateway error for a dropped origin connection, or enforce its own timeout. Verify the actual client-visible result through that tunnel before using it as evidence of client behavior. Direct-origin results do not establish what the tunnel will expose.

## Compatibility and diagnostics

[slow-server](slow-server.md) remains a compatibility launcher. Existing `slow-server [port]` commands and numeric delay paths work through this implementation. Prefer `flaky-server` for new invocations.

Startup and per-request logs go to stderr. Request events identify the method, selected behavior, configured delay, and status. Stream events include body size, chunk size, content type, scheduled duration, and requested rate. Completion events report sent bytes, advertised bytes, and elapsed whole seconds. Invalid stream controls produce a diagnostic reason. The request ID in each event also appears in the response's `X-Request-ID` header. Empty closes have an ID in the log only. Request bodies, headers, and raw query strings are not logged.

The listener runs until stopped with Ctrl-C. Deliberate failures affect only their request. Active connections can finish after the listener is stopped.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `port` | Optional decimal TCP port from 1 through 65535; default 8080 |
| `-h, --help` | Display help without starting a server |
| `--` | End option parsing |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Help or clean listener exit |
| 1 | Listener or runtime failure |
| 2 | Invalid arguments |
| 3 | Missing dependency |

These codes describe the server command. Deliberate HTTP and connection failures are observed by the client and do not stop the listener.

### Dependencies

- `socat`: install with `brew install socat` on macOS or your Linux package manager
- `sleep` with fractional-second support, as provided by macOS and common Linux distributions
- `curl` for the download and client examples
