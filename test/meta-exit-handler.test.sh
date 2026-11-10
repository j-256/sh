#!/bin/bash
# meta-exit-handler.test.sh - Verify production exit handlers under errexit
#
# Execute each script footer with a controlled wrapper result so failure
# cleanup is checked without running the script body or its external actions
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- fixture code expands only in the child shell

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."
FLEET_DIR="$(_fleet_dir "$REPO_DIR")"

_write_handler_fixture() {
    local script="$1"
    local declaration; declaration="$(awk '/^_[[:alnum:]_]+\(\) [({]/ { print; exit }' "$script")"
    WRAPPER="${declaration%%\(*}"
    STATUS_VAR="$(sed -n 's/^eval "unset \(__[[:alnum:]_]*\); exit .*/\1/p' "$script")"
    [ -n "$WRAPPER" ] && [ -n "$STATUS_VAR" ] || return 1
    {
        printf '%s\n' '#!/bin/bash' "$declaration" '    return "$1"'
        case "$declaration" in
            *'(') printf '%s\n' ')' ;;
            *'{') printf '%s\n' '}' ;;
            *) return 1 ;;
        esac
        awk -v wrapper="$WRAPPER" '
            $0 == wrapper " \"$@\"" || $0 == "if " wrapper " \"$@\"; then" { found = 1 }
            found { print }
            END { if (!found) exit 1 }
        ' "$script"
    } > "$TEST_DIR/handler"
}

test_sourced_exit_handlers_clean_up_before_returning_failure() {
    local script
    for script in "$FLEET_DIR"/* "$SCRIPT_DIR/test-runner.sh"; do
        [ "$script" = "$SCRIPT_DIR/test-runner.sh" ] || _is_bash_script "$script" || continue
        local name; name="$(basename "$script")"
        if ! _write_handler_fixture "$script"; then
            _fail "$name: cannot extract exit handler"
            continue
        fi
        local status
        local mode
        for status in 0 2 7; do
            for mode in unhandled handled; do
                /bin/bash -ec '
                    fixture=$1
                    wrapper=$2
                    status_var=$3
                    requested=$4
                    mode=$5
                    trap '\''
                        saved=$?
                        if declare -F "$wrapper" >/dev/null; then
                            printf "leaked wrapper: %s\n" "$wrapper" >&2
                            exit 99
                        fi
                        if declare -p "$status_var" >/dev/null 2>&1; then
                            printf "leaked status variable: %s\n" "$status_var" >&2
                            exit 99
                        fi
                        case "$-" in *e*) ;; *) printf "errexit disabled\n" >&2; exit 99 ;; esac
                        printf "cleanup:%s\n" "$saved"
                        exit "$saved"
                    '\'' EXIT
                    if [ "$mode" = handled ]; then
                        if . "$fixture" "$requested"; then actual=0; else actual=$?; fi
                        printf "returned:%s\n" "$actual"
                    else
                        . "$fixture" "$requested"
                    fi
                ' bash "$TEST_DIR/handler" "$WRAPPER" "$STATUS_VAR" "$status" "$mode" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
                local actual_rc=$?
                local expected_rc="$status"
                local expected_output="cleanup:$status"
                if [ "$mode" = handled ]; then
                    expected_rc=0
                    expected_output="$(printf 'returned:%s\ncleanup:0' "$status")"
                fi
                local label="$name: $mode source status $status under errexit"
                assert_eq "$label exit" "$actual_rc" "$expected_rc"
                assert_eq "$label cleanup" "$(get_stdout)" "$expected_output"
                assert_eq "$label stderr" "$(get_stderr)" ""
            done
        done
    done
}

test_executed_exit_handlers_preserve_status() {
    local script
    for script in "$FLEET_DIR"/* "$SCRIPT_DIR/test-runner.sh"; do
        [ "$script" = "$SCRIPT_DIR/test-runner.sh" ] || _is_bash_script "$script" || continue
        local name; name="$(basename "$script")"
        if ! _write_handler_fixture "$script"; then
            _fail "$name: cannot extract exit handler"
            continue
        fi
        local status
        for status in 0 2 7; do
            /bin/bash -e "$TEST_DIR/handler" "$status" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
            assert_eq "$name: executed handler preserves $status" "$?" "$status"
            /bin/bash -e -s -- "$status" < "$TEST_DIR/handler" > "$TEST_DIR/stdout" 2> "$TEST_DIR/stderr"
            assert_eq "$name: stdin handler preserves $status" "$?" "$status"
            assert_eq "$name: stdin handler has no top-level return error" "$(get_stderr)" ""
        done
    done
}

run_tests "$@"
