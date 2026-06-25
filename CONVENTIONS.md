# Shell Script Conventions

Standards for scripts in this repository.

**See also:** [`DOCS.md`](DOCS.md) for how to write a `<script>.md` doc; [`TESTING.md`](TESTING.md) for how to write a `<script>.test.sh` test file.

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

_script_name() (
    local SCRIPT_NAME; SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

    _show_help() { ... }
    _error() { echo "[ERR][$SCRIPT_NAME] $*" >&2; }

    # --- argument parsing, main logic ---
)

# --- source/execute exit handler (see below) ---
```

The wrapper body is `( ... )`, not `{ ... }`. A subshell-bodied function runs in its own process: helper functions, `local` vars, `cd`, `set` flags, traps -- everything dies when the function returns. Nothing leaks into the caller's shell. `return N` from inside the subshell still propagates the exit status to the caller, so the source/execute exit handler at the bottom of the file works unchanged. See [Source-only scripts](#source-only-scripts) for the exception: scripts that need to mutate the caller's shell can't use a subshell body.

### Naming

- **Filename**: lowercase, hyphen-separated, no `.sh` extension (e.g. `find-zone-by-name`)
- **Wrapper function**: filename with hyphens replaced by underscores, prefixed with `_` (e.g. `_find_zone_by_name`)
- **Inner functions**: prefixed with `_` (e.g. `_show_help`, `_error`)

### Source-only scripts

A script is *source-only* when it manipulates the caller's shell directly -- reading caller-shell variables (like `dbg`) or setting them (like `prompt`). These scripts must be sourced rather than executed; an executed copy runs in a subprocess and can't touch the caller's variables.

Source-only scripts use a `{ ... }` wrapper body instead of the standard `( ... )`, because a subshell-bodied function would isolate the caller's shell from its own work -- the whole point of being source-only is to operate on caller state. With a brace body, helpers, `local` vars, and traps live in the caller's shell during the call, which means they need explicit cleanup (see [Cleanup Trap](#cleanup-trap)).

Source-only scripts also have a stricter naming rule than executable scripts: every inner function (including the wrapper) and every top-level variable is prefixed with `__<script>__` rather than a single leading `_`. The reason is namespace collision -- when a script is sourced into a brace-bodied wrapper, its function and variable definitions live in the caller's shell during the call. Common helper names like `_show_help`, `_error`, or `__unset` could clobber the caller's pre-existing identifiers; worse, the cleanup trap's `unset -f` would then delete them outright on return. The `__<script>__` prefix makes accidental collisions essentially impossible.

```bash
__prompt__main() {
    local __prompt__name; __prompt__name="$(basename "${BASH_SOURCE[0]}")"

    __prompt__show_help() { ... }
    __prompt__error() { ... }

    __prompt__unset() {
        unset -f __prompt__unset __prompt__show_help __prompt__error
    }
    ...
}

__prompt__main "$@"
__prompt__rc=$?
unset -f __prompt__main
```

The rule covers:

- **The wrapper function**: `__prompt__main` rather than the executable-script default `_prompt`.
- **Inner functions**: `__prompt__show_help`, `__prompt__error`, `__prompt__unset`.
- **Top-level variables** outside the wrapper (the executed-vs-sourced rejection block at the top of the file): `__prompt__basename`, `__prompt__name`. These live in the caller's shell during the script's execution, so they need the prefix as much as the functions do.
- **The `__<script>__rc` variable** in the source/execute exit handler.

#### Locals inside functions

Locals are scoped to their function and are normally safe with any name -- they can't leak into the caller's shell. The exception: when a function reads a caller-shell variable by *name* (via `eval`, `declare -p`, `printf -v`, or `read`), an unprefixed local can shadow the very variable the caller asked the function to inspect or set. The classic case is `dbg foo`: if `__dbg__main` had a `local foo`, the caller's `$foo` would be invisible. Same hazard applies to `prompt _input`: a `local _input` inside `__prompt__main` would consume the assignment instead of writing to the caller's `_input`.

The rule is per-function, not per-script: any function whose contract includes "operate on a caller-supplied variable name" must prefix all of its locals with `__<script>__`. Other helpers in the same script (a `__prompt__show_help` whose locals never see a caller-supplied name) can use plain local names without the prefix.

A simple test: does the function take a variable name as an argument and resolve it via `eval` / `declare -p` / `printf -v` / `read`? If yes, prefix all its locals. If no, plain local names are fine.

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

### Periods in help text

Help-text *fragments* -- short single-line entries in OPTIONS, EXIT STATUS, ENVIRONMENT, DEPENDENCIES, SEE ALSO -- drop trailing periods, matching the no-trailing-period rule for error messages and code comments. These read as labels, not sentences.

```
OPTIONS
  -v, --verbose      Enable verbose output
  -h, --help         Show this help message
EXIT STATUS
  0  Success
  1  Runtime failure (network, filesystem, external command failed)
```

Help-text *prose* -- multi-line paragraphs in DESCRIPTION, CAVEATS, and similar narrative sections -- keeps internal and trailing periods. These read as English sentences and the punctuation is load-bearing for parseability.

```
DESCRIPTION
  Updates Cloudflare DNS to use the current machine's outbound IP address.
  Deletes all existing A records for the domain and creates a new one before
  the change is applied. Run periodically from the host to achieve basic
  Dynamic DNS capabilities.
```

A single-sentence DESCRIPTION is still prose -- keep the trailing period. The fragment-vs-prose distinction is "is this a label or a sentence", not "is this one line or many".

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

Source-only scripts use a `{ ... }` wrapper body, so any inner functions and `local` vars live in the caller's shell during the call. A RETURN trap calls an `__unset` helper to remove them when the wrapper returns, so the caller's namespace is left clean. (Executable scripts use a `( ... )` wrapper body and don't need this -- the subshell evaporates everything on return.)

```bash
__prompt__unset() {
    unset -f __prompt__unset __prompt__show_help __prompt__error _other_func
}
trap '__prompt__unset || echo "'"$__prompt__name"' trap failed!" >&2; trap - RETURN' RETURN
```

- `__<script>__unset` must unset itself plus all inner functions
- `'"$__prompt__name"'` embeds the value at definition time via quote-exit-expand-reenter
- Place after inner function definitions, before main logic
- The trailing `trap - RETURN` is load-bearing: it empties the trap slot before the function returns, which keeps the caller's pre-existing RETURN trap intact. See below.

### Why `trap - RETURN` at the end of the handler

Bash's RETURN trap has an asymmetric scoping model:

- **Reads are frame-local.** Inside a callee, `trap -p RETURN` returns empty even when the caller has a trap installed -- the caller's trap is held in the parent frame, invisible from the callee. So save-and-restore is impossible: there is nothing to read.
- **Writes propagate on return.** When the callee returns, whatever text is in the RETURN slot at that moment becomes the trap for the parent frame, overwriting whatever the caller had set.

The consequence: a callee that installs a RETURN trap and leaves it in place silently overwrites the caller's trap on return. The fix is not to save and restore (which is impossible without functrace), but to clear our own slot before returning. With the slot empty at the moment of return, the parent frame is left exactly as it was -- the caller's trap survives because bash had it stashed in the parent frame the whole time.

The pattern: `__<script>__unset` does the work (clean up our helpers so they don't pollute the caller's namespace), and `trap - RETURN` is the politeness step that keeps us from clobbering the caller on the way out.

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
- **Separate declare and assign for command substitution** (SC2155): `local var; var="$(cmd)"` on one line, not `local var="$(cmd)"`. The split is required *only* when the right-hand side is a command substitution `$(...)`, because `local` masks the command's exit status. Everything else inlines: `local n=5` (literal), `local f="$1"` (positional), `local p="$dir/$name"` (parameter expansion), `local sum=$(( a + b ))` (arithmetic) -- none has an exit status to mask, so splitting them adds noise without benefit. Split for `$(...)`; inline the rest.
- **Configuration constants get UPPERCASE names**: top-of-function values that are set once at declaration and act as fixed inputs to the function -- URLs, base paths, magic numbers, default values, header names, TTLs -- use UPPERCASE identifiers. The casing is the signal: readers should treat UPPERCASE as "don't reassign."
  - **Signal it by name, not `local -r`:** don't mark these readonly. SC2155 already requires splitting declare and assign for command substitutions, but `local -r foo` then makes the second-line assignment error -- so `local -r` needs an "unless it's command-substituted" carve-out that a naming convention doesn't. UPPERCASE alone has no carve-outs and works for string literals, parameter expansions, arithmetic, and command substitution alike.
- **No `export` inside functions** unless the variable genuinely needs to be in the environment for child processes

## Style

- Single space before inline comments: `cmd # comment`
- No trailing `.` or `!` on comments, even on multi-sentence ones. Same rule as error messages.
- No trailing `:` on comments that sit directly above code -- the colon adds no signal there, since "introduces follow-on output" is trivially true.
- Trailing `:` IS load-bearing on comments that introduce more *comments*: header sections (`# Usage:`, `# Options:`, `# Dependencies:`, `# Environment:`, `# Examples:`, `# References:`), in-block list intros (`# Validate bracket syntax early:`, `# Accepts:`, `# Outputs:`, `# update BOTH:`), and any line whose subsequent comment lines are an indented list/sample/URL block. Keep the colon -- without it the reader can't see where the introducing sentence ends and the list begins.
- `$(...)` for command substitution, not backticks
- `command -v` to check for executables, not `which`
- Prefer POSIX-compatible patterns where reasonable (scripts may be run by zsh)
- Quote variables in `[ ]` tests: `[ "$var" -eq 0 ]`, not `[ $var -eq 0 ]`
- Prefer `if ...; then ...; else ...; fi` to `A && B || C` (SC2015): the chained form silently runs `C` if `B` fails, not only when `A` fails. The two are equivalent only when `B` can't fail, which is usually not worth relying on -- `echo`/`true` are fine but user-defined functions and external commands aren't.
- Prefer `cmd || :` over `cmd || true` for "ignore failure" patterns. `:` is the POSIX null utility -- intentional, minimal, and reads as "no-op" at a glance. `|| true` works but relies on reading `true` as a no-op keyword rather than a command; `|| :` makes the intent unambiguous.
- Annotate every `# shellcheck disable=SCxxxx` with **both** the rule's title in quotes **and** a rationale, in the form `# shellcheck disable=SCxxxx # "<title>" -- <rationale>`. Example: `# shellcheck disable=SC2086 # "Double quote to prevent globbing and word splitting." -- $tcp expands to +tcp or empty; the split is intentional`.
  - **Title:** verbatim whatever `shellcheck` prints for the flagged line -- copy it exactly, no paraphrasing and no trimming, even when the message includes a worked example (e.g. SC1003's `"Want to escape a single quote? echo 'This is how it'\''s done'."`). Quoting it exactly is the only deterministic rule -- there is no principled place to cut, and a verbatim title stays verifiable by re-running `shellcheck`. Inlining it also saves the reader a wiki lookup.
  - **Rationale:** required, not optional -- after the title, ` -- ` then a short explanation of *why this specific occurrence is correct* (what the flagged code actually does and why the warning doesn't apply here). The title says what the linter wants; the rationale says why you're overriding it. A disable with no rationale forces the next reader to re-derive the justification.
  - **Multiple codes:** for a combined disable like `SC2317,SC2329`, give each title in the same order, separated by ` / `, then the single shared rationale.

## Exit Codes

Usage `--help` should document exactly the codes the script uses, with short descriptions. The canonical meanings:

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Runtime failure (network, filesystem, external command failed) |
| `2` | Usage error (missing arg, unknown flag, bad flag value, precondition not met) |
| `3` | Dependency error (required tool not installed) |
| `4`+ | Script-specific; an error or a non-error result such as "no match" (document in `--help` EXIT STATUS section) |

Reserve `2` strictly for usage/precondition issues so callers can distinguish "the user invoked me wrong" from "something went wrong while running". Reserve `3` for missing external tools. Codes `4` and up are the script's own to define, documented in its `--help` EXIT STATUS section. They need not signal errors: a script whose job is to answer a question may return a nonzero code for a negative-but-correct result, the way `grep` and `diff` return `1` for "no match" and "files differ". `genpw` uses `4` for an empty charset and `5` for an invalid one; a predicate script might instead use `4` for the negative answer. Because the meaning of `4`+ is per-script, a caller reads it from that script's `--help`, not from this table.

Early-exit validation pattern:

```bash
# Usage validation (return 2)
if [ -z "$1" ]; then
    _error "Must provide an argument. Run \`$SCRIPT_NAME -h\` for usage"
    return 2
fi

# Dependency check (return 3)
if ! command -v jq >/dev/null 2>&1; then
    _error "jq is required"
    return 3
fi

# Runtime failure (return 1, later in the flow)
if ! result=$(do_the_thing); then
    _error "Failed to do the thing"
    return 1
fi
```

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

- Capitalize prose-led messages (`"Invalid argument"`, `"Missing value"`, `"Unknown argument"`).
- Preserve literal casing for identifier-led messages (`"client_id is required"`, `"jq is required"`, `"$dir does not exist"`).
- No trailing period or `!`, even on multi-sentence messages. Matches Unix tradition (`git`, `cargo`, `brew`, `ls`). A trailing `:` is fine when the message introduces follow-on output on the next line(s) -- the colon signals "see below" and is load-bearing, e.g. `_warn "$dir is not on your \$PATH. To fix, add this to your shell rc:"` followed by an `echo` of the command to paste.
- Internal periods only where structurally required to separate sentences. The usage-hint pattern is the canonical case: `"... is required. Run \`$SCRIPT_NAME -h\` for usage"` -- the period closes the first sentence and the second has no trailing period. When a usage hint is appended, the message has exactly one internal period (between the two sentences) and no trailing period.

**Prose-led vs identifier-led edge cases:**

- Required positional-arg names are identifier-led: `"selector is required"`, `"domain is required"` (not `"Selector is required"`).
- Command-name-led messages stay lowercase: `"git add failed. Restoring .git..."`, `"jq is required"`, `"mktemp failed"`.
- Variable-value-led messages preserve the value's case: `"$dir does not exist"`, `"$src: No such file"`.
- Proper nouns lead capitalized even when referring to an identifier: `"Chrome app not found at '$app'"`, `"DNS response empty"`.
- Flag names in mid-sentence keep their literal form: `"Invalid --platform '$platform' (valid: mac|win|linux)"`.

### Usage hint

Usage-class errors (missing arg, unknown option, bad flag value) append `. Run \`$SCRIPT_NAME -h\` for usage`. Runtime errors (network failed, file not found) and dependency errors (`jq is required`) do **not** -- usage isn't the issue.

```bash
_error "Must provide a domain name. Run \`$SCRIPT_NAME -h\` for usage"   # usage error
_error "Failed to get device's IP"                                      # runtime error
_error "jq is required"                                                 # dep error
```

### Canonical phrasings

Use these exact forms so error output stays consistent across the repo:

| Situation | Phrasing |
|-----------|----------|
| Unknown flag / catch-all `*)` branch | `"Unknown argument '$1'. Run \`$SCRIPT_NAME -h\` for usage"` |
| Bad flag value | `"Invalid --flag '$value' (valid: opt1\|opt2\|opt3). Run \`$SCRIPT_NAME -h\` for usage"` |
| Missing flag value | `"--flag requires a <type>. Run \`$SCRIPT_NAME -h\` for usage"` |
| Missing required positional arg (prose-led) | `"Must provide <thing>. Run \`$SCRIPT_NAME -h\` for usage"` |
| Missing required positional arg (identifier-led) | `"<identifier> is required. Run \`$SCRIPT_NAME -h\` for usage"` |
| Duplicated flag | `"Multiple <things> not allowed (already set to '$value'). Run \`$SCRIPT_NAME -h\` for usage"` |
| Dependency missing | `"<tool> is required"` (no hint) |
| Runtime failure | `"Failed to <verb> <object>"` (no hint, no trailing period) |

Single-quote interpolated values (`'$1'`, `'$value'`) so empty strings and whitespace are visible. Use `$SCRIPT_NAME` in the hint backticks (not a hardcoded name).

### Helper presence

- `_error` is required in every script.
- `_warn`, `_info`, `_debug` are defined **only** when the script calls them. Do not define speculative helpers -- they become orphan code that future readers have to investigate. Bash errors loudly at the call site if a caller uses an undefined helper, so nothing is lost by omitting unused ones. (For source-only scripts, speculative helpers also bloat `__<script>__unset`'s `unset -f` list.)
- In source-only scripts, `__<script>__unset` lists exactly the helpers the script defines -- no more, no less.

**Helper placement:** define helpers inside the wrapper function, before the cleanup trap (source-only scripts) and before any logic that might call them. When dependency-checking is part of the flow (e.g. before arg parsing), place helpers first so dep-check error paths can use `_error`.

### Default helper block (plain)

```bash
_error() { echo "[ERR][$SCRIPT_NAME] $*" >&2; }
_warn()  { echo "[WRN][$SCRIPT_NAME] $*" >&2; }
_info()  { echo "[INF][$SCRIPT_NAME] $*" >&2; }
_debug() { echo "[DBG][$SCRIPT_NAME] $*" >&2; }
```

This is the shape for every script unless it has a specific need to disambiguate its own diagnostic output from external command output.

### Colored variant

A small number of scripts drive `curl`, `dig`, `openssl`, or spawn other tools whose output interleaves with theirs. These may use ANSI color to make diagnostic output visually distinct, guarded by a TTY check and respecting `NO_COLOR`. Two shapes, chosen by how much diagnostic output the script emits.

**Whole-line tint** -- the entire `[SEV][name] message` line takes the severity color. Simplest; the right default for scripts that emit only occasional diagnostics:

```bash
_color() { [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && printf '%s' "$1"; }
_error() { printf '%s[ERR][%s] %s%s\n' "$(_color $'\033[31m')" "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
_warn()  { printf '%s[WRN][%s] %s%s\n' "$(_color $'\033[33m')" "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
_info()  { printf '%s[INF][%s] %s%s\n' "$(_color $'\033[2m')"  "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
_debug() { printf '%s[DBG][%s] %s%s\n' "$(_color $'\033[36m')" "$SCRIPT_NAME" "$*" "$(_color $'\033[0m')" >&2; }
```

**Structured prefix** -- colors the prefix pieces distinctly (dim brackets, hued `SEV` token, cyan name) and leaves the message in the default fg, so the line structure reads at a glance and the message body can carry its own accent. It precomputes the prefixes once at function entry instead of forking two `$(_color ...)` subshells on every call, so it stays cheap when a script emits many lines -- the right shape for a trace-heavy `-v` mode that prints one `[INF]` line per record. This is what `spf` uses:

```bash
# Empty unless stderr is a TTY and NO_COLOR is unset, so pipes/redirects stay plain.
local C_BRK=""    # brackets: dim
local C_INF=""    # INF token: dim
local C_WRN=""    # WRN token: yellow
local C_ERR=""    # ERR token: red
local C_NAME=""   # script name: cyan
local C_SRC=""    # optional in-message accent (e.g. a trace's subject): green
local C_RST=""
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    C_BRK=$'\033[2m'
    C_INF=$'\033[2m'
    C_WRN=$'\033[33m'
    C_ERR=$'\033[31m'
    C_NAME=$'\033[36m'
    C_SRC=$'\033[32m'
    C_RST=$'\033[0m'
fi
local PFX_ERR="${C_BRK}[${C_ERR}ERR${C_BRK}][${C_NAME}${SCRIPT_NAME}${C_BRK}]${C_RST} "
local PFX_WRN="${C_BRK}[${C_WRN}WRN${C_BRK}][${C_NAME}${SCRIPT_NAME}${C_BRK}]${C_RST} "
local PFX_INF="${C_BRK}[${C_INF}INF${C_BRK}][${C_NAME}${SCRIPT_NAME}${C_BRK}]${C_RST} "
_error() { printf '%s%s%s\n' "$PFX_ERR" "$*" "$C_RST" >&2; }
_warn()  { printf '%s%s%s\n' "$PFX_WRN" "$*" "$C_RST" >&2; }
_info()  { printf '%s%s%s\n' "$PFX_INF" "$*" "$C_RST" >&2; }
```

The trailing `$C_RST` closes any unclosed color the message itself carries, so a caller that ends a message in an accent (`_info "$C_SRC$host"`) can't bleed color onto the next line. It is empty when color is off, so plain output is byte-identical. This mirrors the whole-line form's trailing `$(_color $'\033[0m')`. A self-closing in-message accent (`"${C_SRC}${x}${C_RST}: tail"`) doesn't depend on it, but the trailing reset makes the helper safe regardless of how the caller colors the message.

The `C_SRC` accent is applied at the call site by wrapping the subject inside the message. The vars are empty when color is off, so the plain output is byte-identical:

```bash
_info "${C_SRC}${src}${C_RST}: $record"   # subject pops in green; the rest stays default fg
```

Palette: `[ERR]` red (`\033[31m`), `[WRN]` yellow (`\033[33m`), `[INF]` dim (`\033[2m`), `[DBG]` cyan (`\033[36m`); the structured prefix adds dim brackets (`\033[2m`), cyan name (`\033[36m`), and an optional green in-message accent (`\033[32m`). Palette is color-only -- no `\033[1m` (bold) or other weight changes. Mechanism: raw ANSI escapes, not `tput`. TTY guard uses `[ -t 2 ]` since helpers write to stderr. `NO_COLOR` respected per https://no-color.org/. Define only the helpers a script actually uses. Source-only scripts using the whole-line form must include `_color` in `__<script>__unset`; the structured form defines no helper function, so its `local` palette/prefix vars are auto-scoped with nothing to unset.

Default to the plain variant. Only reach for a colored variant when output disambiguation genuinely matters.

## Argument Parsing

Every script accepts three GNU-style input shapes, same as `curl`, `git`, and `grep`:

- Bundled short flags: `-sv` == `-s -v`
- Glued short-opt values: `-n5` == `-n 5`
- `=`-joined long-opt values: `--num=5` == `--num 5`

Scripts implement this via a preprocessor block that runs once before the parse loop, plus a `--foo=*)` arm next to every `-f|--foo)` arm that takes a value.

### Canonical short options

Reuse these letters with these meanings across scripts. New scripts that need one of these behaviors must use the listed letter; new scripts that pick a short option for a different purpose must avoid these letters.

| Short | Long | Meaning |
|-------|------|---------|
| `-h` | `--help` | Show help |
| `-v` | `--verbose` | Verbose output |
| `-q` | `--quiet` | Suppress non-error output |
| `-n` | `--dry-run` | Simulate, don't modify |
| `-f` | `--force` | Force/overwrite |
| `-d` | _(script-specific)_ | Reserved for script-specific use (data, duration, etc.) |

`-n` for dry-run follows `make -n`, `rsync -n`, `git push -n` (mnemonic: "no execute"). `-d` is deliberately script-specific -- several scripts already use it for `--data`, `--duration`, etc., so it is not reserved for dry-run.

Every short option must be paired with a long option unless the short is deliberately undocumented (rare -- prefer documenting and pairing). The long form is what shows up in scripts, docs, and error messages; the short is the typing shortcut.

### Preprocessor

Every script with short options defines `_expand_short_opts` inside the wrapper function and calls it immediately above the parse loop. The function body is identical across scripts; the call-site argument lists the letters that take a value (`""` if none).

```bash
_expand_short_opts() {
    # $1 = string of short-opt letters that take a value (e.g. "nXHd"); "" for flag-only scripts
    # $2..$N = "$@"
    # Populates _EXPANDED; caller does: set -- "${_EXPANDED[@]}"; unset _EXPANDED
    local value_opts="$1"; shift
    _EXPANDED=()
    local passthru=""
    local arg
    local rest
    local c
    for arg in "$@"; do
        if [ -n "$passthru" ]; then _EXPANDED+=("$arg"); continue; fi
        case "$arg" in
            --)          passthru=1; _EXPANDED+=("$arg") ;;
            --*|-|"")    _EXPANDED+=("$arg") ;;
            -[a-zA-Z]?*)
                rest="${arg#-}"
                while [ -n "$rest" ]; do
                    c="${rest%"${rest#?}"}"; rest="${rest#?}"
                    _EXPANDED+=("-$c")
                    case "$value_opts" in *"$c"*)
                        [ -n "$rest" ] && _EXPANDED+=("$rest")
                        rest="" ;;
                    esac
                done ;;
            *)        _EXPANDED+=("$arg") ;;
        esac
    done
}

_expand_short_opts "nXHd" "$@"
set -- "${_EXPANDED[@]}"; unset _EXPANDED
```

The call-site argument lists every short-option letter in the script that takes a value -- `"nwsXHdA"` in `curl-timing`, `""` in `bak`. A missing letter causes `-n5` to silently split into `-n -5`.

Tokens starting with `-` followed by a digit (`-500G`, `-42`) pass through unchanged rather than expanding as clusters. This matches how `curl` and GNU tools treat negative-number arguments -- no short option name is a digit, so `-[digit]...` is safely reserved for negative-value passthrough.

In source-only scripts, `_expand_short_opts` is listed in `__<script>__unset` alongside the other inner functions.

### Long options with `=`

Every long option that takes a value has a sibling `--foo=*)` arm next to its `-f|--foo)` arm. Both arms guard against an empty value with the canonical missing-value phrasing from the Error Messages canon:

```bash
-n|--num)
    [ -n "${2-}" ] || { _error "--num requires a value. Run \`$SCRIPT_NAME -h\` for usage"; return 2; }
    num_requests="$2"; shift 2 ;;
--num=*)
    num_requests="${1#*=}"
    [ -n "$num_requests" ] || { _error "--num requires a value. Run \`$SCRIPT_NAME -h\` for usage"; return 2; }
    shift ;;
```

The `--num=*)` guard catches `--num=` (empty value after `=`), symmetric with how the `-n|--num)` arm catches a missing `$2`. Both paths emit the same canonical message.

Long flag options (no value) have no `--foo=*)` arm. The arm exists to extract a value (`${1#*=}`) and assign it; a flag has nothing to extract, so the arm would be dead weight in every parse loop. `--verbose=oops` falls through to `-*)` and errors with the canonical "Unknown argument" phrasing -- a reasonable result without the extra arm.

### Parse loop shape

Canonical structure, inside the wrapper function, after the helper definitions (and after the `__<script>__unset` trap, in source-only scripts) and before main logic:

```bash
_expand_short_opts "nXHd" "$@"
set -- "${_EXPANDED[@]}"; unset _EXPANDED

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) _show_help; return 0 ;;
        -v|--verbose) verbose=1; shift ;;

        -n|--num)
            [ -n "${2-}" ] || { _error "--num requires a value. Run \`$SCRIPT_NAME -h\` for usage"; return 2; }
            num_requests="$2"; shift 2 ;;
        --num=*)
            num_requests="${1#*=}"
            [ -n "$num_requests" ] || { _error "--num requires a value. Run \`$SCRIPT_NAME -h\` for usage"; return 2; }
            shift ;;

        --) shift; while [ $# -gt 0 ]; do args+=("$1"); shift; done ;;
        -*) _error "Unknown argument '$1'. Run \`$SCRIPT_NAME -h\` for usage"; return 2 ;;
        *)  args+=("$1"); shift ;;
    esac
done
```

### Positional/option ordering

Positionals and options may be freely interleaved. `bak file1 -v file2` is equivalent to `bak -v file1 file2`. The `*)` (positional) and option arms both `shift` and accumulate as they go, so ordering is a property of the parse-loop shape -- no extra code required. Use `--` to force the remainder as positional when a positional starts with `-`.

### Scope

Every long option is either a flag (no value) or requires a value -- never optional-value (`--color` defaulting when bare, taking a value only with `--color=always`). Exceptions are rare and called out per-script; see "Value-optional options" below for the recipe. Long options are matched exactly; abbreviations like `--ver` for `--verbose` are unknown arguments.

### Value-optional options

The Scope rule bans value-optional options by default because the shared preprocessor and the `--foo)`/`--foo=*)` arm pattern can't know per-option whether `$2` should be consumed -- they have to pick one rule and apply it uniformly. A script may opt in when (a) the value shape is narrow enough to be unambiguous against anything else that could follow (a narrow regex, a closed enum), and (b) the combined form is genuinely more ergonomic than a split `--watch --interval=5m`. The `-w|--watch [interval]` recipe below is the worked example.

Recipe:

1. Keep the short letter OUT of `_expand_short_opts`'s value-opts string. This preserves bundling (`-wF` == `-w -F`); the trade-off is that attached short (`-w5m`) stops working. Bundling is usually more valuable.

2. In the space-form arm, `shift` onto the candidate, sniff-test it, and consume only on match. Leave the token as `$1` otherwise so the next loop iteration picks it up as a flag or positional:

    ```bash
    -w|--watch)
        watch=true; shift
        if [ -n "${1:-}" ] && printf '%s' "$1" | grep -qE '^[1-9][0-9]*[smh]?$'; then
            interval="$1"; shift
        fi
        ;;
    ```

3. The `--foo=*)` arm is unchanged from the normal required-value pattern (empty value after `=` errors with the canonical missing-value phrasing). Bare `--foo` (no `=`) falls through to the space-form arm above.

4. In `--help`, bracket the value name: `-w, --watch [interval]`.

5. Leave a comment above the `_expand_short_opts` call citing this section and explaining why the letter is excluded from value-opts.

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

### Conditional dependencies

Some tools are needed only when a specific flag or mode is used. Place the `command -v` check inside the gated code path -- after argument parsing, immediately before the first call -- not unconditionally at the top of the script. A user who never reaches for `--validate` should not be blocked by a missing `openssl`.

```bash
if [ "$validate" ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        _error "openssl is required"
        return 3
    fi
    # ... use openssl
fi
```

The error message uses the canonical `"<tool> is required"` phrasing -- no need to mention the gating flag, since the tool is only invoked when the flag is set and the user already knows what they asked for. The exit code remains `3` (dependency error).

In the `--help` `DEPENDENCIES` section and the `.md` Dependencies list, mark conditional tools with a parenthetical noting when they're needed:

```
DEPENDENCIES
  dig
  openssl (required only for --validate)
```

This keeps the unconditional deps prominent while making the conditional ones discoverable.

## Commit Style

- **Subject format:** `Update <script> - <short description>` (leading verb "Update", no final period). For truly new additions, `Add <script> - <short description>`.
- **Body:** bulleted, one bullet per concrete change. Focus on the "what" -- the rationale can go in the spec or commit message body paragraph if needed, but subject + bullets is usually enough.
- **Scope:** one commit per script. The commit covers the script itself plus `docs/<name>.md` and `tests/<name>.test.sh` if those change. Cross-cutting edits (`CONVENTIONS.md`, `test-helpers.sh`, `test-runner.sh`) get their own commits.
- **Exceptions:** when a single change applies identically to multiple scripts -- typo sweeps, formatting passes, or one mechanical fix repeated across several files -- bundle them into one commit. The guiding principle is "splitting would add no clarity"; several near-identical commits add review cost without payoff. Subject format for bundled commits: `Update <script-a> + <script-b> - <description>` for two, `Update <N> scripts - <description>` for more.
