# render-md

[View script](../render-md)

Render markdown to HTML and open it in your browser. The output uses GitHub-like styling with automatic dark/light mode.

> **Note:** Unlike the other scripts in this repo, `render-md` is a Node.js CLI (a self-contained single file, but it needs Node ≥ 18 on your `$PATH`). Everything else in the catalog is bash. If you don't have Node yet, `brew install node` is the fast path; `pwa-prereqs --install` also handles it.

## Quick start

```bash
render-md README.md
```

That's it -- your browser opens with the rendered page. Relative links and images resolve against the source file's directory.

Pipe from stdin:

```bash
cat CHANGELOG.md | render-md
```

## Common examples

**Write HTML to a file instead of opening the browser:**

```bash
render-md README.md -o readme.html
```

**Write HTML to stdout** (for piping into other tools):

```bash
render-md README.md -o -
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-o FILE` | Write HTML to FILE instead of opening in browser |
| `-o -` | Write HTML to stdout |
| `-h, --help` | Show help |

### Environment variables

| Variable | Description |
|---|---|
| `BROWSER` | Override which browser to open. Default: first available of Chrome, Edge, Firefox, Safari |

### Dependencies

Requires Node.js. The `marked` markdown parser is bundled into the script -- no `npm install` needed at runtime.
