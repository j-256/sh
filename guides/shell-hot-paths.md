# Fast shell startup and hot paths

Shell startup files, command wrappers, hooks, and small CLIs tend to become slow one reasonable addition at a time. A version manager scans its installation, a health check verifies live state, a parser is invoked once per field, and optional integrations initialize before anyone asks for them. None looks expensive alone, but every cost sits between invocation and the first useful action.

The governing principle is simple:

> Freshness does not require blocking readiness.

Treat time to ready and time to fully settled as separate latency targets. Keep true prerequisites on the synchronous path, start freshness work asynchronously when its result may arrive later, load optional capabilities on first use, and move unrelated maintenance out of startup entirely. Then optimize all of those paths anyway, because deferred work still consumes resources and affects tail latency.

## Define readiness before optimizing

"Startup finished" is too vague to design or measure. Name the first useful event instead: the prompt accepts input, the wrapper begins streaming its result, the hook releases the parent process, or the requested subcommand starts doing its own work.

For each startup operation, ask whether that event depends on its result.

| Work type | Scheduling choice | Typical examples |
| --- | --- | --- |
| Required for correctness now | Synchronous hot path | Configuration needed by the next operation, required authentication, input validation |
| Must run every invocation, result may arrive later | Eager asynchronous | Health checks, drift detection, advisory diagnostics |
| Needed only when a feature is used | Lazy | Version managers, completion systems, optional SDKs and plugins |
| Independent of this invocation | Periodic process or daemon | Cleanup, update scans, telemetry aggregation |
| Stable until a known input changes | Cache with explicit invalidation | Deterministic discovery or generated metadata |

Use this decision sequence:

```text
Does readiness depend on the result?
  yes -> run synchronously
  no  -> must it run for every invocation?
           yes -> start it asynchronously
           no  -> is it needed when a feature is first used?
                    yes -> load it lazily
                    no  -> schedule it independently
```

Caching is not a synonym for deferral. If a check must observe live state on every invocation, keep that frequency and change only the waiting relationship. An asynchronous check can still be fresh every time.

## Make the work cheaper too

Moving an operation off the hot path improves readiness latency, but it does not make the operation free. It can still compete with foreground work for CPU and I/O, delay complete settlement, consume battery, or multiply across many concurrent shells.

Shell performance is often process performance. Before reaching for a cache, look for avoidable process boundaries and repeated scans:

- Return several fields from one parser invocation instead of invoking the parser once per field
- Keep loop bookkeeping in shell variables instead of running a command substitution for every record
- Prefer parameter expansion and shell builtins when they express the same operation clearly
- Read a small file once and reuse its contents within the invocation
- Dispatch a cheap subcommand before defining or initializing handlers it cannot reach
- Stop a search after finding the newest relevant record when older records cannot change the answer
- Avoid temporary files used only to move a scalar between adjacent commands

Batching must preserve error semantics. One combined parser invocation is only equivalent when malformed input, missing fields, defaults, and exit statuses still behave the same way as the separate calls.

## Run frequent checks asynchronously

A startup check is a good async candidate when all of the following are true:

- Later startup code does not consume its result
- The check does not mutate the parent shell's variables, directory, options, or file descriptors
- A result delivered at the next safe output boundary is still useful
- Concurrent invocations are safe, or the implementation defines an explicit serialization policy
- Failure can be captured and surfaced rather than silently discarded

Do not let a background process write directly into an interactive terminal while the user may be typing. Capture each invocation's output separately, mark completion atomically, and flush the captured output from a prompt hook or another UI-owned boundary.

This Bash 3.2-compatible sketch shows the core lifecycle. It intentionally uses a unique private directory for each invocation and a completion file rather than a shared result cache:

```bash
_startup_check_poll() {
    local directory="${STARTUP_CHECK_DIRECTORY:-}"
    [ -n "$directory" ] || return 0
    [ -f "$directory/done" ] || return 0

    local status
    IFS= read -r status < "$directory/status" || status=1
    [ ! -s "$directory/output" ] || cat "$directory/output"
    case "$status" in
        0) ;;
        *) printf '%s\n' "startup check exited with status $status" >&2 ;;
    esac
    rm -f "$directory/output" "$directory/status" "$directory/done"
    rmdir "$directory" 2>/dev/null || :
    unset STARTUP_CHECK_DIRECTORY STARTUP_CHECK_PID
}

_startup_check_begin() {
    local check="$1"
    local directory; directory="$(mktemp -d "${TMPDIR:-/tmp}/startup-check.XXXXXX")" || {
        "$check" || :
        return 0
    }

    STARTUP_CHECK_DIRECTORY="$directory"

    # The command-substitution shell owns the background job so interactive
    # Bash does not print a job-control banner before the first prompt
    STARTUP_CHECK_PID="$(
        (
            umask 077
            trap ': > "$directory/done"' EXIT
            status=0
            "$check" > "$directory/output" 2>&1 || status=$?
            printf '%s\n' "$status" > "$directory/status"
        ) </dev/null >/dev/null 2>&1 &
        printf '%s\n' "$!"
    )"
}
```

The command-substitution layer is load-bearing. A direct `(...) &` launched by an interactive shell may print a job number and PID even if it is immediately disowned. Moving ownership into the short-lived subshell prevents that banner. Because the interactive shell is no longer the worker's direct parent, poll the completion marker instead of relying on `wait`.

Call `_startup_check_poll` from the shell's existing prompt hook. Preserve any hook already installed, avoid adding the poller twice when startup files are re-sourced, and account for both scalar and array forms if the supported Bash versions include both. A prompt hook should only inspect completed state; it must never block waiting for the worker.

### Always provide a synchronous mode

Async behavior needs a deterministic escape hatch for debugging, tests, automation, and environments where background execution is unavailable:

```bash
_run_startup_check() {
    local check="$1"
    if [ "${STARTUP_CHECKS_ASYNC:-1}" != 0 ]; then
        case "$-" in
            *i*) _startup_check_begin "$check"; return 0 ;;
        esac
    fi

    local status=0
    "$check" || status=$?
    case "$status" in
        0) ;;
        *) printf '%s\n' "startup check exited with status $status" >&2 ;;
    esac
}
```

The override should restore the real synchronous operation, not a mock, cached answer, or reduced check. Non-interactive shells should normally use the synchronous path unless their caller explicitly participates in the async result protocol.

### Decide the overlap policy explicitly

Re-sourcing startup files or starting several shells at once creates concurrency that the old synchronous design may never have seen. Pick and document one behavior:

- Run every invocation independently when freshness per invocation is the contract and the work is read-only
- Serialize mutating work with a lock while allowing unrelated startup to continue
- Coalesce equivalent work only when callers accept shared results and the invalidation boundary is trustworthy
- Fall back to synchronous execution when the current shell already has an unfinished worker and losing either invocation would violate the contract

Never let an accidental global temp filename choose the policy for you. Unique state directories, private permissions, an `EXIT` completion trap, and cleanup after delivery make the lifecycle explicit. Also decide what happens if the parent shell exits before polling; ephemeral state may be left for operating-system cleanup, removed by an exit hook, or expired by a separate maintenance policy.

### Watch for foreground contention

Async work can slow the hot path by competing with it. Start I/O-bound checks early when they can spend most of their lifetime waiting. Consider starting CPU-heavy checks at readiness, running them with lower priority, or moving them to an independent scheduler. Measure under realistic concurrency instead of assuming that `&` removed the cost.

## Load optional capabilities lazily

Lazy initialization is better than eager async when startup does not need the work at all unless a particular command is used. A self-replacing function can preserve the normal command name while loading its implementation on first call:

```bash
heavy_tool() {
    unset -f heavy_tool
    if ! . "$HOME/.heavy-tool/init.sh"; then
        printf '%s\n' "heavy_tool: initialization failed" >&2
        return 1
    fi
    if ! command -v heavy_tool >/dev/null 2>&1; then
        printf '%s\n' "heavy_tool: initializer did not define heavy_tool" >&2
        return 1
    fi
    heavy_tool "$@"
}
```

This pattern is appropriate only when initialization has no side effect that every shell requires before other commands run. Preserve arguments and exit status, make failure visible, and verify that the initializer actually replaced the wrapper before recursing.

Completions can often be lazier still: load a completion definition when the command is first completed rather than when the shell starts. The exact mechanism differs by shell, but the dependency rule stays the same.

## Measure readiness and settlement separately

An internal timer around one function answers a different question from an external timer around the user's actual invocation. A useful benchmark records at least three values:

1. **Synchronous baseline:** process launch through full startup with deferral disabled
2. **Time to ready:** process launch through the first useful event with normal scheduling
3. **Time to settled:** process launch through completion and delivery of deferred work

Use the same executable, environment, startup mode, working directory, and input shape the user actually experiences. Run warmups before measured iterations, prevent background workers from overlapping the next iteration, and report the iteration count with mean, median, minimum, and maximum. Compare distributions, not a single lucky launch.

Instrument major boundaries with a cheap shell builtin when possible. Full xtrace output can distort a profile by adding work to every command, especially in files containing many function definitions. Category timings should add back to the externally observed total; if they do not, name the unmeasured region rather than renormalizing it away.

After an async change, benchmark the optimized implementation synchronously as well. That separates two independent wins:

- **Implementation improvement:** the work itself became cheaper
- **Scheduling improvement:** the caller stopped waiting for all of it

Both matter. The synchronous number protects automation and the fallback path, while settlement time reveals whether a faster prompt merely hid a growing resource cost.

## Review checklist

- Is the readiness event named precisely?
- Does every synchronous operation produce state needed before that event?
- Does every async operation have isolated output, visible failure, and a delivery boundary?
- Can any deferred operation race with another invocation or mutate state used by the foreground?
- Is there a real synchronous override?
- Are optional integrations loaded only when used?
- Were repeated subprocesses, scans, and parser invocations reduced before adding a cache?
- Were time to ready, time to settled, and synchronous runtime measured independently?
- Did the benchmark prevent background work from leaking into the next iteration?
- Do non-interactive shells and older supported Bash versions retain deterministic behavior?

Fast startup is not the absence of checks. It is a clear readiness contract, inexpensive implementation, deliberate scheduling, and reliable delivery of everything that finishes later.
