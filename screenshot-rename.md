# screenshot-rename

Automatically rename macOS screenshots from the verbose default format to a clean timestamp-only name. Instead of `Screenshot 2026-04-21 at 14.23.15.png`, you get `2026-04-21 14.23.15.png`.

Runs as a watcher — when you take a screenshot, it gets renamed immediately. Useful if you accumulate screenshots and want them sorted chronologically without the redundant "Screenshot" prefix cluttering your Desktop.

## Quick start

```bash
$ screenshot-rename
Watching for new screenshots in: /Users/you/Desktop
Renaming screenshot: /Users/you/Desktop/Screenshot 2026-04-21 at 14.23.15.png -> 2026-04-21 14.23.15.png
```

By default the script watches the macOS-configured screenshot location (from `defaults read com.apple.screencapture location`) and falls back to `~/Desktop` when that setting isn't configured. Press `Ctrl+C` to stop the watcher.

## Common examples

**Watch a custom directory:**

```bash
$ screenshot-rename --path ~/Pictures/Screenshots
Watching for new screenshots in: /Users/you/Pictures/Screenshots
```

**Use UTC timestamps instead of local time:**

```bash
$ screenshot-rename --utc
```

**Use a different filename format:**

```bash
$ screenshot-rename --format "%Y%m%d-%H%M%S"
```

## Naming scheme

The default filename format is `%Y-%m-%d %H.%M.%S` (dots instead of colons for filesystem compatibility), producing names like `2026-04-21 14.23.15.png`. Override with `--format` (strftime syntax); the `.png` extension is always appended.

The timestamp is captured at the moment of rename, not extracted from the original filename. If a file with the same timestamp already exists, a counter is appended: `2026-04-21 14.23.15-1.png`, `2026-04-21 14.23.15-2.png`, etc.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `--path PATH` | Directory to watch (default: macOS screenshot location, or `~/Desktop`) |
| `--format FORMAT` | strftime format for new filenames (default: `%Y-%m-%d %H.%M.%S`) |
| `-u, --utc` | Use UTC timezone instead of local time |
| `-h, --help` | Show help |

### Dependencies

- `fswatch` — file change monitor (install via Homebrew: `brew install fswatch`)
- `defaults` — macOS-native, used to look up the configured screenshot location
