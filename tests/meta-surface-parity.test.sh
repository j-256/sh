#!/bin/bash
# meta-surface-parity.test.sh - Verify -h documents every option the parser accepts
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
#
# Enforces the CONVENTIONS.md Self-sufficiency rule -- a script must be usable
# from the file alone, so every option the parser accepts must be discoverable in
# -h (see CONVENTIONS.md "Self-sufficiency"). Two invariants:
#
#   1. code subset of -h: every flag the argument parser matches (via
#      _option_flags) appears somewhere in --help output. -h/--help themselves are
#      exempt -- they are universal (every script supports them by the
#      source/execute convention) and are the one pair a user always tries first.
#   2. pairing: every short option has a long form (via _option_pairs). The
#      reverse is not required -- long-only options are legitimate.
#
# Scope: this checks the code-vs--h surface. The header-vs--h-vs-.md parity (the
# other half of the Self-sufficiency rule's meta-testable claim) is a documented
# follow-up, not yet enforced here.
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
    local first_line
    first_line="$(head -1 "$file")"
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash') return 0 ;;
        *) return 1 ;;
    esac
}

# Excluded scripts: the shared base ($_META_OPT_EXCLUDE = pin-dns, an extractor
# limitation) plus this test's own additions. Each addition names its reason so
# the skip reads as tracked debt, not a silent hole -- see TESTING.md.
#
# TODO(surface-parity): the additions below are tracked violations to resolve,
# then remove from this list:
#   snippet             --start-pattern/--end-pattern/--trim-start/--trim-end are
#                       aliases of documented flags; decide drop (per the dropped
#                       --token alias precedent) vs. document, then un-exclude
EXCLUDE="$_META_OPT_EXCLUDE snippet"
_is_excluded() { case " $EXCLUDE " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Flag tokens documented anywhere in a script's --help output. Matches -x and
# --long tokens whose preceding char is not alphanumeric, so prose hyphenation
# ("well-formed") is not mistaken for a flag
_help_flags() {
    "$1" --help 2>&1 | awk '{ s=$0
        while (match(s, /--?[a-zA-Z][a-zA-Z0-9-]*/)) {
            tok = substr(s, RSTART, RLENGTH)
            before = (RSTART == 1) ? "" : substr(s, RSTART - 1, 1)
            if (before !~ /[a-zA-Z0-9]/) print tok
            s = substr(s, RSTART + RLENGTH)
        } }' | sort -u
}

test_every_option_is_documented_in_help() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        local code; code="$(_option_flags "$script" | grep -vE '^(-h|--help)$')"
        local help; help="$(_help_flags "$script")"
        local missing; missing="$(comm -23 <(printf '%s\n' "$code") <(printf '%s\n' "$help") | tr '\n' ' ')"
        missing="${missing% }"
        assert_eq "$s: every parsed option appears in -h" "$missing" ""
    done
}

test_every_short_has_a_long() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        local unpaired; unpaired="$(_option_pairs "$script" | awk -F'\t' '$2 == "" { print $1 }' | tr '\n' ' ')"
        unpaired="${unpaired% }"
        assert_eq "$s: every short option has a long form" "$unpaired" ""
    done
}

run_tests "$@"
