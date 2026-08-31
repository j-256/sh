#!/bin/bash
# meta-dry-run-format.test.sh - Verify dry-run plans use the canonical result prefix
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md
#
# Enforces the CONVENTIONS.md "Dry-run output" rule: every script that parses
# --dry-run defines the exact stdout helper
#   _dry() { printf '[DRY][%s] %s\n' "$SCRIPT_NAME" "$*"; }
# and routes counterfactual action headers through it. The direct-emitter check
# rejects the legacy banners and bare Would lines retired by the fleet sweep
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."
FLEET_DIR="$(_fleet_dir "$REPO_DIR")"

_has_dry_run() {
    local flags; flags=" $(_option_flags "$1" | tr '\n' ' ') "
    case "$flags" in
        *" --dry-run "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Print one violation per missing helper or direct legacy emitter
# Empty output means the script conforms
_dry_run_violations() {
    local script="$1"
    _has_dry_run "$script" || return 0

    local canonical="_dry() { printf '[DRY][%s] %s\n' \"\$SCRIPT_NAME\" \"\$*\"; }"
    if ! grep -Fq "$canonical" "$script"; then
        echo "missing canonical _dry stdout helper"
    fi

    awk '
        /^[[:space:]]*#/ { next }
        /_dry/ { next }
        /(echo|printf|_info|_warn|_error)/ && /(\[DRY RUN\]|DRY RUN:|Dry run:|[Ww]ould[[:space:]])/ {
            printf "%d: direct dry-run output bypasses _dry\n", NR
        }
    ' "$script"
}

test_all_dry_run_scripts_use_canonical_output() {
    local script
    for script in "$FLEET_DIR"/*; do
        _is_bash_script "$script" || continue
        _has_dry_run "$script" || continue
        local name; name="$(basename "$script")"
        local hits; hits="$(_dry_run_violations "$script")"
        assert_eq "$name: dry-run plans use [DRY][\$SCRIPT_NAME] on stdout" "$hits" ""
    done
}

# Prove both halves of the detector bite before the real fleet is conformant
test_detector_catches_synthetic_legacy_output() {
    local bad="$TEST_DIR/bad"
    {
        echo '#!/bin/bash'
        echo 'case "$1" in'
        echo '    -n|--dry-run) dry=1 ;;'
        echo 'esac'
        echo 'echo "[DRY RUN] would delete $path"'
    } > "$bad"
    local bad_hits; bad_hits="$(_dry_run_violations "$bad")"
    assert_eq "detector flags missing helper and direct legacy output" "$bad_hits" "missing canonical _dry stdout helper
5: direct dry-run output bypasses _dry"

    local wrong_route="$TEST_DIR/wrong-route"
    {
        echo '#!/bin/bash'
        echo 'case "$1" in'
        echo '    -n|--dry-run) dry=1 ;;'
        echo 'esac'
        echo '_dry() { printf '\''[DRY][%s] %s\n'\'' "$SCRIPT_NAME" "$*" >&2; }'
    } > "$wrong_route"
    local route_hits; route_hits="$(_dry_run_violations "$wrong_route")"
    assert_eq "detector rejects stderr helper" "$route_hits" "missing canonical _dry stdout helper"

    local good="$TEST_DIR/good"
    {
        echo '#!/bin/bash'
        echo 'case "$1" in'
        echo '    -n|--dry-run) dry=1 ;;'
        echo 'esac'
        echo '_dry() { printf '\''[DRY][%s] %s\n'\'' "$SCRIPT_NAME" "$*"; }'
        echo '_dry "Would delete: '\''$path'\''"'
    } > "$good"
    local good_hits; good_hits="$(_dry_run_violations "$good")"
    assert_eq "detector passes canonical helper usage" "$good_hits" ""
}

run_tests "$@"
