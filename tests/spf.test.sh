#!/bin/bash
# spf.test.sh - Tests for spf
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../spf"

# --- shims ---
# The dig shim answers TXT (SPF records), A, and AAAA queries from canned
# fixtures keyed by the queried name. Later tasks extend the case arms.
write_shims() {
    cat > "$SHIM_DIR/dig" <<'SHIM'
#!/bin/bash
printf 'dig %s\n' "$*" >> "$TEST_DIR/dig.log"
qtype=""; name=""
for a in "$@"; do
    case "$a" in
        @*|+*) ;;
        TXT|A|AAAA) qtype="$a" ;;
        *) name="$a" ;;
    esac
done
case "$qtype:$name" in
    TXT:example.com)        printf '%s\n' '"v=spf1 ip4:198.51.100.0/24 -all"' ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"
}

# --- test cases ---

test_top_help() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help NAME" "NAME"
    assert_stdout_contains "help lists find" "find"
    assert_stdout_contains "help lists flatten" "flatten"
    assert_stdout_contains "help lists check" "check"
    assert_stdout_contains "help lists tree" "tree"
}

test_no_verb_is_usage_error() {
    run_script
    assert_rc "no verb exits 2" 2
    assert_stderr_contains "names the problem" "verb"
}

test_unknown_verb_is_usage_error() {
    run_script bogus example.com
    assert_rc "unknown verb exits 2" 2
    assert_stderr_contains "echoes the bad verb" "bogus"
}

# --- run ---
run_tests "$@"
