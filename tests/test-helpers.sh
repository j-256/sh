#!/bin/bash
# test-helpers.sh - Shared test infrastructure
#
# Source this at the top of every .test.sh file
# See TESTING.md for full documentation
# shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- single-quoted inline bash scripts are intentional

_VERBOSE=0
_PASS=0
_FAIL=0

# --- output helpers ---

get_stdout() { cat "$TEST_DIR/stdout" 2>/dev/null; }
get_stderr() { cat "$TEST_DIR/stderr" 2>/dev/null; }
get_rc() { cat "$TEST_DIR/rc" 2>/dev/null; }

# --- assertions ---

_ok() {
    _PASS=$((_PASS + 1))
    [ "$_VERBOSE" -eq 1 ] && echo "[OK] $1"
    return 0
}

_fail() {
    _FAIL=$((_FAIL + 1))
    echo "[FAIL] $1" >&2
    return 1
}

assert_eq() {
    local label="$1"
    local got="$2"
    local want="$3"
    if [ "$got" = "$want" ]; then
        _ok "$label"
    else
        _fail "$label: expected '$want', got '$got'"
    fi
}

assert_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    case "$haystack" in
        *"$needle"*) _ok "$label" ;;
        *) _fail "$label: expected to contain '$needle'" ;;
    esac
}

assert_not_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    case "$haystack" in
        *"$needle"*) _fail "$label: expected NOT to contain '$needle'" ;;
        *) _ok "$label" ;;
    esac
}

assert_rc() {
    local label="$1"
    local want="$2"
    assert_eq "$label" "$(get_rc)" "$want"
}

assert_stdout_contains() {
    local label="$1"
    local needle="$2"
    assert_contains "$label" "$(get_stdout)" "$needle"
}

assert_stdout_not_contains() {
    local label="$1"
    local needle="$2"
    assert_not_contains "$label" "$(get_stdout)" "$needle"
}

assert_stderr_contains() {
    local label="$1"
    local needle="$2"
    assert_contains "$label" "$(get_stderr)" "$needle"
}

assert_stderr_not_contains() {
    local label="$1"
    local needle="$2"
    assert_not_contains "$label" "$(get_stderr)" "$needle"
}

assert_file_exists() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        _ok "$label"
    else
        _fail "$label: file not found: $path"
    fi
}

# --- hang guard ---

# A script under test that blocks on unfed input or spin-loops would otherwise
# hang the whole suite -- run_tests has no per-test timeout, so one stuck script
# never reports and the run never ends. When `timeout` (GNU coreutils; installed
# as `gtimeout` by Homebrew on macOS) is available, each run_script* invocation
# is bounded: a stuck script is killed and the test fails (rc 124) instead of
# hanging. Override the bound with TEST_TIMEOUT (seconds). When neither binary is
# present, runs are UNBOUNDED -- we warn once so the hang-the-suite failure mode
# is known rather than mysterious.
_TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
if command -v timeout >/dev/null 2>&1; then
    _TIMEOUT="timeout $_TEST_TIMEOUT"
elif command -v gtimeout >/dev/null 2>&1; then
    _TIMEOUT="gtimeout $_TEST_TIMEOUT"
else
    _TIMEOUT=""
    echo "[WRN][test-helpers] 'timeout' not found (try: brew install coreutils); a hanging script under test will hang the whole suite" >&2
fi

# --- script runner ---

# All script runners pin PATH to $SHIM_DIR plus the system tool dirs
# (/usr/bin:/bin) rather than inheriting the caller's $PATH, so a run is
# deterministic across machines: the script under test sees its shims first,
# then only stock OS tools -- never a host-specific Homebrew/nvm binary that is
# present on one box and absent on another. A test that asserts a tool is
# absent (e.g. "glow is not on PATH") must not hinge on the dev's installs.
# Tests needing tighter isolation still narrow PATH locally (PATH="$SHIM_DIR"
# or PATH=""); a test that genuinely needs a non-system tool sets its own PATH
run_script() {
    # shellcheck disable=SC2086 # "Double quote to prevent globbing and word splitting." -- $_TIMEOUT is "timeout N" or empty; the split is intentional
    $_TIMEOUT env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Source the script under test (instead of executing it). Use for scripts that
# must be sourced to mutate caller-shell state. Sets $0 to "bash" inside the
# subshell so the script's sourced-vs-executed check (typically $0 != bash)
# passes. stdout/stderr/rc captured the same way as run_script
run_script_sourced() {
    # shellcheck disable=SC2086 # "Double quote to prevent globbing and word splitting." -- $_TIMEOUT is "timeout N" or empty; the split is intentional
    $_TIMEOUT env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        /bin/bash -c 'script="$1"; shift; . "$script" "$@"' bash "$UNDER_TEST" "$@" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Source the script and capture one or more variable values that the script set
# in the caller's shell. Captured values land in $TEST_DIR/captured as NAME=VALUE
# lines (one per variable, in the order given)
# Usage: run_script_sourced_capture "VAR1 VAR2 ..." [args...]
run_script_sourced_capture() {
    local vars="$1"; shift
    # shellcheck disable=SC2086 # "Double quote to prevent globbing and word splitting." -- $_TIMEOUT is "timeout N" or empty; the split is intentional
    $_TIMEOUT env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" VARS="$vars" \
        /bin/bash -c '
            script="$1"; shift
            . "$script" "$@"
            rc=$?
            : > "$TEST_DIR/captured"
            for v in $VARS; do printf "%s=%s\n" "$v" "${!v}" >> "$TEST_DIR/captured"; done
            exit $rc
        ' bash "$UNDER_TEST" "$@" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

assert_captured() {
    local label="$1"
    local var="$2"
    local want="$3"
    local got; got="$(grep "^${var}=" "$TEST_DIR/captured" 2>/dev/null | head -1 | cut -d= -f2-)"
    assert_eq "$label" "$got" "$want"
}

# --- option-arm parsing (shared by the surface-parity and canonical-letter meta-tests) ---

# Scripts excluded from the option-surface meta-tests, space-separated. The shared
# base is pin-dns: a curl wrapper whose helper functions case-match curl's own
# short flags to classify borrowed args before forwarding them. _option_flags and
# _option_pairs scan every case...esac, so they can't tell those recognizer arms
# from real option arms and over-report pin-dns's surface -- a tooling limit, not a
# spec violation (pin-dns's authored surface is in sync). Each meta-test appends its
# own exemptions on top of this base (EXCLUDE="$_META_OPT_EXCLUDE extra-script")
# rather than editing this constant, so a test-specific exemption doesn't leak
# across tests -- e.g. the canonical-letter test additionally exempts pin-dns for a
# different, real reason (it reserves its whole short space for curl passthrough, so
# its own options are long-only by design; see CONVENTIONS), which is an authored
# exception to the canonical-binding rule, not the extractor artifact excluded here.
# (Non-bash scripts like render-md are dropped by the shebang filter, not here.)
_META_OPT_EXCLUDE="pin-dns"

# Emit the set of option flags a script's argument parser accepts, one per line,
# sorted and deduplicated. Reads case-arm labels inside every `case ... esac`
# block in the script (the main parse loop plus any in sub-functions), so a flag
# handled anywhere is captured. Both option-surface meta-tests consume this, so
# they share one arm-parser rather than drifting with two independent ones
#
# What it extracts, and what it skips:
#   -j|--jwt)        -> -j, --jwt   short and long both emitted
#   --jwt=*)         -> --jwt       the =* value-form collapses onto the bare long
#   -*)  *)  --)     -> skipped     catch-alls and the -- passthru: no letter follows
#   -[a-zA-Z]?* --*  -> skipped     glob arms (e.g. in _expand_short_opts), not flags
#   append) status)  -> skipped     subcommand arms start with a letter, not with -
#
# A token counts as a flag only if it matches ^--?[a-zA-Z][a-zA-Z0-9-]*$ after the
# =* strip: that admits -x and --long-name and rejects globs, quotes, and a bare --
#
# An arm whose label line carries a `# hidden` comment (e.g. `--print-pool) # hidden
# diagnostic`) is skipped: a deliberately-undocumented option is not part of the
# surface a user is expected to discover, so it is exempt from the self-sufficiency
# checks. This keeps the rest of the script's flags checked, unlike excluding it
_option_flags() {
    awk '
        /^[[:space:]]*case[[:space:]]/       { depth++; next }
        /^[[:space:]]*esac([[:space:]]|;|$)/ { if (depth > 0) depth--; next }
        depth > 0 {
            pos = index($0, ")")
            if (pos == 0) next
            if (substr($0, pos) ~ /#[[:space:]]*hidden/) next
            label = substr($0, 1, pos - 1)
            gsub(/[[:space:]]/, "", label)
            if (label !~ /^-/) next
            n = split(label, toks, "|")
            for (i = 1; i <= n; i++) {
                t = toks[i]
                sub(/=\*$/, "", t)
                if (t ~ /^--?[a-zA-Z][a-zA-Z0-9-]*$/) print t
            }
        }
    ' "$1"  | sort -u
}

# Emit each short option paired with the long form(s) it shares a case arm with,
# one line per short: "<short>\t<long>[,<long>...]", sorted by short. A short whose
# long field is empty has NO long form in any arm -- the violation the pairing
# invariant flags (every short must have a long; the reverse is not required, so
# long-only options are simply not emitted here). Sibling to _option_flags: same
# arm-scan and same skip rules, but preserves the short<->long correspondence that
# _option_flags's flat set discards. Aggregates across arms, so a short paired in
# any arm counts as paired. Skips `# hidden`-marked arms, same as _option_flags
_option_pairs() {
    awk '
        /^[[:space:]]*case[[:space:]]/       { depth++; next }
        /^[[:space:]]*esac([[:space:]]|;|$)/ { if (depth > 0) depth--; next }
        depth > 0 {
            pos = index($0, ")")
            if (pos == 0) next
            if (substr($0, pos) ~ /#[[:space:]]*hidden/) next
            label = substr($0, 1, pos - 1)
            gsub(/[[:space:]]/, "", label)
            if (label !~ /^-/) next
            ns = 0; nl = 0
            n = split(label, toks, "|")
            for (i = 1; i <= n; i++) {
                t = toks[i]
                sub(/=\*$/, "", t)
                if (t !~ /^--?[a-zA-Z][a-zA-Z0-9-]*$/) continue
                if (t ~ /^--/) longs[++nl] = t; else shorts[++ns] = t
            }
            for (i = 1; i <= ns; i++) {
                s = shorts[i]
                if (!(s in seen_short)) { seen_short[s] = 1; order[++norder] = s; joined[s] = "" }
                for (j = 1; j <= nl; j++) {
                    k = s SUBSEP longs[j]
                    if (k in seen_pair) continue
                    seen_pair[k] = 1
                    joined[s] = (joined[s] == "" ? longs[j] : joined[s] "," longs[j])
                }
            }
        }
        END {
            for (i = 1; i <= norder; i++) print order[i] "\t" joined[order[i]]
        }
    ' "$1" | sort
}

# --- test runner ---

run_tests() {
    # Refuse if the test file was sourced rather than executed. Test files are
    # execute-only: run_tests ends in exit, so sourcing one into an interactive
    # shell would close that shell. When sourced, ${BASH_SOURCE[1]} (the test
    # file that called run_tests) differs from $0 (the interpreter, "bash").
    # Mirrors the source/execute guard that dbg and prompt use for the inverse
    # mistake. This is the first thing run_tests does; nothing in any test file
    # runs between sourcing and this check
    if [ "${BASH_SOURCE[1]}" != "$0" ]; then
        echo "[ERR][test-helpers] ${BASH_SOURCE[1]##*/} must be executed, not sourced. Run: bash ${BASH_SOURCE[1]##*/}" >&2
        return 2
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -v) _VERBOSE=1 ;;
        esac
        shift
    done

    local root; root="$(mktemp -d 2>/dev/null)" || root="$(mktemp -d -t test 2>/dev/null)"
    if [ ! -d "$root" ]; then
        echo "[ERR][test-helpers] Failed to create temp directory" >&2
        exit 1
    fi

    # Filter to non-exported test_ functions only (avoids picking up
    # exported test_* functions from the user's environment)
    local tests; tests="$(declare -F | awk '$2 == "-f" && $3 ~ /^test_/ {print $3}')"
    if [ -z "$tests" ]; then
        echo "[ERR][test-helpers] No test_ functions found" >&2
        rm -rf "$root"
        exit 1
    fi

    # Use fd 3 so scripts that check [ -t 0 ] or read from stdin
    # don't consume the test name list
    local test_name
    while IFS= read -r test_name <&3; do
        TEST_DIR="$root/$test_name"
        SHIM_DIR="$TEST_DIR/shims"
        mkdir -p "$TEST_DIR" "$SHIM_DIR"

        if declare -f write_shims >/dev/null 2>&1; then
            write_shims
        fi

        "$test_name"
    done 3<<< "$tests"

    rm -rf "$root"

    local total=$((_PASS + _FAIL))
    echo ""
    echo "$total assertions: $_PASS passed, $_FAIL failed"

    if [ "$_FAIL" -ne 0 ]; then
        exit 1
    fi
    exit 0
}
