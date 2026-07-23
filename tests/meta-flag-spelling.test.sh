#!/bin/bash
# meta-flag-spelling.test.sh - Verify options use canonical, not legacy, spellings
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
#
# Enforces the CONVENTIONS.md "Canonical short options" spelling rule: the
# dry-run long flag is spelled `--dry-run` (hyphenated), never `--dryrun`.
# `meta-canonical-letters` checks the letter BINDING (--dry-run implies -n) but
# keys off the literal string `--dry-run`, so a script spelling it `--dryrun` is
# invisible to it. This test closes that exact gap: it flags the non-canonical
# spelling itself.
#
# Reuses the shared `_option_flags` extractor (see test-helpers.sh), so a banned
# spelling counts only when it is a real parsed option (a case-arm label), not a
# substring in a comment or a string. The banned set is a small "bad=good" table;
# add a row when a new non-canonical spelling is retired.
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Test bash scripts only: shebang must be /bin/bash or /usr/bin/env bash.
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

# Excluded scripts: just the shared base ($_META_OPT_EXCLUDE, currently empty)
EXCLUDE="$_META_OPT_EXCLUDE"
_is_excluded() { case " $EXCLUDE " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Banned non-canonical option spellings, as space-separated "bad=good" pairs.
# A spelling is banned when the fleet has standardized on the canonical form and
# the legacy one must not creep back (e.g. --dryrun for the hyphenated --dry-run)
_BANNED_SPELLINGS="--dryrun=--dry-run"

# Echo "uses <bad>; canonical is <good>" for each banned spelling the script's
# option surface (via _option_flags) contains. Empty output = conformant
_spelling_violations() {
    local flags; flags=" $(_option_flags "$1" | tr '\n' ' ') "
    local pair
    local bad
    local good
    for pair in $_BANNED_SPELLINGS; do
        bad="${pair%%=*}"
        good="${pair#*=}"
        case "$flags" in
            *" $bad "*) echo "uses $bad; canonical is $good" ;;
        esac
    done
}

# The fleet assertion: no script's parsed option surface uses a banned spelling
test_no_script_uses_noncanonical_spelling() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        local hits; hits="$(_spelling_violations "$script")"
        assert_eq "$s: options use canonical spelling (no --dryrun etc.)" "$hits" ""
    done
}

# Self-check: prove the detector bites. The fleet assertion is vacuously green
# over this repo (no --dryrun present), so without this a broken detector would
# pass silently. Feeds a synthetic script with a --dryrun) parse arm and asserts
# it is flagged, then a --dry-run) arm and asserts silence
test_detector_catches_synthetic_dryrun() {
    local bad="$TEST_DIR/bad"
    {
        echo '#!/bin/bash'
        echo 'while [ $# -gt 0 ]; do'
        echo '    case "$1" in'
        echo '        -n|--dryrun) dry=1; shift ;;'
        echo '    esac'
        echo 'done'
    } > "$bad"
    local bad_hits; bad_hits="$(_spelling_violations "$bad")"
    assert_eq "detector flags --dryrun" "$bad_hits" "uses --dryrun; canonical is --dry-run"

    local good="$TEST_DIR/good"
    {
        echo '#!/bin/bash'
        echo 'while [ $# -gt 0 ]; do'
        echo '    case "$1" in'
        echo '        -n|--dry-run) dry=1; shift ;;'
        echo '    esac'
        echo 'done'
    } > "$good"
    local good_hits; good_hits="$(_spelling_violations "$good")"
    assert_eq "detector passes --dry-run" "$good_hits" ""
}

run_tests "$@"
