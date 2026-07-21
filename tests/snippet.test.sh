#!/bin/bash
# snippet.test.sh - Tests for snippet
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../snippet"

# --- helpers ---

write_test_file() {
    local filename="$1"
    cat > "$TEST_DIR/$filename" <<'EOF'
header line
START marker here
first line of snippet
second line of snippet
third line of snippet
END marker here
footer line
EOF
}

write_multifile_test() {
    cat > "$TEST_DIR/file1.txt" <<'EOF'
file1 header
START A
file1 content
END A
file1 footer
EOF
    cat > "$TEST_DIR/file2.txt" <<'EOF'
file2 header
START A
file2 content
END A
file2 footer
EOF
}

# --- shims ---

write_shims() {
    # sed shim: pass through to real sed
    cat > "$SHIM_DIR/sed" <<'SHIM'
#!/bin/bash
exec /usr/bin/sed "$@"
SHIM
    chmod +x "$SHIM_DIR/sed"

    # cat shim: pass through to real cat
    cat > "$SHIM_DIR/cat" <<'SHIM'
#!/bin/bash
exec /bin/cat "$@"
SHIM
    chmod +x "$SHIM_DIR/cat"

    # awk shim: pass through to real awk
    cat > "$SHIM_DIR/awk" <<'SHIM'
#!/bin/bash
exec /usr/bin/awk "$@"
SHIM
    chmod +x "$SHIM_DIR/awk"

    # tput shim: return empty (non-terminal)
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"

    # basename shim: pass through to real basename
    cat > "$SHIM_DIR/basename" <<'SHIM'
#!/bin/bash
exec /usr/bin/basename "$@"
SHIM
    chmod +x "$SHIM_DIR/basename"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has Usage" "Usage:"
    assert_stdout_contains "help has -s option" "-s, --start"
    assert_stdout_contains "help has -e option" "-e, --end"
    assert_stdout_contains "help has -f option" "-f, --trim-first"
    assert_stdout_contains "help has -l option" "-l, --trim-last"
    assert_stdout_contains "help has -t option" "-t, --trim"
}

test_no_args_shows_help() {
    run_script
    assert_rc "no args exits 0" 0
    assert_stdout_contains "no args shows usage" "Usage:"
}

test_missing_start_pattern() {
    write_test_file "test.txt"
    run_script "$TEST_DIR/test.txt"
    assert_rc "missing start" 2
    assert_stderr_contains "error message" "[ERR][snippet] Start pattern is required"
}

test_missing_start_value() {
    write_test_file "test.txt"
    run_script -s
    assert_rc "missing -s value" 2
    assert_stderr_contains "error message" "[ERR][snippet] Missing value for '-s'"
}

test_missing_end_value() {
    write_test_file "test.txt"
    run_script -s "START" -e
    assert_rc "missing -e value" 2
    assert_stderr_contains "error message" "[ERR][snippet] Missing value for '-e'"
}

test_missing_trim_first_value() {
    write_test_file "test.txt"
    run_script -s "START" -f
    assert_rc "missing -f value" 2
    assert_stderr_contains "error message" "[ERR][snippet] Missing value for '-f'"
}

test_missing_trim_last_value() {
    write_test_file "test.txt"
    run_script -s "START" -l
    assert_rc "missing -l value" 2
    assert_stderr_contains "error message" "[ERR][snippet] Missing value for '-l'"
}

test_missing_trim_value() {
    write_test_file "test.txt"
    run_script -s "START" -t
    assert_rc "missing -t value" 2
    assert_stderr_contains "error message" "[ERR][snippet] Missing value for '-t'"
}

test_unknown_option() {
    write_test_file "test.txt"
    run_script -s "START" --unknown-flag "$TEST_DIR/test.txt"
    assert_rc "unknown option" 2
    assert_stderr_contains "error message" "[ERR][snippet] Unknown argument '--unknown-flag'"
}

test_basic_start_end() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" "$TEST_DIR/test.txt"
    assert_rc "basic" 0
    assert_stdout_contains "includes start marker" "START marker here"
    assert_stdout_contains "includes first line" "first line of snippet"
    assert_stdout_contains "includes end marker" "END marker here"
    assert_stdout_not_contains "excludes header" "header line"
    assert_stdout_not_contains "excludes footer" "footer line"
}

test_start_only_to_end() {
    write_test_file "test.txt"
    run_script -s "START" "$TEST_DIR/test.txt"
    assert_rc "start only" 0
    assert_stdout_contains "includes start" "START marker here"
    assert_stdout_contains "includes content" "third line of snippet"
    assert_stdout_contains "includes end marker" "END marker here"
    assert_stdout_contains "includes footer" "footer line"
}

test_trim_first() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -f 1 "$TEST_DIR/test.txt"
    assert_rc "trim first" 0
    assert_stdout_not_contains "excludes start" "START marker here"
    assert_stdout_contains "includes first content" "first line of snippet"
}

test_trim_last() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -l 1 "$TEST_DIR/test.txt"
    assert_rc "trim last" 0
    assert_stdout_contains "includes start" "START marker here"
    assert_stdout_contains "includes content" "third line of snippet"
    assert_stdout_not_contains "excludes end" "END marker here"
}

test_trim_both() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -t 1 "$TEST_DIR/test.txt"
    assert_rc "trim both" 0
    assert_stdout_not_contains "excludes start" "START marker here"
    assert_stdout_contains "includes middle" "second line of snippet"
    assert_stdout_not_contains "excludes end" "END marker here"
}

test_trim_first_and_last_separate() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -f 1 -l 2 "$TEST_DIR/test.txt"
    assert_rc "trim f and l" 0
    assert_stdout_not_contains "excludes start" "START marker here"
    assert_stdout_contains "includes first" "first line of snippet"
    assert_stdout_contains "includes second" "second line of snippet"
    assert_stdout_not_contains "excludes third" "third line of snippet"
}

test_trim_more_than_available() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -f 3 -l 3 "$TEST_DIR/test.txt"
    assert_rc "overtrim" 0
    assert_eq "empty output" "$(get_stdout)" ""
}

test_trim_zero() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -f 0 -l 0 "$TEST_DIR/test.txt"
    assert_rc "zero trim" 0
    assert_stdout_contains "includes all" "START marker here"
    assert_stdout_contains "includes end" "END marker here"
}

test_stdin_input() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" < "$TEST_DIR/test.txt"
    assert_rc "stdin" 0
    assert_stdout_contains "includes start" "START marker here"
    assert_stdout_contains "includes content" "first line of snippet"
}

test_multiple_files() {
    write_multifile_test
    run_script -s "START" -e "END" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt"
    assert_rc "multiple files" 0
    assert_stdout_contains "has file1 content" "file1 content"
    assert_stdout_contains "has file2 content" "file2 content"
}

test_long_option_start() {
    write_test_file "test.txt"
    run_script --start "START" -e "END" "$TEST_DIR/test.txt"
    assert_rc "long start" 0
    assert_stdout_contains "works" "first line of snippet"
}

test_long_option_end() {
    write_test_file "test.txt"
    run_script -s "START" --end "END" "$TEST_DIR/test.txt"
    assert_rc "long end" 0
    assert_stdout_contains "works" "first line of snippet"
}

test_long_option_trim_first() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" --trim-first 1 "$TEST_DIR/test.txt"
    assert_rc "long trim-first" 0
    assert_stdout_not_contains "excludes start" "START marker here"
}

test_long_option_trim_last() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" --trim-last 1 "$TEST_DIR/test.txt"
    assert_rc "long trim-last" 0
    assert_stdout_not_contains "excludes end" "END marker here"
}

test_long_option_trim() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" --trim 1 "$TEST_DIR/test.txt"
    assert_rc "long trim" 0
    assert_stdout_not_contains "excludes start" "START marker here"
    assert_stdout_not_contains "excludes end" "END marker here"
}

test_double_dash_separator() {
    write_test_file "test.txt"
    run_script -s "START" -e "END" -- "$TEST_DIR/test.txt"
    assert_rc "double dash" 0
    assert_stdout_contains "works" "first line of snippet"
}

test_pattern_not_found() {
    write_test_file "test.txt"
    run_script -s "NOTFOUND" "$TEST_DIR/test.txt"
    assert_rc "pattern not found" 0
    assert_eq "empty output" "$(get_stdout)" ""
}

test_start_found_end_not_found() {
    write_test_file "test.txt"
    run_script -s "START" -e "NOTFOUND" "$TEST_DIR/test.txt"
    assert_rc "end not found" 0
    assert_stdout_contains "includes start" "START marker here"
    assert_stdout_contains "includes footer" "footer line"
}

test_file_not_found() {
    run_script -s "START" "$TEST_DIR/nonexistent.txt"
    # sed exits 0 when file not found but writes error to stderr
    assert_rc "file not found" 0
    assert_eq "empty output" "$(get_stdout)" ""
}

test_regex_pattern() {
    cat > "$TEST_DIR/regex.txt" <<'EOF'
header
START123
content line
END456
footer
EOF
    run_script -s "START[0-9]" -e "END[0-9]" "$TEST_DIR/regex.txt"
    assert_rc "regex" 0
    assert_stdout_contains "matches regex start" "START123"
    assert_stdout_contains "includes content" "content line"
    assert_stdout_contains "matches regex end" "END456"
}

test_multiple_matches() {
    cat > "$TEST_DIR/multi.txt" <<'EOF'
START
first block
END
middle
START
second block
END
footer
EOF
    run_script -s "START" -e "END" "$TEST_DIR/multi.txt"
    assert_rc "multiple matches" 0
    assert_stdout_contains "first block" "first block"
    assert_stdout_contains "second block" "second block"
    assert_stdout_not_contains "excludes middle" "middle"
}

test_trim_with_multiple_matches() {
    cat > "$TEST_DIR/multi.txt" <<'EOF'
START
line1
line2
END
START
line3
line4
END
EOF
    run_script -s "START" -e "END" -f 1 -l 1 "$TEST_DIR/multi.txt"
    assert_rc "trim multi" 0
    # Trimming affects entire output, not per-block
    # First START is trimmed, last END is trimmed
    assert_stdout_contains "has line1" "line1"
    assert_stdout_contains "has line2" "line2"
    assert_stdout_contains "has line3" "line3"
    assert_stdout_contains "has line4" "line4"
    assert_stdout_contains "has middle START" "START"
    assert_stdout_contains "has middle END" "END"
}

test_single_line_snippet() {
    cat > "$TEST_DIR/single.txt" <<'EOF'
before
MARKER
after
EOF
    run_script -s "MARKER" -e "MARKER" "$TEST_DIR/single.txt"
    assert_rc "single line" 0
    assert_stdout_contains "has marker" "MARKER"
    assert_stdout_not_contains "no before" "before"
    # sed includes lines after first match until end pattern, so 'after' is excluded
}

test_special_chars_in_pattern() {
    cat > "$TEST_DIR/special.txt" <<'EOF'
header
[START]
content
[END]
footer
EOF
    run_script -s '\[START\]' -e '\[END\]' "$TEST_DIR/special.txt"
    assert_rc "special chars" 0
    assert_stdout_contains "matches" "[START]"
    assert_stdout_contains "content" "content"
}

# --- run ---

run_tests "$@"
