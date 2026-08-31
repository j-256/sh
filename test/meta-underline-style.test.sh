#!/bin/bash
# meta-underline-style.test.sh - Verify stdout underlines use the canonical environment gate
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md
#
# Enforces the CONVENTIONS.md "--help" styling rule for every raw underline
# start in the fleet, including underlined stdout text outside help. The style
# variable must start empty, the nearest enclosing condition must use the exact
# TTY/CLICOLOR_FORCE/NO_COLOR gate, and a paired reset must appear in that gate;
# tput underline capabilities are rejected so styling adds no dependency
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."
FLEET_DIR="$(_fleet_dir "$REPO_DIR")"

# Print one violation per non-canonical underline start or tput dependency
# Empty output means the script conforms
_underline_violations() {
    awk '
        function trim(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            return value
        }
        function assignment_var(line, value) {
            value = trim(line)
            sub(/[[:space:]]*=.*/, "", value)
            return value
        }
        function initialized_empty(variable, before,    first, line, value, prefix, rest) {
            first = before - 12
            if (first < 1) first = 1
            prefix = "local " variable "=\"\""
            for (line = before - 1; line >= first; line--) {
                value = trim(lines[line])
                if (index(value, prefix) != 1) continue
                rest = substr(value, length(prefix) + 1)
                if (rest == "" || rest ~ /^[[:space:]]+#/) return 1
            }
            return 0
        }
        function canonical_gate_before(before,    first, line, value) {
            first = before - 12
            if (first < 1) first = 1
            for (line = before - 1; line >= first; line--) {
                value = trim(lines[line])
                if (value == "fi") return 0
                if (value ~ /^if[[:space:]]/)
                    return value == "if { [ -t 1 ] || [ -n \"${CLICOLOR_FORCE:-}\" ]; } && [ -z \"${NO_COLOR:-}\" ]; then"
            }
            return 0
        }
        /^[[:space:]]*#/ { lines[NR] = $0; next }
        { lines[NR] = $0 }
        END {
            for (line = 1; line <= NR; line++) {
                value = trim(lines[line])
                if (value ~ /tput[[:space:]]+(smul|rmul)/)
                    printf "line %d: tput underline styling is not allowed\n", line

                if (index(value, "\\033[4m") == 0) continue

                variable = assignment_var(value)
                if (!initialized_empty(variable, line))
                    printf "line %d: %s is not initialized to empty\n", line, variable
                if (!canonical_gate_before(line))
                    printf "line %d: underline start lacks canonical stdout style gate\n", line

                reset_line = 0
                last = line + 12
                if (last > NR) last = NR
                for (candidate = line + 1; candidate <= last; candidate++) {
                    candidate_value = trim(lines[candidate])
                    if (candidate_value == "fi") break
                    if (index(candidate_value, "\\033[24m") != 0) {
                        reset_line = candidate
                        break
                    }
                }
                if (!reset_line) {
                    printf "line %d: underline start has no paired reset\n", line
                    continue
                }

                reset_variable = assignment_var(lines[reset_line])
                if (!initialized_empty(reset_variable, line))
                    printf "line %d: %s is not initialized to empty\n", reset_line, reset_variable
            }
        }
    ' "$1"
}

test_all_underlines_use_canonical_stdout_gate() {
    local script
    for script in "$FLEET_DIR"/*; do
        _is_bash_script "$script" || continue
        local name; name="$(basename "$script")"
        local hits; hits="$(_underline_violations "$script")"
        assert_eq "$name: stdout underlines honor CLICOLOR_FORCE and NO_COLOR" "$hits" ""
    done
}

test_detector_catches_synthetic_legacy_styles() {
    local bad="$TEST_DIR/bad"
    {
        echo '#!/bin/bash'
        echo 'local s; [ -t 1 ] && s=$'\''\033[4m'\'''
        echo 'local r; [ -t 1 ] && r=$'\''\033[24m'\'''
    } > "$bad"
    local bad_hits; bad_hits="$(_underline_violations "$bad")"
    assert_contains "detector rejects legacy TTY-only gate" "$bad_hits" "underline start lacks canonical stdout style gate"
    assert_contains "detector requires empty initialization" "$bad_hits" "s is not initialized to empty"

    local tput_style="$TEST_DIR/tput"
    {
        echo '#!/bin/bash'
        echo 's="$(tput smul)"'
        echo 'r="$(tput rmul)"'
    } > "$tput_style"
    local tput_hits; tput_hits="$(_underline_violations "$tput_style")"
    assert_contains "detector rejects tput underline start" "$tput_hits" "tput underline styling is not allowed"

    local wrong_precedence="$TEST_DIR/wrong-precedence"
    {
        echo '#!/bin/bash'
        echo 'local s=""'
        echo 'local r=""'
        echo 'if [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; then'
        echo '    s=$'\''\033[4m'\'''
        echo '    r=$'\''\033[24m'\'''
        echo 'fi'
    } > "$wrong_precedence"
    local precedence_hits; precedence_hits="$(_underline_violations "$wrong_precedence")"
    assert_contains "detector requires NO_COLOR precedence" "$precedence_hits" "underline start lacks canonical stdout style gate"
}

test_detector_accepts_canonical_help_and_palette_blocks() {
    local good="$TEST_DIR/good"
    {
        echo '#!/bin/bash'
        echo 'local s=""'
        echo 'local r=""'
        echo 'if { [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; } && [ -z "${NO_COLOR:-}" ]; then'
        echo '    s=$'\''\033[4m'\'''
        echo '    r=$'\''\033[24m'\'''
        echo 'fi'
    } > "$good"
    local good_hits; good_hits="$(_underline_violations "$good")"
    assert_eq "detector accepts canonical help block" "$good_hits" ""

    local palette="$TEST_DIR/palette"
    {
        echo '#!/bin/bash'
        echo 'local color=""'
        echo 'local smul=""'
        echo 'local rmul=""'
        echo 'if { [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; } && [ -z "${NO_COLOR:-}" ]; then'
        echo '    color=$'\''\033[36m'\'''
        echo '    smul=$'\''\033[4m'\'''
        echo '    rmul=$'\''\033[24m'\'''
        echo 'fi'
    } > "$palette"
    local palette_hits; palette_hits="$(_underline_violations "$palette")"
    assert_eq "detector accepts a larger canonical palette" "$palette_hits" ""
}

run_tests "$@"
