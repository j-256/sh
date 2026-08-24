#!/bin/bash
# get.test.sh - Tests for get
# shellcheck source-path=SCRIPTDIR disable=SC2329,SC2016

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../scripts/get"

# --- test cases ---

test_help_exits_zero() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME section" "NAME"
    assert_stdout_contains "help has SYNOPSIS section" "SYNOPSIS"
    assert_stdout_contains "help mentions 'get'" "get"
}

test_short_help_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h shows NAME section" "NAME"
}

test_help_names_all_short() {
    run_script -h
    assert_stdout_contains "help names -a short" "-a, --all"
}

test_help_names_skill_short() {
    run_script -h
    assert_stdout_contains "help names -s short" "-s, --skill"
    assert_stdout_contains "help documents SKILL_DIR" "SKILL_DIR"
}

test_unknown_flag_errors() {
    run_script --banana
    assert_rc "unknown flag exits 2" 2
    assert_stderr_contains "stderr mentions the flag" "--banana"
}

test_all_with_names_errors() {
    run_script --all tsd
    assert_rc "--all mixed with names exits 2" 2
    assert_stderr_contains "stderr mentions conflict" "--all"
}

test_names_with_all_errors() {
    run_script tsd --all
    assert_rc "names mixed with --all exits 2" 2
}

test_curl_missing_exits_three() {
    rm -f "$SHIM_DIR/curl"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        /bin/bash "$UNDER_TEST" tsd >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "missing curl exits 3" 3
    assert_stderr_contains "stderr mentions curl" "curl"
}

# --- shims ---

write_shims() {
    cat > "$TEST_DIR/index.md" <<'INDEX'
# Shell Utilities

**Jump to:** [A](#a) · [B](#b)

## A

| Tool | Description |
|------|-------------|
| [`alpha`](alpha.md?html) · [script](alpha) | First script |
| [`bravo`](bravo.md?html) · [script](bravo) | Second script with a `|` in it |

## B

| Tool | Description |
|------|-------------|
| [`charlie`](charlie.md?html) · [script](charlie) | Third script |
| [`delta`](delta.md?html) · [script](delta) | Fourth script |
| [`echo-tool`](echo-tool.md?html) · [script](echo-tool) | Fifth script |

---

**Notes**
- Some trailing prose that should be ignored.
INDEX

    # The --skill payload the curl shim serves for the SKILL.md URL. Frontmatter
    # is load-bearing: get validates it rather than trusting a 200
    cat > "$TEST_DIR/skill.md" <<'SKILLMD'
---
name: toolio
description: Test payload
---

# toolio

Body.
SKILLMD

    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
# Log args for assertions
printf '%s\n' "$@" >> "$TEST_DIR/curl.args"

# Find the URL (last non-flag arg that isn't a value for -o)
url=""
i=1
while [ $i -le $# ]; do
    a="${!i}"
    case "$a" in
        -o)
            i=$((i + 2))
            continue
            ;;
        -*)
            i=$((i + 1))
            continue
            ;;
        *)
            url="$a"
            ;;
    esac
    i=$((i + 1))
done

# Find output file if -o was given
out=""
i=1
while [ $i -le $# ]; do
    a="${!i}"
    if [ "$a" = "-o" ]; then
        j=$((i + 1))
        out="${!j}"
        break
    fi
    i=$((i + 1))
done

emit() {
    if [ -n "$out" ]; then
        cat > "$out"
    else
        cat
    fi
}

case "$url" in
    */INDEX.md)
        cat "$TEST_DIR/index.md" | emit
        exit 0
        ;;
    */FAIL-INDEX)
        exit 22
        ;;
    */FAIL-SKILL)
        exit 22
        ;;
    */BOGUS-SKILL)
        printf '%s\n' "not a skill at all" | emit
        exit 0
        ;;
    */SKILL.md)
        cat "$TEST_DIR/skill.md" | emit
        exit 0
        ;;
    */alpha|*/bravo|*/charlie|*/delta|*/echo-tool|*/get)
        name="${url##*/}"
        printf '%s\n' "#!/bin/bash" "# $name" "echo $name" | emit
        exit 0
        ;;
    *)
        exit 22
        ;;
esac
SHIM
    chmod +x "$SHIM_DIR/curl"
}

test_index_fetch_failure_exits_one() {
    # Point the script at an INDEX URL that the shim treats as failing
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" _GET_TEST_INDEX_URL="https://example.invalid/FAIL-INDEX" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "INDEX fetch failure exits 1" 1
    assert_stderr_contains "stderr mentions INDEX" "INDEX"
}

test_listing_has_category_headings() {
    run_script
    assert_rc "listing exits 0" 0
    assert_stdout_contains "listing has category A heading" "A"
    assert_stdout_contains "listing has category B heading" "B"
}

test_listing_indents_script_names() {
    run_script
    # Script rows are indented two spaces
    assert_stdout_contains "alpha indented" "  alpha"
    assert_stdout_contains "echo-tool indented" "  echo-tool"
}

test_listing_preserves_source_order() {
    run_script
    local out; out="$(get_stdout)"
    local alpha_pos; alpha_pos="$(printf '%s' "$out" | grep -n 'alpha' | head -1 | cut -d: -f1)"
    local bravo_pos; bravo_pos="$(printf '%s' "$out" | grep -n 'bravo' | head -1 | cut -d: -f1)"
    if [ -n "$alpha_pos" ] && [ -n "$bravo_pos" ] && [ "$alpha_pos" -lt "$bravo_pos" ]; then
        _ok "alpha appears before bravo"
    else
        _fail "alpha should appear before bravo (got alpha=$alpha_pos bravo=$bravo_pos)"
    fi
}

test_listing_shows_descriptions() {
    run_script
    assert_stdout_contains "alpha description" "First script"
    assert_stdout_contains "pipe-containing description preserved" "\`|\`"
}

test_unknown_script_errors_before_fetch() {
    run_script zulu
    assert_rc "unknown name exits 2" 2
    assert_stderr_contains "stderr names the bad name" "zulu"
    # curl.args should contain INDEX.md but NOT /zulu
    if grep -q '/INDEX.md' "$TEST_DIR/curl.args" 2>/dev/null; then
        _ok "INDEX was fetched"
    else
        _fail "expected INDEX.md fetch in curl.args"
    fi
    if grep -q '/zulu' "$TEST_DIR/curl.args" 2>/dev/null; then
        _fail "should NOT have fetched /zulu"
    else
        _ok "no /zulu fetch attempted"
    fi
}

test_mixed_known_unknown_errors() {
    run_script alpha zulu
    assert_rc "mixed known/unknown exits 2" 2
    assert_stderr_contains "stderr mentions zulu" "zulu"
    # Alpha should NOT have been fetched since validation is upfront
    if grep -q '/alpha' "$TEST_DIR/curl.args" 2>/dev/null; then
        _fail "should NOT have fetched /alpha (validation is upfront)"
    else
        _ok "no /alpha fetch attempted"
    fi
}

test_all_populates_requested_from_catalog() {
    run_script --all
    # We expect per-script fetches for every fixture name
    # Task 9 implements per-script fetch; until then, this test will fail
    # Exit code is whatever the current install dispatch returns (0 today)
    for n in alpha bravo charlie delta echo-tool; do
        if grep -q "/$n" "$TEST_DIR/curl.args" 2>/dev/null; then
            _ok "--all fetched /$n"
        else
            _fail "--all did not attempt to fetch /$n"
        fi
    done
}

test_missing_install_dir_created_with_notice() {
    local target="$TEST_DIR/custom-install"
    # target does NOT exist
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    if [ -d "$target" ]; then
        _ok "install dir created"
    else
        _fail "install dir not created: $target"
    fi
    assert_stderr_contains "notice printed" "Created"
}

test_existing_install_dir_no_notice() {
    local target="$TEST_DIR/preexisting"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_stderr_not_contains "no 'Created' notice for existing dir" "Created"
}

test_install_single_script() {
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "install single exits 0" 0
    assert_file_exists "alpha installed" "$target/alpha"
    if [ -x "$target/alpha" ]; then
        _ok "alpha is executable"
    else
        _fail "alpha is not executable"
    fi
    assert_stdout_contains "stdout reports installed" "installed: alpha"
}

test_install_multiple_scripts() {
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha charlie delta >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "multi install exits 0" 0
    assert_file_exists "alpha installed" "$target/alpha"
    assert_file_exists "charlie installed" "$target/charlie"
    assert_file_exists "delta installed" "$target/delta"
}

test_up_to_date_when_identical() {
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    # Pre-seed with the exact content the shim will return
    printf '%s\n' "#!/bin/bash" "# alpha" "echo alpha" > "$target/alpha"
    chmod +x "$target/alpha"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "up-to-date exits 0" 0
    assert_stdout_contains "stdout reports up to date" "up to date: alpha"
}

test_updated_when_differing() {
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    # Pre-seed with different content
    printf 'old content\n' > "$target/alpha"
    chmod +x "$target/alpha"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "updated exits 0" 0
    assert_stdout_contains "stdout reports updated" "updated: alpha"
    local new_content; new_content="$(cat "$target/alpha")"
    assert_contains "new content contains 'echo alpha'" "$new_content" "echo alpha"
    assert_not_contains "old content replaced" "$new_content" "old content"
}

test_per_script_fetch_failure_continues() {
    # Overwrite the shim to fail for /bravo specifically
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/curl.args"
url=""
out=""
i=1
while [ $i -le $# ]; do
    a="${!i}"
    case "$a" in
        -o) j=$((i + 1)); out="${!j}"; i=$((i + 2)); continue ;;
        -*) i=$((i + 1)); continue ;;
        *) url="$a" ;;
    esac
    i=$((i + 1))
done
emit() { if [ -n "$out" ]; then cat > "$out"; else cat; fi; }
case "$url" in
    */INDEX.md) cat "$TEST_DIR/index.md" | emit; exit 0 ;;
    */bravo) exit 22 ;;
    */alpha|*/charlie|*/delta|*/echo-tool)
        name="${url##*/}"
        printf '%s\n' "#!/bin/bash" "# $name" "echo $name" | emit
        exit 0
        ;;
    *) exit 22 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/curl"

    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha bravo charlie >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "partial failure exits 1" 1
    assert_file_exists "alpha installed" "$target/alpha"
    assert_file_exists "charlie installed" "$target/charlie"
    if [ -e "$target/bravo" ]; then
        _fail "bravo should NOT be installed"
    else
        _ok "bravo not installed (fetch failed)"
    fi
    assert_stdout_contains "stdout reports bravo failed" "failed: bravo"
}

test_rejects_non_bash_content() {
    # Overwrite the shim to return HTML for /alpha
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/curl.args"
url=""
out=""
i=1
while [ $i -le $# ]; do
    a="${!i}"
    case "$a" in
        -o) j=$((i + 1)); out="${!j}"; i=$((i + 2)); continue ;;
        -*) i=$((i + 1)); continue ;;
        *) url="$a" ;;
    esac
    i=$((i + 1))
done
emit() { if [ -n "$out" ]; then cat > "$out"; else cat; fi; }
case "$url" in
    */INDEX.md) cat "$TEST_DIR/index.md" | emit; exit 0 ;;
    */alpha) printf '%s\n' "<html><body>Maintenance</body></html>" | emit; exit 0 ;;
    *) exit 22 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/curl"

    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "HTML content exits 1" 1
    if [ -e "$target/alpha" ]; then
        _fail "alpha should NOT be installed (invalid content)"
    else
        _ok "alpha not installed (invalid content)"
    fi
}

test_rejects_empty_response() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> "$TEST_DIR/curl.args"
url=""
out=""
i=1
while [ $i -le $# ]; do
    a="${!i}"
    case "$a" in
        -o) j=$((i + 1)); out="${!j}"; i=$((i + 2)); continue ;;
        -*) i=$((i + 1)); continue ;;
        *) url="$a" ;;
    esac
    i=$((i + 1))
done
emit() { if [ -n "$out" ]; then cat > "$out"; else cat; fi; }
case "$url" in
    */INDEX.md) cat "$TEST_DIR/index.md" | emit; exit 0 ;;
    */alpha) if [ -n "$out" ]; then : > "$out"; fi; exit 0 ;;
    *) exit 22 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/curl"

    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "empty response exits 1" 1
    if [ -e "$target/alpha" ]; then
        _fail "alpha should NOT be installed (empty content)"
    else
        _ok "alpha not installed (empty content)"
    fi
}

test_all_flag_installs_catalog() {
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" --all >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "--all exits 0" 0
    for n in alpha bravo charlie delta echo-tool; do
        assert_file_exists "$n installed via --all" "$target/$n"
    done
}

test_all_short_installs_catalog() {
    # -a is the short for --all; it should install the full catalog too
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" -a >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "-a exits 0" 0
    for n in alpha bravo charlie delta echo-tool; do
        assert_file_exists "$n installed via -a" "$target/$n"
    done
}

test_all_short_with_names_errors() {
    # -a shares --all's mutual exclusion with explicit script names
    run_script -a tsd
    assert_rc "-a mixed with names exits 2" 2
    assert_stderr_contains "stderr mentions conflict" "--all"
}

test_bundled_help_all_short() {
    # -ha bundles -h and -a; _expand_short_opts (added with the -a flag) splits
    # it into -h -a, and -h wins by appearing first, so help prints and exits 0
    run_script -ha
    assert_rc "-ha bundled shorts exit 0" 0
    assert_stdout_contains "-ha prints help" "NAME"
}

test_summary_line_format() {
    local target="$TEST_DIR/bin"
    mkdir -p "$target"
    # Pre-seed alpha so it's up-to-date
    printf '%s\n' "#!/bin/bash" "# alpha" "echo alpha" > "$target/alpha"
    chmod +x "$target/alpha"
    # Pre-seed delta with different content so it gets updated
    printf 'old\n' > "$target/delta"
    chmod +x "$target/delta"

    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:$PATH" INSTALL_DIR="$target" \
        /bin/bash "$UNDER_TEST" alpha charlie delta >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "multi-outcome exits 0" 0
    assert_stdout_contains "summary has request count" "3 requested"
    assert_stdout_contains "summary reports installed" "1 installed"
    assert_stdout_contains "summary reports updated" "1 updated"
    assert_stdout_contains "summary reports up to date" "1 up to date"
}

test_path_warning_when_install_dir_not_on_path() {
    local target="$TEST_DIR/bin-not-on-path"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" INSTALL_DIR="$target" \
        PATH="$SHIM_DIR:/usr/bin:/bin" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_stderr_contains "warning that dir is not on PATH" "not on your \$PATH"
    assert_stderr_contains "warning shows export line" "export PATH=\"$target:\$PATH\""
}

test_no_path_warning_when_install_dir_on_path() {
    local target="$TEST_DIR/bin-on-path"
    mkdir -p "$target"
    env TEST_DIR="$TEST_DIR" INSTALL_DIR="$target" \
        PATH="$target:$SHIM_DIR:/usr/bin:/bin" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_stderr_not_contains "no PATH warning when on PATH" "not on your \$PATH"
}

test_path_warning_trailing_slash_does_not_fire() {
    local target="$TEST_DIR/bin-with-slash"
    mkdir -p "$target"
    # PATH has trailing slash on the entry; INSTALL_DIR doesn't
    env TEST_DIR="$TEST_DIR" INSTALL_DIR="$target" \
        PATH="$target/:$SHIM_DIR:/usr/bin:/bin" \
        /bin/bash "$UNDER_TEST" alpha >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_stderr_not_contains "no PATH warning with trailing slash in PATH entry" "not on your \$PATH"
}

# --- --skill mode ---

# Runs --skill with a SKILL_DIR override and a shimmed skill URL. HOME is
# redirected too so a real ~/.claude on the machine running the suite can never
# be a target, even if a code path stopped honoring SKILL_DIR
run_skill() {
    local skill_dir="$1"
    shift
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$TEST_DIR/home" SKILL_DIR="$skill_dir" \
        _GET_TEST_SKILL_URL="https://example.invalid/skills/toolio/SKILL.md" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

test_skill_installs_to_skill_dir() {
    local root="$TEST_DIR/skills"
    run_skill "$root" --skill
    assert_rc "--skill exits 0" 0
    assert_file_exists "SKILL.md installed" "$root/toolio/SKILL.md"
    assert_stdout_contains "stdout reports installed" "installed: toolio"
    assert_stdout_contains "summary counts one location" "1 skill location"
}

test_skill_short_flag() {
    local root="$TEST_DIR/skills"
    run_skill "$root" -s
    assert_rc "-s exits 0" 0
    assert_file_exists "SKILL.md installed via -s" "$root/toolio/SKILL.md"
}

test_skill_payload_is_not_executable() {
    # The payload is markdown, so unlike a script it must not get +x
    local root="$TEST_DIR/skills"
    run_skill "$root" --skill
    if [ -x "$root/toolio/SKILL.md" ]; then
        _fail "SKILL.md is executable -- markdown must not get +x"
    else
        _ok "SKILL.md is not executable"
    fi
}

test_skill_up_to_date_on_rerun() {
    local root="$TEST_DIR/skills"
    run_skill "$root" --skill
    run_skill "$root" --skill
    assert_rc "rerun exits 0" 0
    assert_stdout_contains "rerun reports up to date" "up to date: toolio"
    assert_stdout_contains "summary counts up to date" "1 up to date"
}

test_skill_updates_when_differing() {
    local root="$TEST_DIR/skills"
    mkdir -p "$root/toolio"
    printf 'stale payload\n' > "$root/toolio/SKILL.md"
    run_skill "$root" --skill
    assert_rc "update exits 0" 0
    assert_stdout_contains "stdout reports updated" "updated: toolio"
    local body; body="$(cat "$root/toolio/SKILL.md")"
    assert_contains "payload replaced" "$body" "name: toolio"
    assert_not_contains "stale content gone" "$body" "stale payload"
}

test_skill_creates_missing_root() {
    local root="$TEST_DIR/nested/deeper/skills"
    run_skill "$root" --skill
    assert_rc "missing root exits 0" 0
    assert_file_exists "nested root created" "$root/toolio/SKILL.md"
}

test_skill_fetch_failure_exits_one() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$TEST_DIR/home" SKILL_DIR="$TEST_DIR/skills" \
        _GET_TEST_SKILL_URL="https://example.invalid/FAIL-SKILL" \
        /bin/bash "$UNDER_TEST" --skill >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "skill fetch failure exits 1" 1
    assert_stdout_contains "stdout reports failure" "failed: toolio"
}

test_skill_rejects_invalid_payload() {
    # A 200 carrying something that isn't a skill (error page, wrong file) must
    # not be written: get validates the frontmatter, not just the status
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$TEST_DIR/home" SKILL_DIR="$TEST_DIR/skills" \
        _GET_TEST_SKILL_URL="https://example.invalid/BOGUS-SKILL" \
        /bin/bash "$UNDER_TEST" --skill >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "invalid payload exits 1" 1
    assert_stdout_contains "stdout reports invalid content" "invalid content"
    if [ -e "$TEST_DIR/skills/toolio/SKILL.md" ]; then
        _fail "invalid payload was written to disk"
    else
        _ok "invalid payload not written"
    fi
}

test_skill_with_names_errors() {
    run_skill "$TEST_DIR/skills" --skill alpha
    assert_rc "--skill with names exits 2" 2
    assert_stderr_contains "stderr mentions --skill" "--skill"
}

test_skill_with_all_errors() {
    run_skill "$TEST_DIR/skills" -s -a
    assert_rc "--skill with --all exits 2" 2
    assert_stderr_contains "stderr mentions --skill" "--skill"
}

test_skill_no_root_found_exits_two() {
    # No SKILL_DIR and a HOME with neither harness dir present
    mkdir -p "$TEST_DIR/empty-home"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$TEST_DIR/empty-home" \
        _GET_TEST_SKILL_URL="https://example.invalid/skills/toolio/SKILL.md" \
        /bin/bash "$UNDER_TEST" --skill >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "no skill root exits 2" 2
    assert_stderr_contains "stderr names SKILL_DIR" "SKILL_DIR"
}

test_skill_detects_each_harness_root() {
    # Both harness config dirs present (skills/ subdir absent) -- each gets the
    # payload, and the summary pluralizes
    local home="$TEST_DIR/dual-home"
    mkdir -p "$home/.claude" "$home/.codex"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$home" \
        _GET_TEST_SKILL_URL="https://example.invalid/skills/toolio/SKILL.md" \
        /bin/bash "$UNDER_TEST" --skill >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "dual-harness install exits 0" 0
    assert_file_exists "claude root installed" "$home/.claude/skills/toolio/SKILL.md"
    assert_file_exists "codex root installed" "$home/.codex/skills/toolio/SKILL.md"
    assert_stdout_contains "summary counts two locations" "2 skill locations"
}

test_skill_skips_absent_harness_root() {
    # Only one harness present -- the other must not be conjured into existence
    local home="$TEST_DIR/single-home"
    mkdir -p "$home/.claude"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$home" \
        _GET_TEST_SKILL_URL="https://example.invalid/skills/toolio/SKILL.md" \
        /bin/bash "$UNDER_TEST" --skill >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "single-harness install exits 0" 0
    assert_file_exists "present harness installed" "$home/.claude/skills/toolio/SKILL.md"
    if [ -e "$home/.codex" ]; then
        _fail "absent harness dir was created"
    else
        _ok "absent harness dir left alone"
    fi
    assert_stdout_contains "summary counts one location" "1 skill location"
}

test_skill_does_not_fetch_catalog() {
    # --skill is standalone: it needs no catalog, so INDEX.md must not be fetched
    run_skill "$TEST_DIR/skills" --skill
    assert_rc "--skill exits 0" 0
    local args; args="$(cat "$TEST_DIR/curl.args" 2>/dev/null)"
    assert_not_contains "no INDEX.md fetch in --skill mode" "$args" "INDEX.md"
}

# --- run ---

run_tests "$@"
