# notify

[View script](../notify)

Turn command completions into macOS Notification Center alerts, synthesized
speech, or both. `notify` accepts a message as arguments or standard input, so
it drops naturally into shell pipelines and `&&`/`||` completion hooks.

Notification-only output remains the default. Speech is opt-in, uses the macOS
`say` command directly, and can be tuned without exposing its rarely useful
audio-file and device-routing controls.

## Quick start

Notify yourself when a build finishes:

```
$ make && notify --say --title "Build" "Build finished"
```

## Common examples

**Display a standard notification**

```
$ notify "Backup complete"
```

**Speak without displaying a notification**

```
$ notify --say-only --voice Samantha --rate 190 "Tea is ready"
```

**Display a detailed message but speak a shorter one**

```
$ notify --say --say-text "Deploy healthy" "Production deployment completed successfully"
```

**Pipe output into the message**

```
$ printf '%s\n' "Database snapshot complete" | notify --title "Backup"
```

**Start speech without waiting for it to finish**

```
$ notify --say-only --background "Ten-minute timer started"
```

**Inspect the choices installed on this Mac**

```
$ notify --list-sounds
$ notify --list-voices
```

**Enable speech through the environment, then override it explicitly**

```
$ NOTIFY_SAY=yes notify "Spoken and displayed"
$ NOTIFY_SAY=yes notify --notify-only "Displayed only"
```

## Output modes

`notify` displays a notification unless speech is explicitly requested.
`--say` enables both outputs, while `--say-only` skips Notification Center.
`--notify-only` is useful when `NOTIFY_SAY` is normally enabled. If several
output-mode options are present, the last one wins.

Using `--voice`, `--rate`, `--say-text`, or `--background` without an explicit
mode implies `--say`. Combining one of those speech options with a final
`--notify-only` is an error rather than silently discarding the speech setting.

## Message input

One or more positional arguments are joined with spaces. With no positional
message, non-terminal standard input is read in full, preserving embedded
newlines. Use `--` before a message that begins with a hyphen.

An empty message is an error; a whitespace-only message is preserved. List
actions do not accept a message, and only one list action may be used at a time.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-p`, `--say` | Display the notification and speak the message |
| `-P`, `--say-only` | Speak the message without displaying a notification |
| `--notify-only` | Disable speech, including speech enabled by `NOTIFY_SAY` |
| `-t TITLE`, `--title TITLE` | Set the title (default: `Notification`) |
| `-s SUBTITLE`, `--subtitle SUBTITLE` | Add a subtitle |
| `-S SOUND`, `--sound SOUND` | Set the notification sound (default: `Glass`) |
| `-n`, `--no-sound` | Suppress the notification sound |
| `-l`, `--list-sounds` | List available notification sounds and exit |
| `-v VOICE`, `--voice VOICE` | Select an installed macOS voice |
| `-r WPM`, `--rate WPM` | Set a positive integer speech rate in words per minute |
| `--say-text TEXT` | Speak different text from the displayed message |
| `-b`, `--background` | Start `say` asynchronously |
| `-L`, `--list-voices` | List installed voices and locales, then exit |
| `-h`, `--help` | Show command help and exit |

`--no-sound` takes precedence over `--sound` and `NOTIFY_SOUND`. Sound
discovery checks the system, local, and current user's macOS Sounds directories.
In background mode, `notify` can report whether `say` started but cannot report
whether the asynchronous speech later completed successfully.

### Environment variables

| Variable | Description |
|---|---|
| `NOTIFY_TITLE` | Default notification title |
| `NOTIFY_SOUND` | Default notification sound |
| `NOTIFY_SAY` | Enable speech when set to `1`, `true`, `yes`, or `on` (case-insensitive for those spellings) |
| `NOTIFY_VOICE` | Default voice when speech is enabled |
| `NOTIFY_RATE` | Default speech rate when speech is enabled |
| `NO_COLOR` | Disable colored diagnostics when non-empty |
| `CLICOLOR_FORCE` | Force colored diagnostics when non-empty and `NO_COLOR` is unset |

Command-line options take precedence over environment defaults.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | No notification sounds were found |
| `2` | Invalid arguments or a missing message |
| `3` | A required macOS tool (`osascript` or `say`) is unavailable |

Otherwise, `notify` returns the status of a failed `osascript` or foreground
`say` process. If both outputs fail, the notification status takes precedence,
although speech is still attempted.

### Dependencies

- Bash 3.2 or newer
- macOS `osascript` when notification output is selected
- macOS `say` when speech output or voice discovery is selected

Notification Center attributes alerts to Script Editor, the `osascript` host
application. Notification duration is controlled by macOS under System
Settings > Notifications > Script Editor.
