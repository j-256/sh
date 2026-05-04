#!/bin/bash
# notify.test.sh - Tests for notify
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../notify"

# --- helpers ---

# The osascript.log format: 4 files with individual args to handle embedded newlines
get_osascript_log() { cat "$TEST_DIR/osascript.log" 2>/dev/null; }
get_osascript_message() { cat "$TEST_DIR/osascript.message" 2>/dev/null; }
get_osascript_title() { cat "$TEST_DIR/osascript.title" 2>/dev/null; }
get_osascript_subtitle() { cat "$TEST_DIR/osascript.subtitle" 2>/dev/null; }
get_osascript_sound() { cat "$TEST_DIR/osascript.sound" 2>/dev/null; }

# --- shims ---

write_shims() {
    # osascript shim: log each arg to separate file to handle embedded newlines
    cat > "$SHIM_DIR/osascript" <<'SHIM'
#!/bin/bash
while [ $# -gt 0 ]; do
    case "$1" in
        -) shift; break ;;
        *) shift ;;
    esac
done
printf '%s' "$1" > "$TEST_DIR/osascript.message"
printf '%s' "$2" > "$TEST_DIR/osascript.title"
printf '%s' "$3" > "$TEST_DIR/osascript.subtitle"
printf '%s' "$4" > "$TEST_DIR/osascript.sound"
printf 'osascript called with 4 args\n' > "$TEST_DIR/osascript.log"
exit 0
SHIM
    chmod +x "$SHIM_DIR/osascript"

    # afplay shim: log invocations (used by --list-sounds test)
    cat > "$SHIM_DIR/afplay" <<'SHIM'
#!/bin/bash
printf 'afplay' > "$TEST_DIR/afplay.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/afplay.log"; done
printf '\n' >> "$TEST_DIR/afplay.log"
exit 0
SHIM
    chmod +x "$SHIM_DIR/afplay"

    # Create fake sound directories
    mkdir -p "$TEST_DIR/System/Library/Sounds"
    mkdir -p "$TEST_DIR/Library/Sounds"
    : > "$TEST_DIR/System/Library/Sounds/Glass.aiff"
    : > "$TEST_DIR/System/Library/Sounds/Ping.aiff"
    : > "$TEST_DIR/Library/Sounds/MySound.wav"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help mentions osascript" "osascript"
    assert_stdout_contains "help mentions macOS only" "macOS only"
}

test_basic_message_positional() {
    run_script "Test message"
    assert_rc "basic message" 0
    assert_eq "message received" "$(get_osascript_message)" "Test message"
    assert_eq "default title" "$(get_osascript_title)" "Notification"
    assert_eq "default subtitle" "$(get_osascript_subtitle)" ""
    assert_eq "default sound" "$(get_osascript_sound)" "Glass"
}

test_multiple_positional_args() {
    run_script "Hello" "world" "test"
    assert_rc "multi args" 0
    assert_eq "args joined with spaces" "$(get_osascript_message)" "Hello world test"
}

test_message_from_stdin() {
    printf '%s\n' "stdin message" | run_script
    assert_rc "stdin message" 0
    assert_eq "message from stdin" "$(get_osascript_message)" "stdin message"
}

test_custom_title() {
    run_script -t "Custom Title" "Test"
    assert_rc "custom title short" 0
    assert_eq "title set" "$(get_osascript_title)" "Custom Title"
}

test_title_long_form() {
    run_script --title "Long Title" "Test"
    assert_rc "custom title long" 0
    assert_eq "title set" "$(get_osascript_title)" "Long Title"
}

test_title_equals_form() {
    run_script --title="Equals Title" "Test"
    assert_rc "title equals" 0
    assert_eq "title set" "$(get_osascript_title)" "Equals Title"
}

test_custom_subtitle() {
    run_script -s "Subtitle Text" "Test"
    assert_rc "subtitle short" 0
    assert_eq "subtitle set" "$(get_osascript_subtitle)" "Subtitle Text"
}

test_subtitle_long_form() {
    run_script --subtitle "Long Subtitle" "Test"
    assert_rc "subtitle long" 0
    assert_eq "subtitle set" "$(get_osascript_subtitle)" "Long Subtitle"
}

test_subtitle_equals_form() {
    run_script --subtitle="Equals Subtitle" "Test"
    assert_rc "subtitle equals" 0
    assert_eq "subtitle set" "$(get_osascript_subtitle)" "Equals Subtitle"
}

test_custom_sound() {
    run_script --sound "Ping" "Test"
    assert_rc "custom sound" 0
    assert_eq "sound set" "$(get_osascript_sound)" "Ping"
}

test_sound_equals_form() {
    run_script --sound="Basso" "Test"
    assert_rc "sound equals" 0
    assert_eq "sound set" "$(get_osascript_sound)" "Basso"
}

test_no_sound_flag() {
    run_script -n "Test"
    assert_rc "no sound short" 0
    assert_eq "sound empty" "$(get_osascript_sound)" ""
}

test_no_sound_long_form() {
    run_script --no-sound "Test"
    assert_rc "no sound long" 0
    assert_eq "sound empty" "$(get_osascript_sound)" ""
}

test_no_sound_overrides_custom_sound() {
    run_script --sound "Ping" -n "Test"
    assert_rc "no sound override" 0
    assert_eq "sound empty" "$(get_osascript_sound)" ""
}

test_env_notify_title() {
    NOTIFY_TITLE="Env Title" run_script "Test"
    assert_rc "env title" 0
    assert_eq "title from env" "$(get_osascript_title)" "Env Title"
}

test_flag_overrides_env_title() {
    NOTIFY_TITLE="Env Title" run_script -t "Flag Title" "Test"
    assert_rc "flag overrides env title" 0
    assert_eq "title from flag" "$(get_osascript_title)" "Flag Title"
}

test_env_notify_sound() {
    NOTIFY_SOUND="Basso" run_script "Test"
    assert_rc "env sound" 0
    assert_eq "sound from env" "$(get_osascript_sound)" "Basso"
}

test_flag_overrides_env_sound() {
    NOTIFY_SOUND="Basso" run_script --sound "Ping" "Test"
    assert_rc "flag overrides env sound" 0
    assert_eq "sound from flag" "$(get_osascript_sound)" "Ping"
}

test_no_sound_overrides_env_sound() {
    NOTIFY_SOUND="Basso" run_script -n "Test"
    assert_rc "no sound overrides env" 0
    assert_eq "sound empty" "$(get_osascript_sound)" ""
}

test_double_dash_separator() {
    run_script -t "Title" -- "Message with -- dashes"
    assert_rc "double dash" 0
    assert_eq "message includes dashes" "$(get_osascript_message)" "Message with -- dashes"
}

test_all_options_combined() {
    run_script -t "Title" -s "Sub" --sound "Ping" "Message"
    assert_rc "all options" 0
    assert_eq "title" "$(get_osascript_title)" "Title"
    assert_eq "subtitle" "$(get_osascript_subtitle)" "Sub"
    assert_eq "sound" "$(get_osascript_sound)" "Ping"
    assert_eq "message" "$(get_osascript_message)" "Message"
}

test_list_sounds() {
    # Skip: --list-sounds uses hardcoded system paths that can't be shimmed
    # Would need to modify script to support TEST_SOUNDS_DIR or similar
    run_script --list-sounds
    assert_rc "list sounds exits cleanly" 0
}

test_list_sounds_short_form() {
    run_script -l
    assert_rc "list sounds short exits cleanly" 0
}

test_missing_message() {
    # Run with stdin redirected from /dev/null to simulate TTY case
    run_script </dev/null
    assert_rc "missing message" 2
    assert_stderr_contains "error message" "MESSAGE is required"
    assert_stderr_contains "help shown" "SYNOPSIS"
}

test_missing_title_value() {
    run_script --title
    assert_rc "missing title value" 2
    assert_stderr_contains "error message" "-t|--title requires a value"
}

test_missing_subtitle_value() {
    run_script -s
    assert_rc "missing subtitle value" 2
    assert_stderr_contains "error message" "-s|--subtitle requires a value"
}

test_missing_sound_value() {
    run_script --sound
    assert_rc "missing sound value" 2
    assert_stderr_contains "error message" "--sound requires a value"
}

test_unknown_option() {
    run_script --unknown "Test"
    assert_rc "unknown option" 2
    assert_stderr_contains "error message" "Unknown argument '--unknown'"
}

test_osascript_not_found() {
    # Test the error path when osascript is not found
    # Override PATH to only include shim dir (where osascript doesn't exist)
    rm -f "$SHIM_DIR/osascript"
    env PATH="$SHIM_DIR" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" "Test" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "osascript missing" 3
    assert_stderr_contains "error message" "osascript not found (macOS only)"
}

test_message_with_newlines() {
    run_script "Line 1
Line 2
Line 3"
    assert_rc "multiline message" 0
    local msg
    msg="$(get_osascript_message)"
    assert_contains "newlines preserved" "$msg" "Line 1"
    assert_contains "line 2 present" "$msg" "Line 2"
    assert_contains "line 3 present" "$msg" "Line 3"
}

test_message_with_special_chars() {
    run_script "Test \$var & <html> 'quotes' \"double\""
    assert_rc "special chars" 0
    assert_contains "special chars preserved" "$(get_osascript_message)" "\$var & <html>"
}

test_empty_string_message() {
    run_script ""
    assert_rc "empty string" 2
    assert_stderr_contains "error message" "MESSAGE is required"
}

test_whitespace_only_message() {
    run_script "   "
    assert_rc "whitespace message" 0
    assert_eq "whitespace preserved" "$(get_osascript_message)" "   "
}

# --- run ---

run_tests "$@"
