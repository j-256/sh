# colorize-url

Apply distinct ANSI colors to URL components (scheme, host, path, query, fragment) for readability. Query string keys and values get separate colors.

Useful when inspecting URLs in logs, debugging API requests, or comparing similar URLs -- the color-coding makes structural differences pop.

## Quick start

```
$ colorize-url https://example.com/products?category=shirts&page=2
```

Output (colors shown conceptually):
```
https://example.com/products?category=shirts&page=2
^^^^^            ^^^ ^^^^^^^^  ^^^^^^^^       ^^^^
gray             white cyan     yellow green  yellow green
     ^^^                     ^        ^      ^
     white                   darker   white  darker
```

In practice: scheme is gray, hostname is bright white, path is bright cyan with white slashes, query parameter keys are bright yellow, values are green, and separators (`?`, `&`, `=`) are dimmed.

## Common examples

**Pipe URLs from logs or commands:**

```bash
echo "https://api.example.net/v2/users/42?format=json" | xargs colorize-url
```

**Compare two similar URLs side-by-side** (with terminal tools like `diff` or `colordiff`):

```bash
colorize-url "https://api.example.net/v1/users/42" > /tmp/url1
colorize-url "https://api.example.net/v2/users/42" > /tmp/url2
diff /tmp/url1 /tmp/url2
```

**Inspect fragment identifiers:**

```bash
colorize-url "https://docs.example.com/api/reference#authentication"
```

**Handle edge-case query strings** (empty values, valueless keys):

```bash
colorize-url "https://example.com/?debug&key=&foo=bar"
```

Output preserves whether `=` was present: `debug` (no `=`), `key=` (empty value with `=`), `foo=bar` (normal pair).

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Show help message |

### Color scheme

- **Scheme** (`https`): bright black (gray)
- **Hostname**: bright white
- **Path segments**: bright cyan
- **Path slashes**: white
- **Query keys**: bright yellow
- **Query values**: green
- **Query separators** (`?`, `&`): black (dimmed)
- **Equals signs**: white
- **Fragment** (`#...`): white

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | No URL provided |

### Dependencies

None (pure bash string manipulation with ANSI escape codes).
