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
    TXT:example.com)
        printf '%s\n' '"v=spf1 ip4:198.51.100.0/24 include:_spf.example.net ~all"' ;;
    TXT:_spf.example.net)
        printf '%s\n' '"v=spf1 ip4:203.0.113.0/24 ip6:2001:db8::/32 -all"' ;;
    TXT:nospf.example)        ;;                                   # no SPF record
    A:mail.example.com)       printf '%s\n' '198.51.100.9' ;;
    AAAA:mail.example.com)    printf '%s\n' '2001:db8::9' ;;
    # cycle: A -> B -> A
    TXT:cyc-a.example)        printf '%s\n' '"v=spf1 include:cyc-b.example -all"' ;;
    TXT:cyc-b.example)        printf '%s\n' '"v=spf1 include:cyc-a.example -all"' ;;
    # diamond: root includes dia-a + dia-b, both include dia-c
    TXT:dia-root.example)     printf '%s\n' '"v=spf1 include:dia-a.example include:dia-b.example -all"' ;;
    TXT:dia-a.example)        printf '%s\n' '"v=spf1 include:dia-c.example -all"' ;;
    TXT:dia-b.example)        printf '%s\n' '"v=spf1 include:dia-c.example -all"' ;;
    TXT:dia-c.example)        printf '%s\n' '"v=spf1 ip4:192.0.2.0/24 -all"' ;;
    # bare a / mx on the apex
    TXT:hosted.example)       printf '%s\n' '"v=spf1 a mx -all"' ;;
    A:hosted.example)         printf '%s\n' '198.51.100.20' ;;
    A:mailhost.hosted.example) printf '%s\n' '198.51.100.30' ;;
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

test_ir_root_and_include() {
    run_script __ir example.com
    assert_rc "ir exits 0" 0
    # root ip4 row, cost 0
    assert_stdout_contains "root ip4" $'0\texample.com\t+\tip4\t198.51.100.0/24\t0'
    # include row, cost 1
    assert_stdout_contains "include row" $'0\texample.com\t+\tinclude\t_spf.example.net\t1'
    # nested ip4 at depth 1
    assert_stdout_contains "nested ip4" $'1\t_spf.example.net\t+\tip4\t203.0.113.0/24\t0'
    # nested ip6 at depth 1
    assert_stdout_contains "nested ip6" $'1\t_spf.example.net\t+\tip6\t2001:db8::/32\t0'
}

test_ir_qualifiers() {
    run_script __ir example.com
    assert_stdout_contains "tilde all from root" $'0\texample.com\t~\tall\t\t0'
}

test_ir_no_record_is_runtime_error() {
    run_script __ir nospf.example
    assert_rc "no record exits 1" 1
    assert_stderr_contains "says no record" "No SPF record"
}

test_ir_cycle_terminates() {
    run_script __ir cyc-a.example
    assert_rc "cycle still exits 0" 0
    # cyc-a includes cyc-b includes cyc-a: the second cyc-a is in the ancestor
    # path, so it is NOT re-walked -> exactly two include rows, no hang.
    assert_eq "two include rows only" \
        "$(get_stdout | awk -F'\t' '$4=="include"' | grep -c .)" "2"
}

test_ir_diamond_counts_twice() {
    run_script __ir dia-root.example
    assert_rc "diamond exits 0" 0
    # dia-c reached via dia-a AND dia-b -> its include row appears TWICE
    # (no global dedup), so check's lookup count sees both.
    assert_eq "dia-c included twice" \
        "$(get_stdout | awk -F'\t' '$4=="include" && $5=="dia-c.example"' | grep -c .)" "2"
    # but dia-c's leaf ip4 also appears twice in the IR (flatten dedups later)
    assert_eq "dia-c ip appears twice in IR" \
        "$(get_stdout | awk -F'\t' '$4=="ip4" && $5=="192.0.2.0/24"' | grep -c .)" "2"
}

test_ir_apex_a_resolves() {
    run_script __ir hosted.example
    assert_rc "apex a exits 0" 0
    assert_stdout_contains "a cost row" $'0\thosted.example\t+\ta\thosted.example\t1'
    assert_stdout_contains "a resolved ip" $'0\thosted.example\t+\tip4\t198.51.100.20\t0'
}

# --- run ---
run_tests "$@"
