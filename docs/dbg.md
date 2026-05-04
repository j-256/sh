# dbg

[View script](../dbg)

Print variables as key-value pairs for debugging -- for shell scripts (or interactive shells) where you want to see what's in a variable without writing the whole `echo "var=$var"` dance.

Given one or more references, `dbg` emits one assignment-like line to stderr for each: scalars, whole arrays, `arr[@]`, `arr[*]`, element/map refs, and exported variables are all handled. Unset variables report `unset name` explicitly rather than silently printing an empty line.

**Must be sourced, not executed.** It reads variables from *your* shell, which only works via sourcing (`. dbg ...`).

## Quick start

```bash
. dbg var_name
```

If `$var_name` is `"hello"`, stderr gets `var_name="hello"`. If it's unset, stderr gets `unset var_name`. Multiple refs in one call are supported:

```bash
. dbg name email role
```

## Common examples

**Inspect a scalar:**

```bash
user="alice"
. dbg user
# stderr: user="alice"
```

**Inspect a value with escape sequences or newlines:** this is the case where `echo` falls down. Control chars can recolor your terminal, and embedded newlines split the output mid-value so you can't tell what's actually in the variable.

```bash
greeting=$'\e[31mHello\n\e[0mWorld'

echo "greeting=$greeting"
# stdout: greeting=[red]Hello
#         [reset]World

. dbg greeting
# stderr: greeting=$'\E[31mHello\n\E[0mWorld'
```

`dbg` switches to `printf %q` form for values containing control characters: one line, escape sequences visible as `\E`, newline as `\n`, and safe to re-source.

**Inspect an array with mixed content:** the control-char check is per-element, so plain values stay readable while hostile ones get the `%q` treatment.

```bash
arr=($'\e[32mgreen' 'plain value' $'line1\nline2')
. dbg 'arr[@]'
# stderr: arr[@]=$'\E[32mgreen' "plain value" $'line1\nline2'
```

Note that `"plain value"` stays in the more readable form instead of `plain\ value`, which is what `printf %q` would emit.

**Inspect an exported variable:**

```bash
export API_KEY="secret"
. dbg API_KEY
# stderr: export API_KEY="secret"
```

The `export` prefix surfaces the export status so the output line reflects the variable's full declaration, not just its value.

**Inspect a whole array:**

```bash
arr=(a b "c d")
. dbg arr
# stderr: arr=([0]="a" [1]="b" [2]="c d")
```

This form uses `declare -p` output directly, so the output is a valid bash assignment.

**Preserve element boundaries with `[@]`:**

```bash
arr=(a b "c d")
. dbg 'arr[@]'
# stderr: arr[@]="a" "b" "c d"
```

Each element is quoted separately, so you can see where one element ends and the next begins -- useful when debugging argument-passing.

**Join array elements with `[*]` (reflects current `$IFS`):**

```bash
arr=(a b c)
. dbg 'arr[*]'
# stderr: arr[*]="a b c"
```

**Inspect a specific array element:**

```bash
arr=(a b "c d")
. dbg 'arr[2]'
# stderr: arr[2]="c d"
```

Missing elements report `unset`:

```bash
. dbg 'arr[99]'
# stderr: unset arr[99]
```

**Inspect an associative-array value:**

```bash
declare -A users=([alice]=admin [bob]=user)
. dbg 'users[alice]' 'users[missing]'
# stderr: users[alice]="admin"
# stderr: unset users[missing]
```

**Debugging a function:** sprinkle `. dbg ...` calls inside a function as you would `echo` calls. Because the script self-cleans (it defines, runs, and unsets), there's no persistent state to worry about.

```bash
process() {
    local input="$1"
    local normalized="${input,,}"
    . dbg input normalized   # stderr: input="Hello"  normalized="hello"
    # ...
}
```

## Must be sourced

Executing `dbg` directly produces an error:

```
$ dbg VAR
[ERR][dbg] Must be sourced, not executed. Run `dbg -h` for usage
```

This is by design. The script reads variables from *your* shell, which is impossible from a subprocess. Always invoke it via sourcing:

```bash
. dbg VAR
```

or with the `source` keyword (equivalent):

```bash
source dbg VAR
```

`dbg --help` works even when executed, so someone running `dbg --help` cold gets help instead of the rejection.

## Interactive-shell wrapper

For heavy interactive use, defining a bare-word wrapper in your shell rc gives you `dbg VAR` ergonomics:

```bash
dbg() { . dbg "$@"; } && export -f dbg
```

The script self-cleans on every call, so you don't need to worry about stale inner functions in your shell. The wrapper only changes the invocation shape; the script remains the single source of truth.

## Output format

Values are rendered in one of two forms, chosen automatically:

- **Double-quoted form** (default): `name="value"`, with `\`, `"`, `$`, and backtick escaped so the output line is safe to re-source
- **`printf %q` form** (control-char values): `name=$'...'` or similar, rendered on a single line

See the escape-sequence and mixed-array examples above for what this looks like in practice.

## Strict mode (`__DBG_STRICT`)

For array element and `[@]`/`[*]` refs, `dbg` uses `eval` to resolve the reference. Set `__DBG_STRICT=true` to reject refs containing eval-unsafe syntax before evaluation:

```bash
export __DBG_STRICT=true
. dbg 'arr[key; rm -rf /]'
# stderr: [ERR][dbg] Unsupported reference 'arr[key; rm -rf /]' ...
```

Rejected patterns: `$(...)`, backticks, `${...}`, operators (`;`, `|`, `&`, `>`, `<`), newlines, single quotes, double quotes. Useful when the ref might come from untrusted input; unnecessary for hand-typed debugging.

Default is off. Scripts that take refs from external input should set it; interactive use rarely needs it.

---

## Reference

### Positional arguments

```bash
. dbg <ref> [<ref>...]
```

Each `<ref>` is one of:

| Form | Example | Output shape |
|---|---|---|
| Scalar name | `user` | `user="value"` or `unset user` |
| Whole array | `arr` | `arr=([0]="a" [1]="b" ...)` (via `declare -p`) |
| All elements | `'arr[@]'` | `arr[@]="a" "b" "c d"` (quoted separately) |
| Joined | `'arr[*]'` | `arr[*]="a b c"` (single token, IFS-joined) |
| Element | `'arr[2]'`, `'map[key]'` | `arr[2]="value"` or `unset arr[2]` |

Subscript forms must be quoted in the call to prevent the shell from expanding `[...]` as a glob.

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `__DBG_STRICT` | `false` | When `true`, reject refs containing eval-unsafe syntax |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (script was executed rather than sourced) |

### Warnings

- **Output goes to stderr.** Program output stays on stdout; diagnostic output like `dbg` lives on stderr so it doesn't contaminate piped output.
- **Refs must be valid bash identifiers.** Names with spaces, hyphens, or other non-identifier chars are not supported.
- **Subscripts on non-arrays error out.** `'scalar[0]'` reports `'scalar' is not an array` rather than silently misbehaving.
- **Malformed brackets error out.** `'arr['` or `'arr]'` report `malformed brackets` before attempting eval.
- **Literal newlines in scalars** are emitted by `declare -p` as double-quoted multi-line output (bash 3.2) or `$'...'` form (bash 4+). Both are valid bash, but the multi-line form is less grep-friendly.
- **Requires bash 3.2+.** Associative-array handling requires bash 4+ (which adds `declare -A`).
