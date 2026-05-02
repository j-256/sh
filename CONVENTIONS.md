# Shell Script Conventions

Standards for scripts in this repository.

## File Structure

```bash
#!/bin/bash
# script-name - Short description of what the script does
#
# Usage:
#   script-name [options] <required-arg>
#
# Options:
#   -v, --verbose  Enable verbose output
#   -h, --help     Show help message

_script_name() {
    local SCRIPT_NAME; SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

    _show_help() { ... }
    _error() { echo "[ERR][$SCRIPT_NAME] $*" >&2; }

    # --- cleanup trap (see below) ---

    # --- argument parsing, main logic ---
}

# --- source/execute exit handler (see below) ---
```

### Naming

- **Filename**: lowercase, hyphen-separated, no `.sh` extension (e.g. `find-zone-by-name`)
- **Wrapper function**: filename with hyphens replaced by underscores, prefixed with `_` (e.g. `_find_zone_by_name`)
- **Inner functions**: prefixed with `_` (e.g. `_show_help`, `_error`)

### Shebang

`#!/bin/bash` -- not `#!/usr/bin/env bash`. Target bash 3.2 compatibility (macOS system bash) unless a feature requires newer.

### Header Comment

A plain comment block immediately after the shebang. Includes the script name, a short description, usage, and options. This duplicates `--help` output but serves as quick reference when reading source.

## --help

Every script supports `-h` and `--help`. The help function uses raw ANSI SGR escapes (`\033[4m`/`\033[24m`) for underlined parameter placeholders, guarded by `[ -t 1 ]` (only when stdout is a terminal):

```bash
_show_help() {
    local s; [ -t 1 ] && s=$'\033[4m'
    local r; [ -t 1 ] && r=$'\033[24m'
    echo "NAME"
    echo "  $SCRIPT_NAME - short description"
    echo "SYNOPSIS"
    echo "  $SCRIPT_NAME [${s}options${r}] <${s}arg${r}>"
    echo "DESCRIPTION"
    echo "  What it does and why you'd use it."
    echo "OPTIONS"
    echo "  -v, --verbose  Enable verbose output"
    echo "  -h, --help     Show this help message"
    echo "DEPENDENCIES"
    echo "  jq, curl"
}
```

Sections (use what's relevant): NAME, SYNOPSIS, DESCRIPTION, OPTIONS, ENVIRONMENT, DEPENDENCIES, EXAMPLES, EXIT STATUS, SEE ALSO, CAVEATS.

### Use `$SCRIPT_NAME`, not the literal filename

Every user-visible mention of the script's own name -- help text (NAME, SYNOPSIS, EXAMPLES), error-message prefixes, "run `foo -h` for usage" hints -- must use `$SCRIPT_NAME` rather than the hardcoded filename. `$SCRIPT_NAME` is derived via `basename "${BASH_SOURCE[0]}"`, so it tracks the actual invocation path: if someone renames or symlinks the script, the help and errors stay truthful.

The only acceptable hardcoded occurrences of the script name are:
- The header comment block at the top of the file (plain comment, no bash expansion)
- The wrapper function name and its `__rc` variable (e.g. `_script_name`, `__script_name_rc`)
- Content that is genuinely filename-like (e.g. a temp-file prefix or log-file name the script produces)

Heredocs: prefer unquoted delimiter (`<<EOF`) so `$SCRIPT_NAME` expands. Quoted-delimiter (`<<'EOF'`) suppresses all expansion and forces hardcoding -- only use it when the heredoc body itself must contain literal `$`/`` ` `` characters that would otherwise be interpreted.

Edge case: `basename "${BASH_SOURCE[0]}"` resolves to the file the function was *defined* in. For a standalone script, that's the script's filename (correct). But a function pasted into `~/.bash_profile` will identify itself as `.bash_profile` in help and error output, which is wrong. If a snippet is meant to be sourced into a dotfile, hardcode `local SCRIPT_NAME="<func_name>"` in that copy.

Pipe/procsub invocation is another edge case with no real filename. Four shapes, all of which scripts need to survive:

- `curl -s https://toolio.sh/foo | bash` — stdin pipe. `${BASH_SOURCE[0]}` is the interpreter name (`bash`) inside the function and empty at top level.
- `bash <(curl -s https://toolio.sh/foo)` — process substitution, executed. `${BASH_SOURCE[0]}` is `/dev/fd/N` (basename: a digit).
- `. <(curl -s https://toolio.sh/foo)` — process substitution, sourced. Same `/dev/fd/N` shape.
- `cat foo | bash -c '. /dev/stdin'` — source via `/dev/stdin`. `${BASH_SOURCE[0]}` is `/dev/stdin` (basename: `stdin`).

There's no runtime signal to recover the original name from in any of these, so scripts hardcode a fallback. The fallback is two-stage: first wipe `SCRIPT_NAME` if the source path is a `/dev/*` or `/proc/*` pseudo-file (procsub, `/dev/stdin`), then apply the interpreter-name/empty-string fallback (stdin-pipe):

```bash
_foo() {
    local SCRIPT_NAME; SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    case "${BASH_SOURCE[0]}" in /dev/*|/proc/*) SCRIPT_NAME="" ;; esac
    case "$SCRIPT_NAME" in ""|bash|sh|zsh|dash) SCRIPT_NAME="foo" ;; esac
    ...
}
```

The path-based pre-check is deliberate: matching on the full path (`/dev/*`) rather than the basename (which could be `63`, `stdin`, etc.) avoids fragile globs that could misfire on legitimate filenames starting with a digit or literally named `stdin`. The post-basename case only handles the stdin-pipe shape, where basename is `bash` or empty. Real-file invocations pass through both cases untouched, so rename/symlink tracking still works. The canonical name is the one non-user-visible place besides the header comment where the literal filename appears.

## Cleanup Trap

Inner functions are cleaned up via a RETURN trap using the `__unset()` pattern. This ensures cleanup runs even on early returns:

```bash
__unset() {
    unset -f __unset _show_help _error _other_func
}
trap '__unset || echo "'"$SCRIPT_NAME"' trap failed!" >&2; trap - RETURN' RETURN
```

- `__unset` must unset itself plus all inner functions
- The trap preserves any pre-existing RETURN trap (relevant when sourced)
- `'"$SCRIPT_NAME"'` embeds the value at definition time via quote-exit-expand-reenter
- Place after inner function definitions, before main logic

## Source/Execute Exit Handler

Every script ends with a block that handles both sourced and executed contexts:

```bash
_script_name "$@"
__script_name_rc=$?
unset -f _script_name
if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
    eval "unset __script_name_rc; return $__script_name_rc"
fi
eval "unset __script_name_rc; exit $__script_name_rc"
```

This ensures:
1. The wrapper function is unset after running (no namespace pollution)
2. When sourced (`. script`), returns the correct exit code without killing the caller's shell
3. When executed (`./script`), exits with the correct code
4. When piped into `bash` via stdin (`curl ... | bash`), `${BASH_SOURCE[0]}` is empty at top level -- without the `-n` guard, `"" != "bash"` evaluates true and the `return` fires at top level, emitting `return: can only \`return' from a function or sourced script`. The guard routes this case to `exit`.

## Variable Declarations

- **One variable per `local` statement**: `local a` then `local b`, never `local a b`
- **Separate declare and assign for command substitution** (SC2155): `local var; var="$(cmd)"` on one line, not `local var="$(cmd)"`. Arithmetic `$((...))` is fine to inline since it can't fail.
- **No `export` inside functions** unless the variable genuinely needs to be in the environment for child processes

## Style

- Single space before inline comments: `cmd # comment`
- No periods at end of comments
- `$(...)` for command substitution, not backticks
- `command -v` to check for executables, not `which`
- Prefer POSIX-compatible patterns where reasonable (scripts may be run by zsh)
- Quote variables in `[ ]` tests: `[ "$var" -eq 0 ]`, not `[ $var -eq 0 ]`
- Prefer `if ...; then ...; else ...; fi` to `A && B || C` (SC2015): the chained form silently runs `C` if `B` fails, not only when `A` fails. The two are equivalent only when `B` can't fail, which is usually not worth relying on -- `echo`/`true` are fine but user-defined functions and external commands aren't.

## Error Messages

All diagnostic output follows a single canonical shape:

```
[ERR][$SCRIPT_NAME] message
[WRN][$SCRIPT_NAME] message
[INF][$SCRIPT_NAME] message
[DBG][$SCRIPT_NAME] message
```

All four helpers write to **stderr**. Program output stays on stdout.

The severity token leads so `grep '^\[ERR\]'` is greppable across the repo without per-script awareness. Severity is the most actionable field when scanning output, matching the ordering in `journalctl` and most log viewers. Three-letter tokens also line up when levels mix, producing a tidy left column.

### Level tokens

- **ERR** -- something went wrong; the caller will get a non-zero exit
- **WRN** -- surprising condition worth surfacing; the script continues
- **INF** -- progress/status information
- **DBG** -- verbose diagnostic output gated by a script-specific env var (e.g. `DDNS_DEBUG`)

### Casing and punctuation

- Capitalize prose-led messages (`"Invalid argument"`, `"Missing value"`, `"Unknown option"`).
- Preserve literal casing for identifier-led messages (`"client_id is required"`, `"jq is required"`, `"$dir does not exist"`).
- No trailing period on single-sentence messages. Matches Unix tradition (`git`, `cargo`, `brew`, `ls`).
- Internal periods only where structurally required to separate sentences. The usage-hint pattern is the canonical case: `"... is required. Run \`$SCRIPT_NAME -h\` for usage"` -- the period closes the first sentence and the second has no trailing period. When a usage hint is appended, the message has exactly one internal period (between the two sentences) and no trailing period.

### Usage hint

Usage-class errors (missing arg, unknown option, bad flag value) append `. Run \`$SCRIPT_NAME -h\` for usage`. Runtime errors (network failed, file not found) and dependency errors (`jq is required`) do **not** -- usage isn't the issue.

```bash
_error "Must provide a domain name. Run \`$SCRIPT_NAME -h\` for usage"   # usage error
_error "Failed to get device's IP"                                      # runtime error
_error "jq is required"                                                 # dep error
```

### Helper presence

- `_error` is required in every script.
- `_warn`, `_info`, `_debug` are defined only when the script calls them. Bash errors loudly at the call site if a caller uses an undefined helper.
- `__unset` lists exactly the helpers the script defines.

### Default helper block (plain)

```bash
_error() { echo "[ERR][$SCRIPT_NAME] $*" >&2; }
_warn()  { echo "[WRN][$SCRIPT_NAME] $*" >&2; }
_info()  { echo "[INF][$SCRIPT_NAME] $*" >&2; }
_debug() { echo "[DBG][$SCRIPT_NAME] $*" >&2; }
```

This is the shape for every script unless it has a specific need to disambiguate its own diagnostic output from external command output.

### Colored variant

A small number of scripts drive `curl`, `dig`, `openssl`, or spawn other tools whose output interleaves with theirs. These may use ANSI color to make diagnostic output visually distinct, guarded by a TTY check and respecting `NO_COLOR`:

```bash
_color() { [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && printf '%s' "$1"; }
_error() { printf '%s[ERR][%s] %s%s\n' "$(_color $'\033[31m')" "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
_warn()  { printf '%s[WRN][%s] %s%s\n' "$(_color $'\033[33m')" "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
_info()  { printf '%s[INF][%s] %s%s\n' "$(_color $'\033[2m')"  "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
_debug() { printf '%s[DBG][%s] %s%s\n' "$(_color $'\033[36m')" "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
```

Palette: `[ERR]` red (`\033[31m`), `[WRN]` yellow (`\033[33m`), `[INF]` dim (`\033[2m`), `[DBG]` cyan (`\033[36m`). Palette is color-only -- no `\033[1m` (bold) or other weight changes. Mechanism: raw ANSI escapes, not `tput`. TTY guard uses `[ -t 2 ]` since helpers write to stderr. `NO_COLOR` respected per https://no-color.org/. `__unset` must include `_color`.

Default to the plain variant. Only reach for the colored variant when output disambiguation genuinely matters.

## Dependencies

When a script requires external tools, check for them early and fail with a clear message:

```bash
if ! command -v jq >/dev/null 2>&1; then
    _error "jq is required"
    return 3
fi
```

### What to document in `--help`

List non-universal tools in the `DEPENDENCIES` section of `--help` and the `.md`. **Do not** list near-universal POSIX utilities that are assumed present by the `#!/bin/bash` shebang: `sed`, `grep`, `tr`, `awk`, `tail`, `head`, `cut`, `find`, `printf`, `basename`, `dirname`, `cat`, `echo`, `mv`, `cp`, `rm`, `mkdir`, `rmdir`, `test`/`[`, `date`, `sort`, `uniq`. These are shebang-implied.

Non-universal tools that **do** warrant listing: `jq`, `curl`, `openssl`, `dig`, `bc`, `ipcalc`, `fswatch`, `osascript`, `pbpaste`, `stty`, `defaults`, `brew`, `chsh`, `git`, `sudo`, `base64`, and anything platform-specific.

## Commit Style

- **Subject format:** `Update <script> - <short description>` (leading verb "Update", no final period). For truly new additions, `Add <script> - <short description>`.
- **Body:** bulleted, one bullet per concrete change. Focus on the "what" -- the rationale can go in the spec or commit message body paragraph if needed, but subject + bullets is usually enough.
- **Scope:** one commit per script. The commit covers the script itself plus `docs/<name>.md` and `tests/<name>.test.sh` if those change. Cross-cutting edits (`CONVENTIONS.md`, `test-helpers.sh`, `test-runner.sh`) get their own commits.
- **Exceptions:** small typo/formatting sweeps across many files may land as one commit when splitting would add no clarity.
