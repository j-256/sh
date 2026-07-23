#!/bin/bash
# meta-diagnostic-format.test.sh - Verify diagnostic helpers use the canonical prefix
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
#
# Enforces the CONVENTIONS.md "Error Messages" rule: every diagnostic helper
# (_error/_warn/_info/_debug) emits the canonical severity-led, bracket-adjacent
# prefix
#   [ERR][$SCRIPT_NAME] message
# and NOT a legacy shape such as `[ERR] name:` (space + trailing colon) or
# `[name] ERROR:` (name-first, word-severity). The check is POSITIVE: it asserts
# the canonical `[SEV][` token is present in each helper's body, so any legacy
# shape fails regardless of its exact form -- stronger than blacklisting the
# specific legacy shapes seen so far (two distinct ones already exist in the wild).
#
# The structured colored variant (CONVENTIONS "Colored variant") builds its prefix
# in `local PFX_ERR=...` vars, so the literal `[ERR][` never appears in the helper
# body; a `PFX_<SEV>` reference is accepted as canonical (spf is the only such script).
#
# Routing (stdout vs stderr) is NOT checked here. `_info`->stdout is legitimately
# dual-use (a --list mode that keeps stdout clean; program-output helpers), so a
# static routing assertion over-fires. Routing is a review obligation, per CONVENTIONS.
#
# snippets.sh is intentionally NOT checked: the shared `_is_bash_script` filter drops
# its `.sh` name. It is a reference "graveyard" slated for a future holistic rework,
# not an executed script -- policing it now would be churn. This exemption is
# deliberate, not an oversight.
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Test bash scripts only: shebang must be /bin/bash or /usr/bin/env bash.
# Skips the .md/.sh/.json files at the repo root, and any subdirectories.
# Identical to the filter in the other meta-tests
_is_bash_script() {
    local file="$1"
    [ -f "$file" ] || return 1
    case "$(basename "$file")" in *.md|*.sh|*.json) return 1 ;; esac
    local first_line; first_line="$(head -1 "$file")"
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash') return 0 ;;
        *) return 1 ;;
    esac
}

# Bash scripts to skip these checks, as a space-padded membership string
# (e.g. " foo bar "). Empty today: every checked helper conforms
EXCLUDE=" "
_is_excluded() { case "$EXCLUDE" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Echo "helper: reason" for each diagnostic helper in the file whose brace-balanced
# body lacks the canonical [SEV][ token (or the structured-variant PFX_<SEV> ref).
# Empty output = conformant. Handles multi-line helper bodies (e.g. a colored
# _error whose prefix line sits several lines below the `_error() {` opener) by
# accumulating lines until brace depth returns to zero
_prefix_violations() {
    awk '
        function sev_for(n) {
            if (n == "_warn")  return "WRN"
            if (n == "_info")  return "INF"
            if (n == "_debug") return "DBG"
            return "ERR"
        }
        /^[[:space:]]*_(error|warn|info|debug)\(\)/ {
            name = $0; sub(/\(\).*/, "", name); gsub(/[[:space:]]/, "", name)
            sev = sev_for(name)
            body = $0
            o = gsub(/{/, "{", $0); c = gsub(/}/, "}", $0); depth = o - c
            while (depth > 0) {
                if ((getline nxt) <= 0) break
                body = body "\n" nxt
                o = gsub(/{/, "{", nxt); c = gsub(/}/, "}", nxt); depth += o - c
            }
            canon = "[" sev "]["
            pfx   = "PFX_" sev
            if (index(body, canon) == 0 && index(body, pfx) == 0)
                printf "%s: missing canonical [%s][ prefix\n", name, sev
        }
    ' "$1"
}

# The fleet assertion: every script that defines a diagnostic helper uses the
# canonical prefix. Scripts with no helper are simply skipped (empty violations)
test_all_helpers_use_canonical_prefix() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        local hits; hits="$(_prefix_violations "$script")"
        assert_eq "$s: all diagnostic helpers use canonical [SEV][\$SCRIPT_NAME] prefix" "$hits" ""
    done
}

# Self-check: prove the detector actually bites, so it can't silently rot to a
# no-op once the fleet is clean. Feeds a known-BAD helper (legacy `[ERR] name:`
# shape) and asserts it is flagged, then a known-GOOD helper and asserts silence.
# Unlike the other meta-tests (which trust the detector against the real fleet),
# this test's real-fleet assertion is vacuously green over this repo, so the
# self-check is what guarantees the detector is not inert here
test_detector_catches_synthetic_legacy() {
    local bad="$TEST_DIR/bad.sh"
    {
        echo '#!/bin/bash'
        echo '_error() { echo "[ERR] mytool: $*" >&2; }'
    } > "$bad"
    local bad_hits; bad_hits="$(_prefix_violations "$bad")"
    assert_eq "detector flags legacy [SEV] name: prefix" "$bad_hits" "_error: missing canonical [ERR][ prefix"

    local good="$TEST_DIR/good.sh"
    {
        echo '#!/bin/bash'
        echo '_error() { echo "[ERR][$SCRIPT_NAME] $*" >&2; }'
    } > "$good"
    local good_hits; good_hits="$(_prefix_violations "$good")"
    assert_eq "detector passes canonical prefix" "$good_hits" ""
}

run_tests "$@"
