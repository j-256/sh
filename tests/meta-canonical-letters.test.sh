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
# Authored exceptions use a `# meta:canonical-exempt` marker, not a whole-script skip:
# pin-dns has --dry-run but reserves -n for curl's --netrc (its whole short space
# is curl passthrough), so its dry-run is legitimately long-only -- the
# reserved-namespace exception. Its --dry-run arm carries `# meta:canonical-exempt`,
# which _canonical_exempt_longs reads so the membership check below skips exactly
# that long while still checking every other option on pin-dns. (render-md needs
# no handling here: it is #!/usr/bin/env node, so the _is_bash_script shebang
# filter drops it before the loop reaches it.)
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
    local first_line; first_line="$(head -1 "$file")"
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash') return 0 ;;
        *) return 1 ;;
    esac
}

# Excluded scripts: just the shared base ($_META_OPT_EXCLUDE, currently empty).
# Authored long-only exceptions are handled per-option with `# meta:canonical-exempt`
# markers (see _canonical_exempt_longs), not by excluding a whole script here.
EXCLUDE="$_META_OPT_EXCLUDE"
_is_excluded() { case " $EXCLUDE " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Long options whose case-arm label line carries a `# meta:canonical-exempt` comment,
# one per line. Such a long is an AUTHORED exception to the canonical-short rule
# (e.g. pin-dns's --dry-run, whose -n is reserved for curl's --netrc -- the
# reserved-namespace exception in CONVENTIONS "Canonical short options"). The arm
# stays in the option surface (_option_flags still emits it, so surface-parity
# still checks --dry-run is in -h); only the "needs its canonical short" check is
# waived. Sibling of _option_flags's `# meta:not-options`, but per-arm and this-test-only
_canonical_exempt_longs() {
    awk '
        {
            pos = index($0, ")")
            if (pos == 0) next
            if (substr($0, pos) !~ /#[[:space:]]*meta:canonical-exempt/) next
            label = substr($0, 1, pos - 1)
            gsub(/[[:space:]]/, "", label)
            n = split(label, toks, "|")
            for (i = 1; i <= n; i++) {
                t = toks[i]
                sub(/=\*$/, "", t)
                if (t ~ /^--[a-zA-Z][a-zA-Z0-9-]*$/) print t
            }
        }
    ' "$1" | sort -u
}

# Echo a violation string if the flag set has a canonical long without its
# canonical short. A long marked `# meta:canonical-exempt` in the script is waived
# (see _canonical_exempt_longs). Empty output = conformant
_canonical_violations() {
    local flags; flags=" $(_option_flags "$1" | tr '\n' ' ') "
    local exempt; exempt=" $(_canonical_exempt_longs "$1" | tr '\n' ' ') "
    case "$flags" in *" --force "*)
        case "$exempt" in *" --force "*) : ;; *)
            case "$flags" in *" -f "*) : ;; *) echo "--force without -f" ;; esac ;;
        esac ;;
    esac
    case "$flags" in *" --dry-run "*)
        case "$exempt" in *" --dry-run "*) : ;; *)
            case "$flags" in *" -n "*) : ;; *) echo "--dry-run without -n" ;; esac ;;
        esac ;;
    esac
}

test_all_scripts_canonical_binding() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        local hits; hits="$(_canonical_violations "$script")"
        assert_eq "$s: canonical long implies canonical short [if this long is a genuine reserved-namespace/collision exception (its short belongs to another tool), mark its arm \`# meta:canonical-exempt\` -- do not pad _META_OPT_EXCLUDE; see TESTING.md]" "$hits" ""
    done
}

run_tests "$@"
