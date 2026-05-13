#!/bin/bash
# find-cc-tool-output.test.sh - Tests for find-cc-tool-output
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../find-cc-tool-output"

# --- helpers ---

# The script reads ~/.claude/projects/. Override HOME to a per-test fake tree
# so tests don't depend on or touch the real one
run_script() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" HOME="$TEST_DIR/home" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Build a JSONL transcript with the given lines. Each line is a JSON object;
# nothing else is added
make_jsonl() {
    local path="$1"; shift
    mkdir -p "$(dirname "$path")"
    : > "$path"
    local line
    for line in "$@"; do
        printf '%s\n' "$line" >> "$path"
    done
}

# tool_result entry containing $1 as text. Wraps it in the
# user/message/content/tool_result envelope used by Claude Code transcripts
tool_result() {
    local text="$1"
    local escaped
    escaped=$(printf '%s' "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":[{"type":"text","text":%s}]}]}}' "$escaped"
}

custom_title() {
    local title="$1"
    local escaped
    escaped=$(printf '%s' "$title" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    printf '{"type":"custom-title","customTitle":%s}' "$escaped"
}

# Set up a sample project tree at $HOME/.claude/projects/. Two project dirs,
# each with one or two transcripts containing distinguishable tool_result text
setup_fixture() {
    local proj_a="$TEST_DIR/home/.claude/projects/-Users-test-projA"
    local proj_b="$TEST_DIR/home/.claude/projects/-Users-test-projB"

    # projA / session 1 (no custom title): two tool_results, one with the
    # target substring "ALPHA-MARKER", one without
    make_jsonl "$proj_a/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl" \
        '{"type":"user","message":{"role":"user","content":"hi"}}' \
        "$(tool_result $'first body\nALPHA-MARKER full payload here\nsecond line')" \
        "$(tool_result 'unrelated payload')"

    # projA / session 2 (has custom title "session-two"): one tool_result with
    # the target substring
    make_jsonl "$proj_a/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl" \
        "$(custom_title 'session-two')" \
        "$(tool_result $'ALPHA-MARKER second hit\ndifferent body')"

    # projB / session 3 (custom title "session-three"): one tool_result that
    # does NOT contain ALPHA-MARKER, and one that contains BETA-MARKER
    make_jsonl "$proj_b/cccccccc-cccc-cccc-cccc-cccccccccccc.jsonl" \
        "$(custom_title 'session-three')" \
        "$(tool_result 'no marker here')" \
        "$(tool_result $'BETA-MARKER unique body\nrest of output')"
}

# --- test cases ---

test_help_exits_zero() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has substring arg" "substring"
    assert_stdout_contains "help has --session" "--session"
    assert_stdout_contains "help has --dir" "--dir"
    assert_stdout_contains "help has --all" "--all"
}

test_missing_substring_exits_2() {
    setup_fixture
    run_script
    assert_rc "missing substring exits 2" 2
    assert_stderr_contains "missing substring error" "Must provide a substring"
}

test_unknown_flag_exits_2() {
    setup_fixture
    run_script --bogus foo
    assert_rc "unknown flag exits 2" 2
    assert_stderr_contains "unknown flag error" "Unknown argument"
}

test_no_matches_exits_1() {
    setup_fixture
    run_script "ZZZZ-NEVER-PRESENT"
    assert_rc "no matches exits 1" 1
    assert_stderr_contains "no matches message" "No matches"
}

test_unique_match_prints_full_body() {
    setup_fixture
    run_script "BETA-MARKER"
    assert_rc "unique match exits 0" 0
    assert_stdout_contains "prints body" "BETA-MARKER unique body"
    assert_stdout_contains "prints subsequent line" "rest of output"
}

test_multi_match_lists_and_exits_2() {
    setup_fixture
    run_script "ALPHA-MARKER"
    assert_rc "multi-match exits 2" 2
    assert_stderr_contains "multi-match summary" "2 matches"
    assert_stderr_contains "lists session-two title" "session-two"
    # Listing output must NOT print the full bodies on stdout
    assert_stdout_not_contains "no body on stdout" "ALPHA-MARKER full payload"
}

test_all_dumps_every_match() {
    setup_fixture
    run_script --all "ALPHA-MARKER"
    assert_rc "--all exits 0" 0
    assert_stdout_contains "dumps first body" "ALPHA-MARKER full payload"
    assert_stdout_contains "dumps second body" "ALPHA-MARKER second hit"
}

test_session_friendly_name_filters() {
    setup_fixture
    run_script --session "session-two" "ALPHA-MARKER"
    assert_rc "session filter exits 0" 0
    assert_stdout_contains "prints session-two body" "ALPHA-MARKER second hit"
    assert_stdout_not_contains "skips other session" "ALPHA-MARKER full payload"
}

test_session_uuid_filters() {
    setup_fixture
    run_script --session "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" "ALPHA-MARKER"
    assert_rc "uuid filter exits 0" 0
    assert_stdout_contains "prints uuid'd body" "ALPHA-MARKER full payload"
    assert_stdout_not_contains "skips session-two" "ALPHA-MARKER second hit"
}

test_session_unknown_exits_1() {
    setup_fixture
    run_script --session "no-such-session" "ALPHA-MARKER"
    assert_rc "unknown session exits 1" 1
    assert_stderr_contains "unknown session error" "No session named"
}

test_dir_filters_by_encoded_basename() {
    setup_fixture
    # Encoded basenames start with `-`, so the `=` form is required (see CAVEATS
    # in --help): the space form would feed `-Users-...` into the bundled-short-
    # flag preprocessor
    run_script --dir=-Users-test-projB "BETA-MARKER"
    assert_rc "dir filter exits 0" 0
    assert_stdout_contains "prints projB body" "BETA-MARKER unique body"
}

test_dir_filters_by_absolute_path() {
    setup_fixture
    # /Users/test/projB encodes to -Users-test-projB
    run_script --dir "/Users/test/projB" "BETA-MARKER"
    assert_rc "abs-path dir filter exits 0" 0
    assert_stdout_contains "prints projB body" "BETA-MARKER unique body"
}

test_dir_unknown_exits_1() {
    setup_fixture
    run_script --dir=-no-such-dir "ALPHA-MARKER"
    assert_rc "unknown dir exits 1" 1
    assert_stderr_contains "unknown dir error" "Project directory not found"
}

test_session_value_required() {
    setup_fixture
    run_script --session
    assert_rc "missing session value exits 2" 2
    assert_stderr_contains "missing session error" "--session requires a value"
}

test_dir_value_required() {
    setup_fixture
    run_script --dir
    assert_rc "missing dir value exits 2" 2
    assert_stderr_contains "missing dir error" "--dir requires a value"
}

test_short_flags_bundle() {
    setup_fixture
    # -av should expand to -a -v (both flag-only, neither in value-opts)
    run_script -av "ALPHA-MARKER"
    assert_rc "bundled short flags exit 0" 0
    assert_stdout_contains "dumps both bodies" "ALPHA-MARKER full payload"
    assert_stdout_contains "dumps second body" "ALPHA-MARKER second hit"
}

test_session_eq_form() {
    setup_fixture
    run_script --session=session-two "ALPHA-MARKER"
    assert_rc "--session= form exits 0" 0
    assert_stdout_contains "uses eq form" "ALPHA-MARKER second hit"
}

test_missing_projects_dir_exits_1() {
    # No fixture set up: $HOME/.claude/projects/ does not exist
    mkdir -p "$TEST_DIR/home"
    run_script "anything"
    assert_rc "missing projects dir exits 1" 1
    assert_stderr_contains "error mentions projects dir" "does not exist"
}

# --- run ---

run_tests "$@"
