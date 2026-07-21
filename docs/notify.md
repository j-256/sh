# notify

[View script](../notify)

Show a macOS notification via osascript. Perfect for announcing when a long-running command finishes - pop a notification while you're in another tab or app, then come back when it's done.

The notification appears in the top-right corner of your screen, plays a sound (optional), and shows up in Notification Center. Notifications are attributed to Script Editor (the osascript host app).

## Quick start

```
$ notify "Build finished"
```

## Common examples

**Get notified when a long-running command completes:**

```
$ make && notify "make succeeded" || notify --title "Build failed" "Check logs"
```

**Pipe command output into a notification:**

```
$ curl -s https://api.example.com/status | jq -r '.message' | notify --title "API Status"
```

**Add a subtitle for more context:**

```
$ npm test && notify --title "Tests passed" --subtitle "All 47 specs" "Ready to deploy"
```

**Silent notification (no sound):**

```
$ rsync -av large-dir/ backup/ && notify --no-sound "Backup complete"
```

**Custom sound:**

```
$ brew upgrade && notify --sound Funk "Homebrew packages updated"
```

**See all available sounds:**

```
$ notify --list-sounds
Basso
Blow
Bottle
Frog
Funk
Glass
Hero
...
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-t, --title TITLE` | Notification title (default: "Notification") |
| `-s, --subtitle SUBTITLE` | Notification subtitle |
| `-S, --sound SOUND` | Sound name (default: "Glass") |
| `-n, --no-sound` | Suppress notification sound |
| `-l, --list-sounds` | List available sound names and exit |
| `-h, --help` | Show help and exit |

Options can appear before or after the message. The message can be passed as arguments or piped to stdin.

### Environment variables

| Variable | Description |
|---|---|
| `NOTIFY_TITLE` | Default title (overridden by `--title`) |
| `NOTIFY_SOUND` | Default sound (overridden by `--sound` / `--no-sound`) |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | Invalid arguments or missing required message |
| `3` | osascript not found (not running on macOS) |

### Dependencies

- `osascript` (macOS native, part of the system)

Notification duration is controlled by macOS, not this script. Configure it in System Settings > Notifications > Script Editor.
