#!/bin/bash
# meta-wrapper-guard.test.sh - Enforce guarded outer-wrapper status capture
#
# The outer call must finish cleanup before propagating a failure to an
# errexit caller, so every script uses the same conditional status capture
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- fixture code expands only in the child shell

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."
FLEET_DIR="$(_fleet_dir "$REPO_DIR")"

_guard_violations() {
    awk '
        /^_[[:alnum:]_]+\(\) [({]/ && wrapper == "" {
            wrapper = $0
            sub(/\(\).*/, "", wrapper)
        }
        /^eval "unset __[[:alnum:]_]+; exit / {
            status = $0
            sub(/^eval "unset /, "", status)
            sub(/;.*/, "", status)
        }
        { text = text $0 "\n" }
        END {
            guard = "if " wrapper " \"$@\"; then\n    " status "=0\nelse\n    " status "=$?\nfi\nunset -f " wrapper "\n"
            if (wrapper == "" || status == "" || index(text, guard) == 0)
                print "missing canonical guarded wrapper status capture"
            if (wrapper != "" && index("\n" text, "\n" wrapper " \"$@\"\n") != 0)
                print "unguarded outer-wrapper invocation"
        }
    ' "$1"
}

test_all_outer_wrappers_capture_status_conditionally() {
    local script
    for script in "$FLEET_DIR"/* "$SCRIPT_DIR/test-runner.sh"; do
        [ "$script" = "$SCRIPT_DIR/test-runner.sh" ] || _is_bash_script "$script" || continue
        local name; name="$(basename "$script")"
        local hits; hits="$(_guard_violations "$script")"
        assert_eq "$name: guarded wrapper status capture" "$hits" ""
    done
}

test_detector_rejects_broken_status_capture() {
    local fixture="$TEST_DIR/fixture"
    local variant
    for variant in canonical bare inverted overwritten mismatched; do
        {
            printf '%s\n' '#!/bin/bash' '_fixture() ( return "$1" )'
            case "$variant" in
                canonical)
                    printf '%s\n' 'if _fixture "$@"; then' '    __fixture_rc=0' 'else' '    __fixture_rc=$?' 'fi'
                    ;;
                bare)
                    printf '%s\n' '_fixture "$@"' '__fixture_rc=$?'
                    ;;
                inverted)
                    printf '%s\n' 'if ! _fixture "$@"; then' '    __fixture_rc=$?' 'else' '    __fixture_rc=0' 'fi'
                    ;;
                overwritten)
                    printf '%s\n' 'if _fixture "$@"; then' '    __fixture_rc=0' 'else' '    :' '    __fixture_rc=$?' 'fi'
                    ;;
                mismatched)
                    printf '%s\n' 'if _fixture "$@"; then' '    __fixture_rc=0' 'else' '    __other_rc=$?' 'fi'
                    ;;
            esac
            printf '%s\n' 'unset -f _fixture' 'eval "unset __fixture_rc; exit $__fixture_rc"'
        } > "$fixture"
        local hits; hits="$(_guard_violations "$fixture")"
        if [ "$variant" = canonical ]; then
            assert_eq "detector accepts canonical guard" "$hits" ""
        else
            assert_contains "detector rejects $variant capture" "$hits" 'missing canonical guarded wrapper status capture'
        fi
    done
}

run_tests "$@"
