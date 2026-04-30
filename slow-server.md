# slow-server

Test how your code handles slow responses -- without waiting for an actual slow server to come back online, or fighting with production timeouts. `slow-server` starts a local HTTP server that responds after whatever delay you ask for, letting you verify timeout logic, retry behavior, loading states, and health check thresholds.

Built on `socat`, it's lightweight and easy to kill when you're done testing. You control the delay by hitting a URL with the millisecond value as the last path segment. Hit it with a non-numeric path and you get a 404, so you can test error handling too.

## Quick start

```
$ slow-server
Starting server at http://localhost:8080

# In another terminal:
$ curl http://localhost:8080/2500
2500
```

The server responds after 2.5 seconds (2500 milliseconds). It echoes the delay value in the response body.

## Common examples

**Run on a different port:**

```
$ slow-server 3000
Starting server at http://localhost:3000
```

**Test a timeout by requesting a delay longer than your client allows:**

```
$ curl --max-time 1 http://localhost:8080/3000
curl: (28) Operation timed out after 1001 milliseconds with 0 bytes received
```

Your timeout fired before the 3-second delay completed.

**Verify fast responses still work (0ms delay):**

```
$ curl http://localhost:8080/0
0
```

**Trigger a 404 to test error handling:**

```
$ curl -i http://localhost:8080/notanumber
HTTP/1.1 404 Not Found
```

**Test health checks with a known-good delay:**

```
$ curl http://localhost:8080/500
500
```

If your load balancer expects a response within 1 second, a 500ms delay verifies it stays healthy.

## Server behavior

The server runs until you kill it (Ctrl-C or `kill`). Each request is logged to stderr showing the method, path, and delay:

```
GET /2500 (2500)
Done: GET /2500 (2500)
```

Non-numeric paths log `[ignored]` and return 404 immediately:

```
GET /notanumber (notanumber) [ignored]
```

The server uses `socat` with `fork` to handle concurrent requests -- each request gets its own process, so multiple clients can test different delays at the same time without blocking each other.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `port` | Port to listen on (default: 8080). First positional argument. |
| `-h, --help` | Display help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Clean shutdown (e.g., via Ctrl-C) |
| 1 | Missing dependency (socat not found) |

### Dependencies

- **socat** -- used to run the HTTP server. Install via `brew install socat` on macOS or your package manager.
- **sleep** -- must support fractional seconds (standard on macOS and modern Linux).
