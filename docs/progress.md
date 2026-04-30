# progress

Render a single-line progress bar with percentage completion.

Designed for shell loops or long-running scripts. Instead of a one-liner `printf`, you get proper output stream management (defaults to stderr to keep stdout clean), automatic terminal width detection to prevent line wrapping, and smart behavior in both TTY and non-TTY contexts.

## Quick start

```bash
for i in {1..10}; do
    progress "$i" 10
    sleep 0.2
done
```

In a TTY, this renders an updating progress bar on stderr:
```
[#############################             ]  50%
```

At completion, a newline is printed so the bar doesn't get overwritten by the next command:
```
[##################################################] 100%
```

## Common examples

**Track processing of a file list:**

```bash
files=(*.txt)
total="${#files[@]}"
current=0

for file in "${files[@]}"; do
    current=$((current + 1))
    progress "$current" "$total"
    # process "$file"
done
```

**Use a custom width and characters:**

```bash
for i in {1..50}; do
    progress --width 30 --progress-char '=' --remaining-char '.' "$i" 50
    sleep 0.05
done
```

Renders `[======================........] 100%` at completion.

**Force to stdout** (e.g. when stderr is redirected elsewhere):

```bash
for i in {1..100}; do
    progress --stdout "$i" 100
    # do work
done
```

**Redirect to a log file** -- in non-TTY contexts, only the 100% bar is written:

```bash
for i in {1..100}; do
    progress "$i" 100
    # do work
done 2>> progress.log
```

The log file contains just:
```
[##################################################] 100%
```

## Output behavior

`progress` is smart about where and when it writes:

- **Default:** Outputs to stderr so stdout stays clean for pipelines or command substitution
- **TTY mode:** Uses `\r` to redraw the bar in place at each update
- **Non-TTY mode:** Only emits output at 100% completion, preventing log spam

You can force output to stdout with `--stdout` or explicitly to stderr with `--stderr`.

## Terminal width awareness

The bar width is clamped to fit the terminal so the line never wraps and breaks the `\r` redraw behavior. The format is:

```
[bar] percentage
```

Fixed overhead is 8 characters (`[`, `] `, and `%3d%%`), so a 50-character bar setting on an 80-column terminal will be honored, but on a 40-column terminal it will be reduced to 32 characters.

Width detection uses `stty`, then `tput`, then `$COLUMNS`, falling back to 80.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-w, --width N` | Width of the progress bar itself (default: 50), automatically clamped to fit terminal |
| `-p, --progress-char CHAR` | Character for the completed portion (default: `#`) |
| `-r, --remaining-char CHAR` | Character for the remaining portion (default: ` `) |
| `--stderr` | Force output to stderr |
| `--stdout` | Force output to stdout |
| `-h, --help` | Show help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (missing arguments, invalid number, width <= 0) |

### Dependencies

- `stty` (optional, for terminal width detection)
- `tput` (optional, for terminal width detection)

### Behavior

- `CURRENT` is clamped to the range `[0, MAX]` -- negative values become 0, values above MAX become MAX
- `MAX` must be a positive integer (enforced)
- Width must be a positive integer (enforced)
- In TTY mode, a newline is only printed when `CURRENT == MAX`
- In non-TTY mode, output is suppressed until `CURRENT == MAX`
