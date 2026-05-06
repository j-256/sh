#!/bin/bash
# prompt.test.sh - Tests for prompt
# shellcheck source-path=SCRIPTDIR disable=SC2329
#
# prompt must be sourced (not executed) to do its job -- setting a variable in
# the caller's shell. Most tests use run_script_sourced_capture to source prompt
# in a subshell, feed input on stdin, and capture the result variable.
#
# The interactive TTY path (raw-mode char-at-a-time reading with ghost
# placeholder rendering) is not exercised here: the test subshell has no
# controlling terminal, so prompt takes its non-TTY fallback branch every time.
# That branch covers "prints prompt, reads a line, applies default" -- the
# testable contract. Raw-mode behavior (backspace, placeholder clearing,
# ESC-sequence filtering) has to be verified by hand at a real terminal.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../prompt"

# --- test cases ---

test_help_long() {
    run_script_sourced --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help mentions sourcing" "sourced"
    assert_stdout_contains "help mentions %DEFAULT%" "%DEFAULT%"
}

test_help_short() {
    run_script_sourced -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_executed_rejected() {
    # Running prompt directly (not sourced) should fail with a clear error.
    run_script
    assert_rc "executed exits 2" 2
    assert_stderr_contains "explains requirement" "Must be sourced"
    assert_stderr_contains "refers to help" "Run \`prompt -h\` for usage"
}

test_executed_help_long() {
    # --help is the exception: it works even when executed, so a stranger
    # running `prompt --help` actually gets help instead of the rejection.
    run_script --help
    assert_rc "executed --help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help states sourced requirement" "sourced"
}

test_executed_help_short() {
    run_script -h
    assert_rc "executed -h exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help states sourced requirement" "sourced"
}

test_sourced_with_no_args_shows_help() {
    # Sourcing with no args can't mean anything useful, so show help and exit 0.
    run_script_sourced
    assert_rc "no-args sourced exits 0" 0
    assert_stdout_contains "no-args sourced shows NAME section" "NAME"
    assert_stdout_contains "no-args sourced shows SYNOPSIS" "SYNOPSIS"
}

test_captures_input() {
    printf 'Alice\n' | run_script_sourced_capture "NAME" NAME "What is your name? " "Anonymous"
    assert_rc "captures input exits 0" 0
    assert_captured "NAME got stdin value" NAME "Alice"
}

test_prints_prompt_text() {
    printf 'x\n' | run_script_sourced_capture "NAME" NAME "Enter name: " "default"
    assert_rc "prints prompt exits 0" 0
    assert_stdout_contains "prompt text rendered" "Enter name:"
}

test_default_on_empty_input() {
    # Just pressing Enter should fall back to the default value.
    printf '\n' | run_script_sourced_capture "ANSWER" ANSWER "Continue? " "yes"
    assert_rc "empty input exits 0" 0
    assert_captured "default used when input empty" ANSWER "yes"
}

test_default_on_closed_stdin() {
    # read returning EOF (no input at all) should also yield the default.
    run_script_sourced_capture "ANSWER" ANSWER "Continue? " "no" </dev/null
    assert_rc "closed stdin exits 0" 0
    assert_captured "default used when stdin closed" ANSWER "no"
}

test_empty_default_empty_input() {
    # No default + empty input -> empty result, still rc 0.
    printf '\n' | run_script_sourced_capture "EMPTY" EMPTY "Input: "
    assert_rc "empty default exits 0" 0
    assert_captured "empty string captured" EMPTY ""
}

test_special_chars_preserved() {
    # Inputs containing spaces and shell metachars survive read + eval round-trip.
    printf 'hello world & friends\n' | run_script_sourced_capture "MSG" MSG "Say: " "hi"
    assert_rc "special chars exit 0" 0
    assert_captured "special chars preserved" MSG "hello world & friends"
}

test_underscore_variable_name() {
    # Lowercase + underscores + digits -- a typical caller identifier form.
    printf 'ok\n' | run_script_sourced_capture "my_var_1" my_var_1 "q: " "fallback"
    assert_rc "underscore varname exits 0" 0
    assert_captured "underscore varname set" my_var_1 "ok"
}

test_input_overrides_default() {
    # When stdin provides input, the default must be ignored.
    printf 'user-picked\n' | run_script_sourced_capture "PICK" PICK "q: " "unused-default"
    assert_rc "override exits 0" 0
    assert_captured "input wins over default" PICK "user-picked"
}

test_no_local_shadowing_input() {
    # `_input` was a local inside __prompt__main pre-rename. A caller passing
    # `_input` as the destination varname would have had their value silently
    # eaten. After the prefix rename, all locals are __prompt__-prefixed, so
    # `_input` is just a regular caller name and gets set normally.
    printf 'value-via-_input\n' | run_script_sourced_capture "_input" _input "q: " "default"
    assert_rc "_input as varname exits 0" 0
    assert_captured "_input gets the user input, not shadowed" _input "value-via-_input"
}

test_no_local_shadowing_ch() {
    # `_ch` was the inner read loop's per-char local. Same shadowing class
    # as `_input` -- caller-supplied `_ch` must reach the caller's shell.
    printf 'value-via-_ch\n' | run_script_sourced_capture "_ch" _ch "q: " "default"
    assert_rc "_ch as varname exits 0" 0
    assert_captured "_ch gets the user input, not shadowed" _ch "value-via-_ch"
}

# --- run ---

run_tests "$@"
