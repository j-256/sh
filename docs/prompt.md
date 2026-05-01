# prompt

Interactive prompt with default value and placeholder -- for shell scripts that need to ask the user a question and get back a clean answer in a variable.

Unlike plain `read`, this gives you a gray placeholder hint that disappears when the user starts typing, backspace that works the way you'd expect, and sane Ctrl-C behavior that doesn't leave your terminal broken. The result (or default, if they just press Enter) lands directly in a variable you specify.

**Must be sourced, not executed.** The whole point is to set a variable in *your* shell, which only works via sourcing (`. prompt ...`).

## Quick start

```bash
. prompt USERNAME "What is your username? " "admin"
echo "Hello, $USERNAME"
```

If the user types `alice` and presses Enter, `$USERNAME` becomes `alice`. If they just press Enter without typing, `$USERNAME` becomes `admin`.

## Common examples

**Prompt with a default, no placeholder override:**

```bash
. prompt HOST "Enter hostname: " "localhost"
curl "https://$HOST/api/status"
```

The default `localhost` appears as a gray placeholder. User can type to replace it, or press Enter to accept it.

**Prompt with a custom placeholder that includes the default:**

```bash
. prompt BRANCH "Branch name: " "main" "e.g. feature/foo (default: %DEFAULT%)"
git checkout "$BRANCH"
```

The placeholder text `e.g. feature/foo (default: main)` appears in gray. `%DEFAULT%` is replaced with the actual default value (`main`).

**Prompt with no default (required input):**

```bash
. prompt API_KEY "Paste your API key: "
if [ -z "$API_KEY" ]; then
    echo "API key is required" >&2
    exit 1
fi
```

If the user presses Enter without typing, `$API_KEY` becomes empty. Your script decides whether that's acceptable.

**Yes/no confirmation with default:**

```bash
. prompt CONFIRM "Continue with deployment? [Y/n] " "Y"
case "$CONFIRM" in
    [Yy]*) echo "Deploying..." ;;
    *) echo "Aborted." ; exit 0 ;;
esac
```

**Reading in a non-interactive context** (piped input or redirected stdin):

```bash
printf 'my-value\n' | . prompt RESULT "Enter result: " "fallback"
echo "Got: $RESULT"
```

When stdin isn't a terminal, `prompt` prints the prompt text (no placeholder) and reads a line. The default still applies if input is empty.

**In a script that asks multiple questions:**

```bash
#!/bin/bash
. prompt NAME "Your name: " "Anonymous"
. prompt EMAIL "Your email: " "user@example.com"
. prompt ROLE "Your role: " "developer" "e.g. developer, designer, manager"

echo "Profile created:"
echo "  Name:  $NAME"
echo "  Email: $EMAIL"
echo "  Role:  $ROLE"
```

## Must be sourced

Executing `prompt` directly produces an error:

```
$ prompt VAR "Enter something: "
This script must be sourced to work correctly.
```

This is by design. The script needs to set a variable in *your* shell, which is impossible from a subprocess. Always invoke it via sourcing:

```bash
. prompt VAR "Enter something: " "default"
```

or with the `source` keyword (equivalent):

```bash
source prompt VAR "Enter something: " "default"
```

## Raw-mode editing

When stdin is a terminal (interactive use), `prompt` switches to raw mode for character-at-a-time input. This gives you:

- **Backspace / DEL work**: deletes the last character you typed
- **Placeholder appears in gray**: shown after the prompt text, disappears on the first keypress
- **ESC sequences filtered**: arrow keys and other escape codes are silently ignored (no garbage characters)

The placeholder is purely cosmetic -- it's not part of the input buffer. When the user starts typing, it vanishes and is replaced by their actual input.

## Ctrl-C / signal safety

During the prompt, SIGINT and SIGTERM are ignored. This prevents a common failure mode: if you press Ctrl-C while the terminal is in raw mode and the signal reaches the outer shell, readline's cleanup path can restore the wrong terminal state, leaving your shell unable to echo typed characters.

Trade-off: **Ctrl-C during a prompt does nothing.** To dismiss the prompt, press Enter (which accepts the default, if one was provided). Once the prompt finishes, normal signal handling resumes.

## Non-TTY fallback

When stdin is not a terminal (piped input, redirected from a file, or running in a CI environment), `prompt` skips raw mode entirely:

1. Prints the prompt text to stdout (no placeholder)
2. Does a plain `read -r` to grab a line
3. Uses the default if input is empty

This means scripts using `prompt` stay usable in automated contexts:

```bash
printf 'automated-value\n' | ./my-script.sh
```

If your script redirects stdin from `/dev/null` and the prompt hits EOF, the default is used.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `variable` | Shell variable name to store the result (required) |
| `prompt` | Text displayed before input (optional, e.g. `"Name: "`) |
| `default` | Value used when user presses Enter without typing (optional) |
| `placeholder` | Gray hint text shown in place of default; `%DEFAULT%` is replaced with the actual default value. If omitted, the default itself is used as the placeholder (optional) |
| `-h, --help` | Show help message |

### Positional arguments

Arguments are positional, in this order:

```bash
. prompt <variable> [prompt] [default] [placeholder]
```

- If only `variable` is given, you get a silent prompt with no text and no default.
- If `prompt` is given but `default` is omitted, user must provide input (pressing Enter yields an empty string).
- If `placeholder` is omitted, the `default` value is shown as the placeholder.
- If `placeholder` is given, any `%DEFAULT%` inside it is replaced with the `default` value.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (user provided input or default was used) |
| 2 | Usage error (script was executed rather than sourced) |

### Warnings

- **Variable names must be valid shell identifiers**: letters, digits, underscores. No hyphens, no spaces. If you pass an invalid name (e.g. `my-var`), the `eval` will fail with a syntax error.
- **Overwrites existing variables**: if `$MYVAR` already exists, sourcing `prompt MYVAR ...` replaces its value.
- **No input history**: unlike readline-based prompts, raw mode doesn't provide up-arrow recall.
- **Lone ESC key blocks briefly**: pressing Escape waits for two more bytes (expecting a CSI sequence). Not a natural gesture in a text prompt, but worth knowing if you accidentally hit it.
- **Requires bash 3.2+**: uses `read -n` and `${var:?}` syntax.
