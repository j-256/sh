#!/bin/bash
# meta-canonical-letters.test.sh - Verify behavior-scoped canonical-letter binding
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
#
# Enforces the CONVENTIONS.md canonical-letter rule, lexical half only:
#   if a script's option set contains --force, it must contain -f;
#   if it contains --dry-run, it must contain -n.
# Behavior-scoped: a script WITHOUT the behavior may use the letter freely
# (curl-timing -n/--num, daemons -f/--follow), so absence of --force/--dry-run
# is never a violation. The semantic case (is --fresh a force?) is a review
# obligation, not checkable here.
#
# EXCLUDE pin-dns: it has --dry-run but reserves -n for curl's --netrc (its
# whole short space is curl passthrough), so its dry-run is legitimately
# long-only -- the reserved-namespace exception. Without the exclusion the
# membership check below false-positives "--dry-run without -n". (render-md
# needs no exclusion here: it is #!/usr/bin/env node, so the _is_bash_script
# shebang filter drops it before EXCLUDE is consulted.)
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Identical bash-script filter to the other meta-tests
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

# Scripts to skip: pin-dns has --dry-run but reserves -n for curl passthru
# (--netrc). Hardcoded here so this test is self-contained. The concurrent
# session is landing a shared _META_OPT_EXCLUDE="pin-dns" base in
# test-helpers.sh; once it lands, converge to EXCLUDE="$_META_OPT_EXCLUDE"
# (a follow-up, not a blocker -- see plan tail)
EXCLUDE=" pin-dns "
_is_excluded() { case "$EXCLUDE" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Echo a violation string if the flag set has a canonical long without its
# canonical short. Empty output = conformant
_canonical_violations() {
    local flags
    flags=" $(_option_flags "$1" | tr '\n' ' ') "
    case "$flags" in *" --force "*)
        case "$flags" in *" -f "*) : ;; *) echo "--force without -f" ;; esac ;;
    esac
    case "$flags" in *" --dry-run "*)
        case "$flags" in *" -n "*) : ;; *) echo "--dry-run without -n" ;; esac ;;
    esac
}

test_all_scripts_canonical_binding() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s
        s="$(basename "$script")"
        _is_excluded "$s" && continue
        local hits
        hits="$(_canonical_violations "$script")"
        assert_eq "$s: canonical long implies canonical short" "$hits" ""
    done
}

run_tests "$@"
