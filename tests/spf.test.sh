#!/bin/bash
# spf.test.sh - Tests for spf
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../spf"

# Run the script with NO python3 reachable, while still providing the coreutils
# the resolver needs. macOS ships /usr/bin/python3, so simply removing the shim
# and using the normal PATH would NOT simulate absence (command -v would find the
# system python3). We build a clean bin dir of symlinks to the real coreutils,
# drop the python3 shim, and point PATH at only (shim dir + that clean dir).
run_script_no_python3() {
    /bin/rm -f "$SHIM_DIR/python3"
    local nopy="$TEST_DIR/nopy"
    mkdir -p "$nopy"
    local t
    local real
    for t in sed grep head basename awk sort cat tr cut dirname; do
        real="$(PATH=/usr/bin:/bin command -v "$t" 2>/dev/null)" && ln -sf "$real" "$nopy/$t"
    done
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$nopy" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Run the script with NO dig reachable, to simulate a host missing the BIND
# utilities. Same clean-coreutils-symlink technique as run_script_no_python3, but
# we ALSO drop the dig shim and build the clean dir WITHOUT a dig symlink, so
# `command -v dig` fails on PATH (shim dir + that clean dir). The coreutils are
# still linked for robustness, though the early exit-3 dig check never reaches
# them.
run_script_no_dig() {
    /bin/rm -f "$SHIM_DIR/dig"
    local nodig="$TEST_DIR/nodig"
    mkdir -p "$nodig"
    local t
    local real
    for t in sed grep head basename awk sort cat tr cut dirname; do
        real="$(PATH=/usr/bin:/bin command -v "$t" 2>/dev/null)" && ln -sf "$real" "$nodig/$t"
    done
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$nodig" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

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
    TXT:ptrtest.example)      printf '%s\n' '"v=spf1 ptr:mail.ptrtest.example ptr -all"' ;;
    TXT:qual.example)
        printf '%s\n' '"v=spf1 -ip4:192.0.2.5 ~all"' ;;
    TXT:exists.example)
        printf '%s\n' '"v=spf1 exists:%{i}._spf.exists.example -all"' ;;
    A:7.100.51.198._spf.exists.example)   printf '%s\n' '127.0.0.2' ;;   # %{ir} reverse of 198.51.100.7
    A:198.51.100.7._spf.exists.example)   printf '%s\n' '127.0.0.2' ;;   # %{i} non-reversed
    TXT:sender.example)
        printf '%s\n' '"v=spf1 exists:%{s}._spf.sender.example -all"' ;;
    # bare a / mx on the apex
    TXT:hosted.example)       printf '%s\n' '"v=spf1 a mx -all"' ;;
    A:hosted.example)         printf '%s\n' '198.51.100.20' ;;
    A:mailhost.hosted.example) printf '%s\n' '198.51.100.30' ;;
    # check: >10 lookups (11 includes at the root, each leaf needs no lookup)
    TXT:toomany.example)
        printf '%s\n' '"v=spf1 include:l1.ex include:l2.ex include:l3.ex include:l4.ex include:l5.ex include:l6.ex include:l7.ex include:l8.ex include:l9.ex include:l10.ex include:l11.ex -all"' ;;
    TXT:l1.ex|TXT:l2.ex|TXT:l3.ex|TXT:l4.ex|TXT:l5.ex|TXT:l6.ex|TXT:l7.ex|TXT:l8.ex|TXT:l9.ex|TXT:l10.ex|TXT:l11.ex)
        printf '%s\n' '"v=spf1 -all"' ;;
    # check: syntax smells
    TXT:plusall.example)  printf '%s\n' '"v=spf1 +all"' ;;
    TXT:ptr.example)      printf '%s\n' '"v=spf1 ptr -all"' ;;
    # check: 3 void lookups (each include target has no record)
    TXT:void.example)     printf '%s\n' '"v=spf1 include:v1.void include:v2.void include:v3.void -all"' ;;
    TXT:v1.void|TXT:v2.void|TXT:v3.void)  ;;   # no record -> each is a void lookup
    # find a:<host> three-way fixtures
    # litera.example: literal a:mail.litera.example present; host resolves into its own listed range
    TXT:litera.example)       printf '%s\n' '"v=spf1 a:mail.litera.example ip4:198.51.100.0/24 -all"' ;;
    A:mail.litera.example)    printf '%s\n' '198.51.100.50' ;;
    # flat.example: NO literal a:; host's IP only inside a flattened ip4: range (fragile)
    TXT:flat.example)         printf '%s\n' '"v=spf1 ip4:203.0.113.0/24 -all"' ;;
    A:host.flat.example)      printf '%s\n' '203.0.113.9' ;;
    # other.example: host's IP covered only via a DIFFERENT a: directive (case c)
    TXT:other.example)        printf '%s\n' '"v=spf1 a:known.other.example -all"' ;;
    A:known.other.example)    printf '%s\n' '203.0.113.20' ;;
    A:wanted.other.example)   printf '%s\n' '203.0.113.20' ;;   # same IP as known.other.example
    # gone.example: host resolves to nothing (dangling), but a:dead.gone.example is literally present
    TXT:gone.example)         printf '%s\n' '"v=spf1 a:dead.gone.example -all"' ;;
    A:dead.gone.example)      ;;                                # no A record -> dangling
    # absent.example: queried host's IP appears nowhere
    TXT:absent.example)       printf '%s\n' '"v=spf1 ip4:192.0.2.0/24 -all"' ;;
    A:missing.absent.example) printf '%s\n' '198.51.100.250' ;;
    # find a:<host> IPv6 coverage (for python3-absent degradation test)
    # v6flat.example: NO literal a:; host's only address is an AAAA inside a flattened ip6: range
    TXT:v6flat.example)        printf '%s\n' '"v=spf1 ip6:2001:db8::/32 -all"' ;;
    AAAA:host.v6flat.example)  printf '%s\n' '2001:db8::99' ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/dig"

    cat > "$SHIM_DIR/python3" <<'SHIM'
#!/bin/bash
ip="${@: -2:1}"; cidr="${@: -1}"
printf 'python3 %s\n' "$ip $cidr" >> "$TEST_DIR/python3.log"
case "$ip:$cidr" in
    "2001:db8::9:2001:db8::/32") exit 0 ;;
    "2001:db8::99:2001:db8::/32") exit 0 ;;
    *) exit 4 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/python3"
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

test_dig_missing_exits_3() {
    run_script_no_dig check example.com
    assert_rc "dig missing exits 3" 3
    assert_stderr_contains "says dig required" "dig is required"
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

test_ir_ptr_value_has_no_leading_colon() {
    run_script __ir ptrtest.example
    assert_rc "ptr ir exits 0" 0
    # qualified ptr: value is the bare host, no leading colon
    assert_stdout_contains "qualified ptr value" $'0\tptrtest.example\t+\tptr\tmail.ptrtest.example\t1'
    # bare ptr: empty value field
    assert_stdout_contains "bare ptr empty value" $'0\tptrtest.example\t+\tptr\t\t1'
    # negative: the buggy ':mail...' form must NOT appear
    assert_stdout_not_contains "no stray colon" $'\tptr\t:mail'
}

test_ir_apex_a_resolves() {
    run_script __ir hosted.example
    assert_rc "apex a exits 0" 0
    assert_stdout_contains "a cost row" $'0\thosted.example\t+\ta\thosted.example\t1'
    assert_stdout_contains "a resolved ip" $'0\thosted.example\t+\tip4\t198.51.100.20\t0'
}

test_flatten_lists_ips_sorted_deduped() {
    run_script flatten example.com
    assert_rc "flatten exits 0" 0
    assert_stdout_contains "root ip4" "198.51.100.0/24"
    assert_stdout_contains "nested ip4" "203.0.113.0/24"
    assert_stdout_contains "nested ip6" "2001:db8::/32"
    # IPv4 sorts before IPv6: first line is an ip4, last is the ip6
    assert_eq "ipv6 last" "$(get_stdout | tail -n1)" "2001:db8::/32"
}

test_flatten_record_mode() {
    run_script flatten example.com --record
    assert_rc "record mode exits 0" 0
    assert_stdout_contains "starts v=spf1" 'v=spf1'
    assert_stdout_contains "keeps root all" '~all'
    assert_stdout_contains "quoted chunk" '"v=spf1'
}

test_flatten_notes_unevaluable_exists() {
    # fixture with an exists row (added to shim in this step)
    run_script flatten exists.example
    assert_stderr_contains "notes exists skip" "cannot statically evaluate exists"
}

test_flatten_raw_record_input() {
    # a literal record is recognized (NOT looked up) and flattened directly
    run_script flatten 'v=spf1 ip4:198.51.100.0/24 ip4:203.0.113.0/24 -all'
    assert_rc "raw flatten exits 0" 0
    assert_stdout_contains "emits first ip" "198.51.100.0/24"
    assert_stdout_contains "emits second ip" "203.0.113.0/24"
    # the root record was NOT fetched via dig (no TXT query for a domain)
    assert_not_contains "no TXT lookup for raw" "$(cat "$TEST_DIR/dig.log" 2>/dev/null)" "TXT v=spf1"
}

test_flatten_raw_record_via_stdin() {
    printf 'v=spf1 ip4:198.51.100.0/24 -all\n' | run_script flatten -
    assert_rc "stdin flatten exits 0" 0
    assert_stdout_contains "emits ip from stdin" "198.51.100.0/24"
}

# --- __ip4 / _ip4_in_cidr tests ---

test_ip4_inside_24() {
    run_script __ip4 198.51.100.42 198.51.100.0/24
    assert_rc "inside /24" 0
}
test_ip4_outside_24() {
    run_script __ip4 198.51.101.1 198.51.100.0/24
    assert_rc "outside /24" 1
}
test_ip4_network_address() {
    run_script __ip4 198.51.100.0 198.51.100.0/24
    assert_rc "network addr inside" 0
}
test_ip4_broadcast_address() {
    run_script __ip4 198.51.100.255 198.51.100.0/24
    assert_rc "broadcast inside" 0
}
test_ip4_slash32_exact() {
    run_script __ip4 203.0.113.7 203.0.113.7/32
    assert_rc "exact /32" 0
}
test_ip4_slash32_off_by_one() {
    run_script __ip4 203.0.113.8 203.0.113.7/32
    assert_rc "off by one /32" 1
}
test_ip4_bare_ip_is_slash32() {
    run_script __ip4 203.0.113.7 203.0.113.7
    assert_rc "bare ip exact" 0
}
test_ip4_slash0_matches_everything() {
    run_script __ip4 8.8.8.8 0.0.0.0/0
    assert_rc "/0 matches all" 0
}
test_ip4_malformed_prefix() {
    run_script __ip4 1.2.3.4 1.2.3.0/33
    assert_rc "prefix>32 rejected" 2
}
test_ip4_octet_over_255_rejected() {
    run_script __ip4 256.0.0.1 0.0.0.0/0
    assert_rc "octet>255 rejected" 2
}
test_ip4_inside_16() {
    run_script __ip4 1.2.3.4 1.2.0.0/16
    assert_rc "inside /16" 0
}
test_ip4_outside_16() {
    run_script __ip4 1.3.0.0 1.2.0.0/16
    assert_rc "outside /16" 1
}
test_ip4_empty_prefix_rejected() {
    run_script __ip4 1.2.3.0 "1.2.3.0/"
    assert_rc "empty prefix rejected" 2
}
test_ip4_nonnumeric_prefix_rejected() {
    run_script __ip4 1.2.3.0 1.2.3.0/ab
    assert_rc "non-numeric prefix rejected" 2
}
test_ip4_short_ip_rejected() {
    run_script __ip4 1.2.3 1.2.3.0/24
    assert_rc "3-octet ip rejected" 2
}
test_ip4_long_ip_rejected() {
    run_script __ip4 1.2.3.4.5 1.2.3.0/24
    assert_rc "5-octet ip rejected" 2
}
test_ip4_slash31_inside() {
    run_script __ip4 192.0.2.0 192.0.2.0/31
    assert_rc "inside /31" 0
}
test_ip4_slash31_outside() {
    run_script __ip4 192.0.2.2 192.0.2.0/31
    assert_rc "outside /31" 1
}
test_ip4_slash1_inside() {
    run_script __ip4 200.0.0.1 128.0.0.0/1
    assert_rc "inside /1" 0
}

# --- find (Task 5) ---

test_find_ipv4_match_exit0() {
    run_script find example.com 198.51.100.42
    assert_rc "covered exits 0" 0
    assert_stdout_contains "names source" "example.com"
}
test_find_ipv4_nested_match() {
    run_script find example.com 203.0.113.5
    assert_rc "nested covered exits 0" 0
    assert_stdout_contains "names nested source" "_spf.example.net"
}
test_find_ipv4_no_match_exit4() {
    run_script find example.com 192.0.2.1
    assert_rc "not found exits 4" 4
    assert_stdout_contains "says not found" "not found"
}
test_find_surfaces_reject_qualifier() {
    # qual.example: -ip4 reject covering the query IP
    run_script find qual.example 192.0.2.5
    assert_rc "listed-but-reject still exits 0 (membership)" 0
    assert_stdout_contains "shows minus qualifier" "qualifier: -"
}
test_find_missing_ip_is_usage_error() {
    run_script find example.com
    assert_rc "missing ip exits 2" 2
    assert_stderr_contains "asks for ip" "ip"
}

# --- find (Task 6: IPv6) ---

test_find_ipv6_match_via_python3() {
    run_script find example.com 2001:db8::9
    assert_rc "ipv6 covered exits 0" 0
    assert_contains "used python3" "$(cat "$TEST_DIR/python3.log" 2>/dev/null)" "2001:db8::/32"
}
test_find_ipv6_no_python3_degrades() {
    run_script_no_python3 find example.com 2001:db8::9
    assert_stderr_contains "warns about python3" "python3 not found"
    assert_rc "degraded literal: not an exact string in record so exit 4" 4
}
test_find_ipv6_literal_match_without_python3() {
    run_script_no_python3 find example.com 2001:db8::/32
    assert_rc "literal equal exits 0" 0
}

# --- find (Task 7: exists macro) ---

test_find_exists_macro_match() {
    run_script find exists.example 198.51.100.7
    assert_rc "exists match exits 0" 0
    assert_stdout_contains "credits exists" "exists"
}
test_find_exists_macro_no_match() {
    run_script find exists.example 198.51.100.200
    assert_rc "exists no-match exits 4" 4
}
test_find_exists_unsupported_macro_skipped() {
    run_script find sender.example 198.51.100.7
    assert_stderr_contains "notes skip" "cannot statically evaluate"
    assert_rc "skipped, falls through to not-found" 4
}

# --- find wording (Task 2: mechanism-aware match verbs) ---

test_find_ip4_range_says_covered() {
    run_script find example.com 198.51.100.42
    assert_rc "covered exits 0" 0
    assert_stdout_contains "range match says covered" "is covered by ip4:198.51.100.0/24"
}
test_find_ip4_exact_says_listed() {
    # bare IP (no prefix) is an exact host -> "is listed in"
    run_script find 'v=spf1 ip4:203.0.113.7 -all' 203.0.113.7
    assert_rc "exact exits 0" 0
    assert_stdout_contains "exact match says listed" "is listed in ip4:203.0.113.7"
}
test_find_exists_says_matches_not_covered() {
    run_script find exists.example 198.51.100.7
    assert_rc "exists match exits 0" 0
    assert_stdout_contains "exists says matches" "matches exists:"
    assert_stdout_not_contains "exists does NOT say listed/covered" "listed/covered"
}

# --- find a:<host> (Task 3: presence/coverage three-way) ---

test_find_a_literal_present_exit0() {
    run_script find litera.example a:mail.litera.example
    assert_rc "literal a: exits 0" 0
    assert_stdout_contains "reports literal a:" "matches a:mail.litera.example"
}
test_find_a_flattened_is_fragile_exit5() {
    run_script find flat.example a:host.flat.example
    assert_rc "flattened-only exits 5" 5
    assert_stdout_contains "says not literal" "NOT present literally"
    assert_stdout_contains "names the covering range" "203.0.113.0/24"
    assert_stdout_contains "warns fragile" "fragile"
}
test_find_a_covered_via_other_directive_exit5() {
    run_script find other.example a:wanted.other.example
    assert_rc "covered via other directive exits 5" 5
    assert_stdout_contains "names the other directive" "a:known.other.example"
    assert_stdout_contains "flags not your directive" "not your directive"
}
test_find_a_dangling_present_warns_exit0() {
    run_script find gone.example a:dead.gone.example
    assert_rc "dangling literal still exits 0" 0
    assert_stdout_contains "still reports present" "matches a:dead.gone.example"
    assert_stderr_contains "warns dead directive" "resolves to no addresses"
}
test_find_a_absent_exit4() {
    run_script find absent.example a:missing.absent.example
    assert_rc "absent exits 4" 4
    assert_stdout_contains "says not found" "not found"
}
test_find_rejects_ip4_query() {
    run_script find example.com ip4:198.51.100.0/24
    assert_rc "ip4: query is usage error" 2
    assert_stderr_contains "explains rejection" "does not take ip4:/ip6:"
}
test_find_ip_path_unchanged_exit0() {
    run_script find example.com 198.51.100.42
    assert_rc "bare IP still works" 0
}
test_find_ip_path_unchanged_exit4() {
    run_script find example.com 192.0.2.1
    assert_rc "bare IP not-found still 4" 4
}
test_find_a_ipv6_coverage_warns_without_python3() {
    # v6flat.example: host's only address is IPv6, covered only by a flattened
    # ip6: range. Without python3 the coverage CANNOT be confirmed, so the
    # outcome is "not found" (exit 4) -- but the user must be told IPv6 wasn't
    # really checked, mirroring the bare-IP path's degradation warning.
    run_script_no_python3 find v6flat.example a:host.v6flat.example
    assert_stderr_contains "warns python3 absent" "python3 not found"
    assert_rc "cannot confirm coverage without python3 -> exit 4" 4
}
test_find_a_ipv6_coverage_fragile_with_python3() {
    # Same fixture WITH python3 (shim present): coverage is confirmed, so the
    # flattened-range case fires -> fragile (exit 5).
    run_script find v6flat.example a:host.v6flat.example
    assert_rc "covered by ip6 range -> fragile exit 5" 5
    assert_stdout_contains "says not literal" "NOT present literally"
    assert_stdout_contains "names the covering ip6 range" "2001:db8::/32"
    assert_stdout_contains "warns fragile" "fragile"
}

# --- check (Task 8) ---

test_check_clean_record() {            # example.com: 1 include + ip4 + ip6 -> 1 lookup, clean
    run_script check example.com
    assert_rc "clean exits 0" 0
    assert_stdout_contains "reports lookup count" "lookup"
}
test_check_over_10_lookups() {
    run_script check toomany.example
    assert_rc "over limit exits 4" 4
    assert_stdout_contains "flags limit" "10"
}
test_check_flags_plus_all() {
    run_script check plusall.example
    assert_rc "plus all exits 4" 4
    assert_stdout_contains "warns +all" "+all"
}
test_check_flags_ptr() {
    run_script check ptr.example
    assert_rc "ptr exits 4" 4
    assert_stdout_contains "warns ptr" "ptr"
}
test_check_flags_excess_void_lookups() {
    run_script check void.example
    assert_rc "excess void exits 4" 4
    assert_stdout_contains "flags void" "Void"
}
test_check_no_record_runtime_error() {
    run_script check nospf.example
    assert_rc "no record exits 1" 1
}
test_check_raw_record_skips_record_count() {
    run_script check 'v=spf1 ip4:198.51.100.0/24 -all'
    assert_rc "raw clean exits 0" 0
    assert_stdout_contains "notes record-count N/A" "raw-record"
}
test_check_diamond_not_multiple_all() {
    # dia-root includes dia-a + dia-b, both include dia-c (one -all each).
    # dia-c is walked twice (diamond), so its single all appears twice in the
    # IR with the same source -- this must NOT be flagged as multiple-all.
    run_script check dia-root.example
    assert_rc "clean diamond exits 0" 0
    assert_stdout_not_contains "diamond not flagged multiple-all" "multiple all"
}
test_check_multiple_all_in_one_record() {
    # Two all tokens in the SAME (root) record is the real smell. Raw record
    # so no fixture needed; ~all and -all are both 'all' rows, neither is +all
    # (isolates the multiple-all flag from the +all flag).
    run_script check 'v=spf1 ip4:1.2.3.0/24 ~all -all'
    assert_rc "two alls in one record exits 4" 4
    assert_stdout_contains "flags multiple all" "multiple all"
}

# --- tree (Task 9) ---

test_tree_renders_hierarchy() {
    run_script tree example.com
    assert_rc "tree exits 0" 0
    assert_stdout_contains "shows include target" "_spf.example.net"
    assert_stdout_contains "shows a root ip" "198.51.100.0/24"
    assert_stdout_contains "shows a nested ip" "203.0.113.0/24"
}
test_tree_indents_by_depth() {
    run_script tree example.com
    # depth-1 ip4 row renders as "      ip4:203.0.113.0/24" (6 leading spaces).
    # Assert 4+ spaces + mech:val so the substring is only satisfied by a
    # depth-1 (or deeper) line, not the 2-space depth-0 lines.
    assert_stdout_contains "nested line indented" "    ip4:203.0.113.0/24"
}
test_tree_no_record_runtime_error() {
    run_script tree nospf.example
    assert_rc "no record exits 1" 1
}
test_tree_skips_void_rows() {
    run_script tree void.example
    assert_rc "tree exits 0" 0
    assert_stdout_not_contains "no void leaf" "void:"
}
test_tree_bare_ptr_no_cost_leak() {
    # ptr.example: 'v=spf1 ptr -all'. A bare ptr has an empty IR value field;
    # an IFS=$'\t' read merges the trailing tabs and shifts cost (1) into val,
    # rendering 'ptr:1'. The peel-split parse + ${val:+:$val} label fix this.
    run_script tree ptr.example
    assert_rc "tree exits 0" 0
    assert_stdout_not_contains "no cost leak into ptr value" "ptr:1"
    assert_stdout_contains "bare ptr rendered cleanly" "ptr"
}

# --- run ---
run_tests "$@"
