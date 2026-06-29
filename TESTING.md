# Testing

Standards for test files in this repository.

## Principles

- Every script gets a `<name>.test.sh` in the `tests/` directory (alongside `test-helpers.sh` and `test-runner.sh`). The exceptions are cross-cutting **meta-tests**, named `meta-*.test.sh` -- see [Meta-tests](#meta-tests)
- Tests are self-contained, network-free, and runnable with bash 3.2+
- No external dependencies beyond bash builtins and standard POSIX tools (mktemp, cat, mkdir, chmod, etc.)
- All external commands the script-under-test calls (curl, dig, jq, etc.) are shimmed
- Each test case gets a fresh temp directory for isolation
- Test files do NOT follow CONVENTIONS.md -- they use a simpler structure
- Test files are **execute-only**: run them with `test-runner.sh` or `bash <file>`, never source them. `run_tests` ends in `exit`, so sourcing a test into an interactive shell would close it -- the helper guards against this (see [Permissions](#permissions))

## File Structure

```bash
#!/bin/bash
# script-name.test.sh - Tests for script-name
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../script-name"

# --- shims ---

write_shims() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stderr_contains "help has NAME" "NAME"
}

test_missing_arg() {
    run_script
    assert_rc "missing arg exits 2" 2
}

# --- run ---

run_tests "$@"
```

### Key points

- `UNDER_TEST` -- absolute path to the script being tested
- `write_shims` -- defined in the test file, called by the helpers during setup. Omit if the script has no external dependencies
- Each test case is a function prefixed with `test_`
- `run_tests "$@"` (from helpers) discovers and runs all `test_` functions

## test-helpers.sh

Shared file that every test sources. Provides:

### Setup and teardown

`run_tests` is the entry point. It:

1. Parses flags (`-v` for verbose)
2. Creates a root temp directory
3. Discovers all functions matching `test_*`
4. For each test function:
   a. Creates `$TEST_DIR` (a fresh subdirectory) and `$SHIM_DIR` (for shimmed executables)
   b. Calls `write_shims` if defined
   c. Runs the test function
   d. Tracks pass/fail
5. Cleans up the root temp directory
6. Prints summary and exits 0 (all passed) or 1 (any failed)

### Running the script under test

`run_script [args...]` runs `$UNDER_TEST` with:

- `TEST_DIR` exported so shims can reference it (e.g. to write arg logs)
- `PATH` prefixed by `$SHIM_DIR` so shims shadow real commands
- stdout captured to `$TEST_DIR/stdout`
- stderr captured to `$TEST_DIR/stderr`
- Exit code stored in `$TEST_DIR/rc`

### Sourced scripts

Some scripts must be sourced (`.  script`) rather than executed. Their purpose is to mutate the caller's shell state -- set a variable, change the environment, define a function -- and executing them in a subshell loses that side effect. `prompt` is the canonical example.

Two runners handle this:

- `run_script_sourced [args...]` -- sources `$UNDER_TEST` in a fresh subshell. stdout/stderr/rc captured the same way as `run_script`. Use for argument validation, `--help`, or any code path where you only care about output and exit code.
- `run_script_sourced_capture "VAR1 VAR2 ..." [args...]` -- sources the script, then writes the final values of the named variables to `$TEST_DIR/captured` as `NAME=VALUE` lines. Pair with `assert_captured`.

Both runners set `$0="bash"` inside the subshell so the script's sourced-vs-executed check (typically `$0 != bash`) passes. The invocation shape is `/bin/bash -c '...' bash "$UNDER_TEST" "$@"` -- note the literal `bash` positional.

Feed input on stdin by piping to the runner, same as any other command:

```bash
test_default_on_empty_input() {
    printf '\n' | run_script_sourced_capture "ANSWER" ANSWER "Continue? " "yes"
    assert_rc "empty input exits 0" 0
    assert_captured "default used when empty" ANSWER "yes"
}
```

See `prompt.test.sh` for the reference implementation.

### Assertions

All assertions take a label as the first argument. On failure, they print `[FAIL] label: details` to stderr and return 1. On success, they print `[OK] label` only if `-v` was passed.

- `assert_rc "label" <expected>` -- check exit code from last `run_script`
- `assert_eq "label" "got" "want"` -- exact string match
- `assert_contains "label" "haystack" "needle"` -- substring match
- `assert_not_contains "label" "haystack" "needle"` -- substring absence
- `assert_file_exists "label" "path"` -- check that a file is present at path
- `assert_captured "label" VAR "expected"` -- check a variable value from last `run_script_sourced_capture`

### Output helpers

- `get_stdout` -- prints captured stdout from last `run_script`
- `get_stderr` -- prints captured stderr from last `run_script`
- `get_rc` -- prints captured exit code from last `run_script`

These read from `$TEST_DIR/stdout`, `$TEST_DIR/stderr`, `$TEST_DIR/rc`.

Convenience wrappers for common patterns:

- `assert_stdout_contains "label" "needle"` -- shorthand for `assert_contains "label" "$(get_stdout)" "needle"`
- `assert_stdout_not_contains "label" "needle"` -- shorthand for `assert_not_contains "label" "$(get_stdout)" "needle"`
- `assert_stderr_contains "label" "needle"` -- shorthand for `assert_contains "label" "$(get_stderr)" "needle"`
- `assert_stderr_not_contains "label" "needle"` -- shorthand for `assert_not_contains "label" "$(get_stderr)" "needle"`

### Verbosity

- Default: only `[FAIL]` lines print, plus a summary with total/pass/fail counts
- `-v`: `[OK]` lines also print

## Writing Shims

Shims are defined in the test file's `write_shims` function because shim behavior is script-specific. Each shim is a small executable written to `$SHIM_DIR`.

### Basic pattern

A shim should log its args so tests can assert on what the script passed to the external command:

```bash
write_shims() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"
}
```

Then in a test case:

```bash
test_passes_correct_flags() {
    run_script "https://example.com"
    assert_rc "exits 0" 0
    assert_contains "adds -sS" "$(cat "$TEST_DIR/curl.args")" "-sS"
}
```

### Default behavior

Shims should succeed silently by default. Special behavior (simulate failure, empty output, etc.) is handled in two ways:

**Override per test case** -- rewrite the shim before calling `run_script`. Since test cases run sequentially, this is safe:

```bash
test_curl_failure() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
echo "curl: connection refused" >&2
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script "https://example.com"
    assert_rc "curl failure exits 3" 3
}
```

**Trigger via argument** -- the shim inspects its args to decide behavior:

```bash
# In write_shims:
cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/dig.args"
for a in "$@"; do
    case "$a" in
        *noresult*) exit 0 ;; # return nothing
    esac
done
printf '%s\n' "192.0.2.11"
exit 0
SHIM
chmod +x "$SHIM_DIR/dig"
```

## test-runner.sh

An aggregate runner that finds and runs all test files. Lives in `tests/` alongside the test files. Unlike test files, this follows CONVENTIONS.md since it is a tool.

- Globs `*.test.sh` in its own directory (`tests/`)
- Runs each file, captures its exit code
- Accepts an optional pattern to filter which tests to run (e.g. `test-runner.sh pin-dns`)
- Prints a final summary: which files passed, which failed
- Exits 0 if all passed, 1 if any failed

## Permissions

The executable bit follows the repo-wide rule that `+x` means "execute this" and `-x` means "source this, or it is not runnable as-is" (e.g. the source-only `dbg` and `prompt` scripts are `-x` and refuse execution). In `tests/`:

| File | Bit | Why |
| --- | --- | --- |
| `<name>.test.sh`, `meta-*.test.sh` | `+x` | Execute-only -- run via `test-runner.sh` or `bash <file>` |
| `test-runner.sh` | `+x` | The entry point you invoke |
| `test-helpers.sh` | `-x` | Sourced by every test, never run on its own |

Two backstops keep this from drifting: sourcing a test triggers a refuse-and-`return` guard in `run_tests` (a sourced file's `${BASH_SOURCE[1]}` differs from `$0`), and `meta-coverage.test.sh` asserts every file above carries the right bit.

## Meta-tests

Most test files target one script: `<name>.test.sh` exercises `../<name>`, and defines `UNDER_TEST` to point at it. A **meta-test** is different -- it validates a convention across the *whole* script fleet rather than any single script. Meta-tests are named with a `meta-` prefix so the distinction is visible at a glance (in `ls`) and checkable programmatically (by the `meta-*` glob):

| File | Asserts |
| --- | --- |
| `meta-cleanup-on-source.test.sh` | Sourcing any script with `--help` leaks no functions or variables into the caller's shell (CONVENTIONS Cleanup Trap / Source-only scripts) |
| `meta-curl-pipe.test.sh` | Every script works when piped or process-substituted (`curl \| bash`, `bash <(...)`, `. <(...)`) (CONVENTIONS "Use `$SCRIPT_NAME`") |
| `meta-coverage.test.sh` | The script↔test bijection holds: every bash script has a test, and every non-`meta-` test has a matching script |
| `meta-comment-style.test.sh` | No comment ends in a trailing `.` or `!` (CONVENTIONS Style rule); internal sentence-separating periods in a multi-line block are allowed |

Conventions for a meta-test:

- **Name it `meta-<topic>.test.sh`.** This is the signal. `meta-coverage.test.sh` keys off the prefix to exempt meta-tests from its "every test has a script" check -- a meta-test without the prefix would be flagged as an orphan (a test for a script that doesn't exist).
- **No `UNDER_TEST`.** There is no single script under test. Walk `"$REPO_DIR"/*` (or `tests/*.test.sh`) instead.
- **Reuse the `_is_bash_script` filter** when iterating the repo, so node scripts (`render-md`) and non-script `.sh`/`.md`/`.json` files are excluded consistently. `meta-cleanup-on-source.test.sh` and `meta-coverage.test.sh` carry identical copies.

Meta-tests are discovered and run exactly like any other file: `test-runner.sh` globs `*.test.sh`, and `run_tests` finds the `test_*` functions inside. Run one in isolation with `test-runner.sh meta-coverage`.

## Pre-commit hook

A meta-test only fires when someone runs the suite, so a convention it polices can still be violated by a commit that never runs it. The tracked pre-commit hook closes that gap for the *fast, static* checks. Activate it once per clone:

```bash
tests/hooks/install        # points core.hooksPath at tests/hooks/
tests/hooks/install --uninstall   # restore the default
```

The hook (`tests/hooks/pre-commit`) runs only the static, no-script-execution meta-tests listed in its `STATIC_METATESTS` variable (currently `meta-comment-style`), so it stays sub-second and there is no incentive to skip it. The slower fleet meta-tests and per-script suites are **not** run by the hook -- run those with `test-runner.sh` before pushing.

The hook is a convenience gate, not a guarantee: `git commit --no-verify` bypasses it, and a clone that never runs `install` has no hook at all. Server-side CI is the only unskippable enforcement; until this repo has it, the hook plus a periodic full `test-runner.sh` run are the backstop.

## What to Test

### Always test

- **`--help` exits 0** and output includes expected sections (NAME, SYNOPSIS, etc.)
- **Argument validation** -- missing required args, invalid values, unknown flags. Assert on specific exit codes where the script defines them
- **Core behavior** -- happy path with valid args. Assert on stdout/stderr and exit code. For scripts that modify files, assert on filesystem state in the temp dir
- **Exit codes** -- each distinct exit code the script uses should have at least one test case

### Test when relevant

- **Edge cases** -- empty input, paths with spaces, missing dependencies (shim exits 127)
- **Flag interactions** -- flags that modify each other's behavior (e.g. `--quiet` suppressing warnings)

### Don't test

- **Bash itself** -- if the script calls `mkdir -p`, don't test that `mkdir -p` works. Test the script's logic and decisions, not the tools it delegates to

## Gotchas

### Real commands shadowed by shims

When a test removes a shim to simulate "command not found", the real command (if installed) is still on `$PATH`. To truly simulate a missing dependency, restrict PATH to only `$SHIM_DIR`:

```bash
test_fswatch_missing() {
    rm "$SHIM_DIR/fswatch"
    # Restrict PATH so real fswatch is not found
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "no fswatch exits 1" 1
}
```

### `read` inside `find | while` pipes

If the script under test calls `read` (e.g. for interactive prompts) inside a `find ... | while read` pipe, stdin is connected to the find output, not the user's input. Piping input via `printf 's\n' | run_script -i` will not reach the inner `read`. Interactive tests for scripts with this pattern are not feasible -- test non-interactive code paths instead.

Scripts that use `while read ... done < <(find ...)` (process substitution) do not have this problem.

### Scripts that write to CWD

If the script writes output files to the current working directory, override `run_script` to cd into `$TEST_DIR`:

```bash
run_script() {
    ( cd "$TEST_DIR" || exit 1
      env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
          /bin/bash "$UNDER_TEST" "$@"
    ) >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}
```

### Recursive shims

A shim must never call itself. For example, a `cat` shim that uses `cat` internally will recurse infinitely. Either delegate to the real binary via absolute path (`exec /bin/cat "$@"`) or avoid using the shimmed command name inside the shim.

### Interactive scripts (stdin)

For scripts that read from stdin (e.g. `read -r input`), feed input via a custom runner:

```bash
run_script_with_input() {
    local input="$1"
    shift
    printf '%s' "$input" | env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}
```

Or redirect from a file: `exec < "$TEST_DIR/input.txt"` in a subshell wrapper
