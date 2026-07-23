#!/bin/bash
# notify.test.sh - Tests for notify
# shellcheck source-path=SCRIPTDIR disable=SC2329,SC2016

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../notify"
DOC_UNDER_TEST="$SCRIPT_DIR/../docs/notify.md"

# --- helpers ---

get_osascript_log() { cat "$TEST_DIR/osascript.log" 2>/dev/null; }
get_osascript_message() { cat "$TEST_DIR/osascript.message" 2>/dev/null; }
get_osascript_title() { cat "$TEST_DIR/osascript.title" 2>/dev/null; }
get_osascript_subtitle() { cat "$TEST_DIR/osascript.subtitle" 2>/dev/null; }
get_osascript_sound() { cat "$TEST_DIR/osascript.sound" 2>/dev/null; }
get_say_args() { cat "$TEST_DIR/say.args" 2>/dev/null; }
get_say_text() { cat "$TEST_DIR/say.text" 2>/dev/null; }

# --- shims ---

write_shims() {
    # osascript shim: log each argument separately to preserve embedded newlines
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
exit "${OSASCRIPT_RC:-0}"
SHIM
    chmod +x "$SHIM_DIR/osascript"

    # say shim: log each argument on its own line and capture synthesized text
    cat > "$SHIM_DIR/say" <<'SHIM'
#!/bin/bash
: > "$TEST_DIR/say.args"
for arg in "$@"; do printf '%s\n' "$arg" >> "$TEST_DIR/say.args"; done
cat > "$TEST_DIR/say.text"
exit "${SAY_RC:-0}"
SHIM
    chmod +x "$SHIM_DIR/say"

    # basename shim keeps dependency-isolation tests functional with a narrow PATH
    cat > "$SHIM_DIR/basename" <<'SHIM'
#!/bin/bash
value="$1"
printf '%s\n' "${value##*/}"
SHIM
    chmod +x "$SHIM_DIR/basename"

    mkdir -p "$TEST_DIR/Library/Sounds"
    : > "$TEST_DIR/Library/Sounds/MySound.wav"
}

# --- notification behavior ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help mentions osascript" "osascript"
    assert_stdout_contains "help mentions say" "say"
    assert_stdout_contains "help mentions macOS only" "macOS only"
}

test_help_short_form() {
    run_script -h
    assert_rc "short help exits 0" 0
    assert_stdout_contains "short help has SYNOPSIS" "SYNOPSIS"
}

test_help_surface_stays_focused() {
    run_script --help
    assert_stdout_not_contains "help omits in-script versioning" "--version"
    assert_stdout_not_contains "help omits speech templating" "--say-format"
    assert_stdout_not_contains "help omits audio encoding" "--data-format"
    assert_stdout_not_contains "help omits device routing" "--audio-device"
    assert_stdout_not_contains "help omits file-input sugar" "--file"
}

test_no_embedded_version_state() {
    if grep -Eq '^[[:space:]]*(readonly[[:space:]]+)?[A-Za-z_]*VERSION=' "$UNDER_TEST"; then
        _fail "script contains embedded version state"
    else
        _ok "script has no embedded version state"
    fi

    if grep -q -- '--version' "$UNDER_TEST"; then
        _fail "script accepts an in-script version option"
    else
        _ok "script has no in-script version option"
    fi
}

test_documentation_covers_help_surface() {
    assert_file_exists "markdown documentation exists" "$DOC_UNDER_TEST"
    run_script --help

    local header
    local header_options
    local help_options
    local doc_options
    local header_environment
    local help_environment
    local doc_environment
    local missing_header_options
    local missing_doc_options
    local missing_header_environment
    local missing_doc_environment
    header="$(sed -n '1,/^_notify() (/p' "$UNDER_TEST")"
    header_options="$(printf '%s\n' "$header" | grep -Eo -- '--[a-z][a-z-]*' | sort -u)"
    help_options="$(grep -Eo -- '--[a-z][a-z-]*' "$TEST_DIR/stdout" | sort -u)"
    doc_options="$(grep -Eo -- '--[a-z][a-z-]*' "$DOC_UNDER_TEST" | sort -u)"
    header_environment="$(printf '%s\n' "$header" | grep -Eo 'NOTIFY_[A-Z_]+' | sort -u)"
    help_environment="$(grep -Eo 'NOTIFY_[A-Z_]+' "$TEST_DIR/stdout" | sort -u)"
    doc_environment="$(grep -Eo 'NOTIFY_[A-Z_]+' "$DOC_UNDER_TEST" | sort -u)"
    missing_header_options="$(comm -23 <(printf '%s\n' "$header_options") <(printf '%s\n' "$help_options"))"
    missing_doc_options="$(comm -23 <(printf '%s\n' "$help_options") <(printf '%s\n' "$doc_options"))"
    missing_header_environment="$(comm -23 <(printf '%s\n' "$header_environment") <(printf '%s\n' "$help_environment"))"
    missing_doc_environment="$(comm -23 <(printf '%s\n' "$help_environment") <(printf '%s\n' "$doc_environment"))"

    assert_eq "header options are covered by help" "$missing_header_options" ""
    assert_eq "help options are covered by markdown" "$missing_doc_options" ""
    assert_eq "header environment is covered by help" "$missing_header_environment" ""
    assert_eq "help environment is covered by markdown" "$missing_doc_environment" ""
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

test_sound_short_form() {
    run_script -S "Ping" "Test"
    assert_rc "sound short" 0
    assert_eq "sound set" "$(get_osascript_sound)" "Ping"
}

test_sound_short_glued() {
    run_script -SPing "Test"
    assert_rc "sound short glued" 0
    assert_eq "glued value splits via value-opts" "$(get_osascript_sound)" "Ping"
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

test_bundled_short_flags() {
    run_script -pn "Build complete"
    assert_rc "bundled short flags" 0
    assert_file_exists "bundled mode displays notification" "$TEST_DIR/osascript.log"
    assert_file_exists "bundled mode invokes say" "$TEST_DIR/say.args"
    assert_eq "bundled no-sound is honored" "$(get_osascript_sound)" ""
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

test_all_notification_options_combined() {
    run_script -t "Title" -s "Sub" --sound "Ping" "Message"
    assert_rc "all notification options" 0
    assert_eq "title" "$(get_osascript_title)" "Title"
    assert_eq "subtitle" "$(get_osascript_subtitle)" "Sub"
    assert_eq "sound" "$(get_osascript_sound)" "Ping"
    assert_eq "message" "$(get_osascript_message)" "Message"
}

test_list_sounds() {
    HOME="$TEST_DIR" run_script --list-sounds
    assert_rc "list sounds exits cleanly" 0
    assert_stdout_contains "list sounds finds user sound" "MySound"
}

test_list_sounds_short_form() {
    HOME="$TEST_DIR" run_script -l
    assert_rc "list sounds short exits cleanly" 0
    assert_stdout_contains "short list finds user sound" "MySound"
}

test_missing_message() {
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
    assert_stderr_contains "usage hint uses canonical backticks" 'Run `notify -h` for usage'
    assert_stderr_not_contains "usage hint omits straight quotes" "Run 'notify -h' for usage"
}

test_osascript_not_found() {
    rm -f "$SHIM_DIR/osascript"
    env PATH="$SHIM_DIR" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" "Test" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "osascript missing" 3
    assert_stderr_contains "error message" "osascript is required"
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

# --- speech behavior ---

test_say_combined() {
    run_script --say "Build complete"
    assert_rc "combined notification and speech" 0
    assert_file_exists "combined mode displays notification" "$TEST_DIR/osascript.log"
    assert_file_exists "combined mode invokes say" "$TEST_DIR/say.args"
    assert_eq "combined mode speaks message" "$(get_say_text)" "Build complete"
}

test_say_combined_short_form() {
    run_script -p "Build complete"
    assert_rc "combined short form" 0
    assert_file_exists "combined short displays notification" "$TEST_DIR/osascript.log"
    assert_file_exists "combined short invokes say" "$TEST_DIR/say.args"
}

test_say_only() {
    run_script --say-only "Tea is ready"
    assert_rc "say-only" 0
    if [ -f "$TEST_DIR/osascript.log" ]; then
        _fail "say-only displayed a notification"
    else
        _ok "say-only skips notification"
    fi
    assert_eq "say-only speaks message" "$(get_say_text)" "Tea is ready"
}

test_say_only_short_form() {
    run_script -P "Tea is ready"
    assert_rc "say-only short form" 0
    if [ -f "$TEST_DIR/osascript.log" ]; then
        _fail "say-only short displayed a notification"
    else
        _ok "say-only short skips notification"
    fi
    assert_file_exists "say-only short invokes say" "$TEST_DIR/say.args"
}

test_speech_option_implies_combined_mode() {
    run_script -v Alex "Hello"
    assert_rc "speech option implies combined mode" 0
    assert_file_exists "implied mode displays notification" "$TEST_DIR/osascript.log"
    assert_file_exists "implied mode invokes say" "$TEST_DIR/say.args"
}

test_notify_only_overrides_environment() {
    NOTIFY_SAY=yes run_script --notify-only "Quiet"
    assert_rc "notify-only overrides NOTIFY_SAY" 0
    assert_file_exists "notify-only displays notification" "$TEST_DIR/osascript.log"
    if [ -f "$TEST_DIR/say.args" ]; then
        _fail "notify-only invoked say"
    else
        _ok "notify-only skips say"
    fi
}

test_say_after_notify_only_wins() {
    run_script --notify-only --say "Audible"
    assert_rc "say after notify-only" 0
    assert_file_exists "last mode displays notification" "$TEST_DIR/osascript.log"
    assert_file_exists "last mode enables speech" "$TEST_DIR/say.args"
}

test_notify_only_after_say_wins() {
    run_script --say --notify-only "Quiet"
    assert_rc "notify-only after say" 0
    assert_file_exists "last notify mode displays notification" "$TEST_DIR/osascript.log"
    if [ -f "$TEST_DIR/say.args" ]; then
        _fail "last notify mode invoked say"
    else
        _ok "last notify mode disables speech"
    fi
}

test_notify_only_rejects_speech_options() {
    run_script --notify-only -v Alex "Quiet"
    assert_rc "notify-only rejects speech options" 2
    assert_stderr_contains "notify-only conflict diagnostic" "Speech options cannot be combined"
}

test_false_notify_say_value_stays_silent() {
    NOTIFY_SAY=no run_script "Quiet"
    assert_rc "false NOTIFY_SAY value" 0
    if [ -f "$TEST_DIR/say.args" ]; then
        _fail "false NOTIFY_SAY value invoked say"
    else
        _ok "false NOTIFY_SAY value skips say"
    fi
}

test_mixed_case_notify_say_value_enables_speech() {
    NOTIFY_SAY=tRuE run_script "Audible"
    assert_rc "mixed-case NOTIFY_SAY value" 0
    assert_file_exists "mixed-case value displays notification" "$TEST_DIR/osascript.log"
    assert_file_exists "mixed-case value enables speech" "$TEST_DIR/say.args"
}

test_say_voice_and_rate() {
    run_script --say-only -v Samantha -r 190 "Hello"
    assert_rc "voice and rate" 0
    assert_eq "voice and rate forwarded" "$(get_say_args)" $'-v\nSamantha\n-r\n190'
}

test_say_voice_and_rate_equals_forms() {
    run_script --say-only --voice=Alex --rate=175 "Hello"
    assert_rc "voice and rate equals forms" 0
    assert_eq "equals forms forwarded" "$(get_say_args)" $'-v\nAlex\n-r\n175'
}

test_say_environment_defaults() {
    NOTIFY_SAY=yes NOTIFY_VOICE=Alex NOTIFY_RATE=175 run_script "Hello"
    assert_rc "say environment defaults" 0
    assert_eq "environment voice and rate" "$(get_say_args)" $'-v\nAlex\n-r\n175'
}

test_say_text_override() {
    run_script --say --say-text "Spoken text" "Displayed text"
    assert_rc "say-text override" 0
    assert_eq "override is spoken" "$(get_say_text)" "Spoken text"
    assert_eq "original is displayed" "$(get_osascript_message)" "Displayed text"
}

test_say_text_equals_form() {
    run_script --say-only --say-text="Spoken text" "Displayed text"
    assert_rc "say-text equals form" 0
    assert_eq "equals-form override is spoken" "$(get_say_text)" "Spoken text"
}

test_say_rate_validation() {
    run_script --say -r fast "Hello"
    assert_rc "invalid speech rate" 2
    assert_stderr_contains "rate diagnostic" "positive integer"
}

test_missing_speech_option_values() {
    run_script --voice
    assert_rc "missing voice value" 2
    assert_stderr_contains "missing voice diagnostic" "--voice requires a value"

    run_script --rate
    assert_rc "missing rate value" 2
    assert_stderr_contains "missing rate diagnostic" "--rate requires a value"

    run_script --say-text
    assert_rc "missing say-text value" 2
    assert_stderr_contains "missing say-text diagnostic" "--say-text requires a value"
}

test_list_voices() {
    run_script --list-voices
    assert_rc "list voices" 0
    assert_eq "voice discovery query" "$(get_say_args)" $'-v\n?'
}

test_list_voices_short_form() {
    run_script -L
    assert_rc "list voices short" 0
    assert_eq "short voice discovery query" "$(get_say_args)" $'-v\n?'
}

test_list_voices_requires_say() {
    rm -f "$SHIM_DIR/say"
    env PATH="$SHIM_DIR:/bin" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" --list-voices >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "list voices without say" 3
    assert_stderr_contains "list voices dependency diagnostic" "say is required"
}

test_list_action_conflict() {
    run_script --list-voices --list-sounds
    assert_rc "list action conflict" 2
    assert_stderr_contains "list conflict diagnostic" "Only one list option"
}

test_list_action_rejects_message() {
    run_script --list-voices "Hello"
    assert_rc "list action rejects message" 2
    assert_stderr_contains "list message diagnostic" "do not accept a message"
}

test_say_not_found() {
    rm -f "$SHIM_DIR/say"
    env PATH="$SHIM_DIR:/bin" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" --say "Hello" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "say missing" 3
    assert_stderr_contains "say missing diagnostic" "say is required"
}

test_say_only_does_not_require_osascript() {
    rm -f "$SHIM_DIR/osascript"
    env PATH="$SHIM_DIR:/bin" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" --say-only "Hello" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "say-only without osascript" 0
    assert_eq "say-only still speaks" "$(get_say_text)" "Hello"
}

test_notification_only_does_not_require_say() {
    rm -f "$SHIM_DIR/say"
    env PATH="$SHIM_DIR:/bin" TEST_DIR="$TEST_DIR" \
        /bin/bash "$UNDER_TEST" "Hello" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "notification-only without say" 0
    assert_eq "notification-only still displays" "$(get_osascript_message)" "Hello"
}

test_say_failure_status() {
    SAY_RC=9 run_script --say-only "Hello"
    assert_rc "say status propagated" 9
}

test_say_background_reports_launch_status() {
    SAY_RC=9 run_script --say-only -b "Hello"
    assert_rc "background reports launch status" 0
}

test_say_background_long_form() {
    SAY_RC=9 run_script --say-only --background "Hello"
    assert_rc "long background reports launch status" 0
}

test_both_outputs_are_attempted_on_failure() {
    OSASCRIPT_RC=8 SAY_RC=9 run_script --say "Hello"
    assert_rc "notification failure takes precedence" 8
    assert_file_exists "say attempted after notification failure" "$TEST_DIR/say.args"
}

# --- run ---

run_tests "$@"
