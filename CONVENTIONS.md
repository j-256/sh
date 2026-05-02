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
    _error() { echo "[$SCRIPT_NAME] ERROR: $*" >&2; }

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

Every script supports `-h` and `--help`. The help function uses `tput smul`/`rmul` for underlined parameter placeholders, guarded by `[ -t 1 ]` (only when stdout is a terminal):

```bash
_show_help() {
    local s; [ -t 1 ] && s="$(tput smul 2>/dev/null || echo '')"
    local r; [ -t 1 ] && r="$(tput rmul 2>/dev/null || echo '')"
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

Standardize the shape of argument/usage errors so users always know where to get help:

```bash
_error() { echo "[$SCRIPT_NAME] ERROR: $*" >&2; }
_error "client_id is required. Run \`$SCRIPT_NAME -h\` for usage."
```

Rendered: `[script-name] ERROR: client_id is required. Run \`script-name -h\` for usage.`

The "Run ... for usage" suffix is for argument/validation errors where the user needs to learn the interface. It is not required for runtime errors (e.g. "network request failed", "file not found") where usage isn't the issue.

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

Non-universal tools that **do** warrant listing: `jq`, `curl`, `openssl`, `dig`, `bc`, `ipcalc`, `fswatch`, `osascript`, `pbpaste`, `tput`, `stty`, `defaults`, `brew`, `chsh`, `git`, `sudo`, `base64`, and anything platform-specific.
