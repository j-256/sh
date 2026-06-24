#!/bin/bash
# scdef.test.sh - Tests for scdef
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../scdef"

# --- shims ---

# The curl shim looks at the requested URL and serves canned content from
# either an override file (if the test placed one) or a default response.
# Two URL kinds matter: the wiki sitemap (HTML index) and individual SC###.md
# pages (markdown body).
write_shims() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_DIR/curl.args"

# The script invokes curl as: curl -fsS -L -o <dest> -w '%{http_code}' <url>
# Pull out -o destination and the trailing URL
dest=""
url=""
prev=""
for a in "$@"; do
    case "$prev" in
        -o) dest="$a" ;;
    esac
    case "$a" in
        http*) url="$a" ;;
    esac
    prev="$a"
done

# Optional per-test override: $TEST_DIR/curl.response (body) and
# $TEST_DIR/curl.status (HTTP code). If neither, default to 200 + canned body
status="$(cat "$TEST_DIR/curl.status" 2>/dev/null || echo 200)"

if [ "$status" = "200" ]; then
    if [ -f "$TEST_DIR/curl.response" ]; then
        cat "$TEST_DIR/curl.response" > "$dest"
    else
        case "$url" in
            *www.shellcheck.net/wiki/*)
                cat <<'BODY' > "$dest"
<h1>Sitemap</h1>
<ul>
<li><a href='SC1000'>SC1000</a> &ndash; First fake entry.</li>
<li><a href='SC2155'>SC2155</a> &ndash; Declare and assign separately to avoid masking return values.</li>
<li><a href='SC2086'>SC2086</a> &ndash; Double quote to prevent globbing and word splitting.</li>
</ul>
BODY
                ;;
            *raw.githubusercontent.com/wiki/koalaman/shellcheck/SC2155.md)
                cat <<'BODY' > "$dest"
## Declare and assign separately to avoid masking return values.

### Problematic code:

```sh
echo "$variable"
```
BODY
                ;;
            *raw.githubusercontent.com/wiki/koalaman/shellcheck/SC9999.md)
                # Mark this URL as 404 so the script gets a not-found path
                status=404
                ;;
            *)
                printf 'fake body for %s\n' "$url" > "$dest"
                ;;
        esac
    fi
fi

printf '%s' "$status"
case "$status" in
    200) exit 0 ;;
    404) exit 22 ;;  # curl -f exits 22 on >=400 HTTP
    *)   exit 1 ;;
esac
SHIM
    chmod +x "$SHIM_DIR/curl"
}

# Each test gets its own cache root via XDG_CACHE_HOME so cache state does not
# leak between cases. Override run_script to inject it. PATH matches the shared
# helper's pinned floor ($SHIM_DIR:/usr/bin:/bin): scdef needs system tools
# (basename, mktemp, curl) but must NOT see a host-installed glow/render-md, so
# the "renderer not on PATH -> fall back to text" branch fires deterministically
run_script() {
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" \
        XDG_CACHE_HOME="$TEST_DIR/cache" \
        /bin/bash "$UNDER_TEST" "$@" \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# --- test cases ---

# Basics: --help, -h

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has EXIT STATUS" "EXIT STATUS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_h_short_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
}

# Argument validation

test_missing_arg() {
    run_script
    assert_rc "missing arg exits 2" 2
    assert_stderr_contains "must provide msg" "Must provide a code"
    assert_stderr_contains "usage hint" "Run \`scdef -h\` for usage"
}

test_unknown_flag() {
    run_script --bogus
    assert_rc "unknown flag exits 2" 2
    assert_stderr_contains "unknown msg" "Unknown argument '--bogus'"
}

test_invalid_code() {
    run_script wibble
    assert_rc "invalid code exits 2" 2
    assert_stderr_contains "invalid code msg" "Invalid code 'wibble'"
}

test_too_many_args() {
    run_script SC2155 SC2086
    assert_rc "too many args exits 2" 2
    assert_stderr_contains "too many msg" "Too many arguments"
}

test_search_missing_value() {
    run_script -s
    assert_rc "search missing value exits 2" 2
    assert_stderr_contains "search needs pattern" "--search requires a <pattern>"
}

test_search_eq_empty() {
    run_script --search=
    assert_rc "search= exits 2" 2
    assert_stderr_contains "search= empty" "--search requires a <pattern>"
}

test_mutual_exclusion_modes() {
    run_script -u -s foo
    assert_rc "modes mutex exits 2" 2
    assert_stderr_contains "modes mutex msg" "mutually exclusive"
}

test_mutual_exclusion_raw_full() {
    run_script --raw --full 2155
    assert_rc "raw+full mutex exits 2" 2
    assert_stderr_contains "raw+full msg" "--raw and --full are mutually exclusive"
}

# Code normalization (verified via -u so we don't need network)

test_url_canonical_code() {
    run_script -u SC2155
    assert_rc "url SC2155 exits 0" 0
    assert_stdout_contains "url SC2155" "https://github.com/koalaman/shellcheck/wiki/SC2155"
}

test_url_lowercase() {
    run_script -u sc2155
    assert_rc "url sc2155 exits 0" 0
    assert_stdout_contains "url lc -> SC" "/SC2155"
}

test_url_bare_digits() {
    run_script -u 2155
    assert_rc "url 2155 exits 0" 0
    assert_stdout_contains "url digits -> SC" "/SC2155"
}

test_url_separator_dash() {
    run_script -u SC-2155
    assert_rc "url SC-2155 exits 0" 0
    assert_stdout_contains "url dash" "/SC2155"
}

test_url_hash_prefix() {
    run_script -u "#SC2155"
    assert_rc "url #SC2155 exits 0" 0
    assert_stdout_contains "url hash" "/SC2155"
}

test_url_bracketed() {
    run_script -u "[SC2155]"
    assert_rc "url [SC2155] exits 0" 0
    assert_stdout_contains "url brackets" "/SC2155"
}

# Direct lookup happy path

test_direct_lookup_plaintext() {
    run_script SC2155
    assert_rc "direct SC2155 exits 0" 0
    assert_stdout_contains "header line" "SC2155"
    assert_stdout_contains "title" "Declare and assign separately"
    # Plaintext converter: fenced code blocks should be indented
    # shellcheck disable=SC2016 # "Expressions don't expand in single quotes, use double quotes for that." -- asserting the literal text '$variable' appears in output
    assert_stdout_contains "code indent" '    echo "$variable"'
    # And the ATX heading marker should be stripped
    assert_stdout_not_contains "no leading hashes" "## Declare and assign"
}

# Forced renderer that's missing should warn and fall back to text. The pinned
# PATH ($SHIM_DIR:/usr/bin:/bin, set in run_script above) guarantees glow is
# absent regardless of the host, so this reliably exercises the "not on PATH"
# branch rather than depending on the dev's installs
test_forced_renderer_not_installed_falls_back() {
    SCDEF_RENDERER=glow run_script SC2155
    assert_rc "missing renderer exits 0" 0
    assert_stderr_contains "missing renderer warn" "glow is not on PATH"
    # Falls back to text: heading marker should be stripped
    assert_stdout_contains "fallback content" "Declare and assign separately"
    assert_stdout_not_contains "fallback no md" "## Problematic"
}

# Bogus SCDEF_RENDERER value should warn and auto-pick
test_unknown_renderer_value_warns_and_auto() {
    SCDEF_RENDERER=zzz_not_a_renderer run_script SC2155
    assert_rc "unknown renderer exits 0" 0
    assert_stderr_contains "unknown renderer warn" "Unknown SCDEF_RENDERER 'zzz_not_a_renderer'"
}

# SCDEF_RENDERER=text forces the built-in plaintext converter
test_force_text_renderer() {
    SCDEF_RENDERER=text run_script SC2155
    assert_rc "force text exits 0" 0
    # Output is plaintext (heading hashes stripped)
    assert_stdout_not_contains "no md heading" "## Problematic"
}

# SCDEF_RENDERER=none emits raw markdown of the brief extraction
test_force_none_renderer_emits_markdown() {
    SCDEF_RENDERER=none run_script SC2155
    assert_rc "none exits 0" 0
    assert_stdout_contains "md heading present" "## Problematic"
}

# --full bypasses the brief extractor and shows the whole page
test_full_shows_complete_page() {
    run_script --full SC2155
    assert_rc "full exits 0" 0
    assert_stdout_contains "full has rationale" "return value"
}

# --raw emits markdown source verbatim (skips both extractor and renderer)
test_raw_emits_unparsed_markdown() {
    run_script --raw SC2155
    assert_rc "raw exits 0" 0
    # Raw should preserve fenced code (the wiki uses ```sh)
    assert_stdout_contains "raw fence" '```sh'
}

test_direct_lookup_raw() {
    run_script --raw SC2155
    assert_rc "raw exits 0" 0
    # Raw output preserves the markdown
    assert_stdout_contains "raw heading" "## Declare and assign"
    assert_stdout_contains "raw fence" '```sh'
}

# Wiki 404 -> exit 5

test_wiki_not_found() {
    run_script SC9999
    assert_rc "404 exits 5" 5
    assert_stderr_contains "not-found msg" "SC9999 not found on the ShellCheck wiki"
}

# --search

test_search_single_match_auto_fetches() {
    run_script -s 'declare and assign'
    assert_rc "single match exits 0" 0
    assert_stderr_contains "1 match info" "1 match: SC2155"
    assert_stdout_contains "fetched body" "Declare and assign separately"
}

test_search_multi_match_prints_rows() {
    run_script -s SC
    assert_rc "multi match exits 0" 0
    # All three index entries contain "SC", so all three should be printed
    assert_stdout_contains "row SC1000" "SC1000"
    assert_stdout_contains "row SC2086" "SC2086"
    assert_stdout_contains "row SC2155" "SC2155"
}

test_search_no_matches() {
    run_script -s 'definitely-not-in-index'
    assert_rc "no match exits 4" 4
    assert_stderr_contains "no match msg" "No matches"
}

test_search_eq_form() {
    run_script "--search=declare and assign"
    assert_rc "--search= exits 0" 0
    assert_stderr_contains "1 match via =" "1 match: SC2155"
}

# --list

test_list_dumps_index() {
    run_script --list
    assert_rc "list exits 0" 0
    assert_stdout_contains "list SC1000" "SC1000"
    assert_stdout_contains "list SC2155" "SC2155"
    assert_stdout_contains "list SC2086" "SC2086"
}

# Cache behavior

test_cache_reused_across_calls() {
    run_script --list
    assert_rc "first list exits 0" 0
    assert_stderr_contains "first call refreshes" "Refreshing index"

    run_script --list
    assert_rc "second list exits 0" 0
    assert_stderr_not_contains "second call uses cache" "Refreshing index"
}

test_refresh_forces_refetch() {
    run_script --list
    run_script --refresh --list
    assert_rc "refresh exits 0" 0
    assert_stderr_contains "refresh refetches" "Refreshing index"
}

# Stale-cache fallback: cache exists but the network breaks

test_stale_cache_fallback_on_fetch_failure() {
    # Populate the cache normally
    run_script --list
    assert_rc "warmup exits 0" 0

    # Backdate the cache file so the next call thinks it is stale
    local cache_file="$TEST_DIR/cache/scdef/index.tsv"
    assert_file_exists "cache exists" "$cache_file"
    touch -t 200001010000 "$cache_file"

    # Force the next curl call to fail
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script --list
    assert_rc "stale fallback exits 0" 0
    assert_stderr_contains "stale warning" "using existing cache"
    assert_stdout_contains "still serves data" "SC2155"
}

test_no_cache_plus_fetch_failure() {
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
exit 7
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script --list
    assert_rc "no cache + fail exits 1" 1
    assert_stderr_contains "fetch failed err" "Fetch failed"
}

# Dependency error: no curl on PATH. We delete the shim and restrict PATH so
# the script's `command -v curl` check fails, even on systems with a real curl
# installed in /usr/bin

test_curl_missing_direct_lookup() {
    rm "$SHIM_DIR/curl"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        XDG_CACHE_HOME="$TEST_DIR/cache" \
        /bin/bash "$UNDER_TEST" SC2155 \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "curl missing exits 3" 3
    assert_stderr_contains "curl required" "curl is required"
}

# --url and --open need no fetch, so they should work with no curl at all
test_curl_missing_url_mode_still_works() {
    rm "$SHIM_DIR/curl"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        XDG_CACHE_HOME="$TEST_DIR/cache" \
        /bin/bash "$UNDER_TEST" -u SC2155 \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    assert_rc "url mode w/o curl exits 0" 0
    assert_stdout_contains "url mode prints url" "/SC2155"
}

# With a fresh cache, --list should not invoke curl at all -- the cache is
# served directly. Verified by replacing the curl shim with a stub that
# fails loudly if invoked
test_list_with_fresh_cache_skips_curl() {
    run_script --list
    assert_rc "warmup exits 0" 0

    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
echo "curl was called when cache should have been used" >&2
exit 99
SHIM
    chmod +x "$SHIM_DIR/curl"

    run_script --list
    assert_rc "list w/ fresh cache exits 0" 0
    assert_stderr_not_contains "curl untouched" "curl was called"
    assert_stdout_contains "list serves cache" "SC2155"
}

# Stale cache + missing curl: should warn and serve stale rather than failing
test_stale_cache_curl_missing_falls_back() {
    run_script --list
    assert_rc "warmup exits 0" 0

    # Backdate the cache so a refresh will be attempted
    local cache_file="$TEST_DIR/cache/scdef/index.tsv"
    touch -t 200001010000 "$cache_file"

    # Make curl non-discoverable via `command -v`: an executable stub at the
    # front of PATH is fine for `command -v`, but we want it to fail. Trick:
    # remove the shim entirely AND restrict PATH to just $SHIM_DIR plus a
    # dir with coreutils, so the real curl in /usr/bin is hidden but cat etc.
    # are still available. Easiest: keep the original PATH but shadow `curl`
    # as a fake builtin via a function -- not possible in a child process.
    # Pragmatic approach: the convention's pattern (rm shim + PATH=$SHIM_DIR)
    # strips coreutils too, so we use it but only for the prelude check
    rm "$SHIM_DIR/curl"
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR" \
        XDG_CACHE_HOME="$TEST_DIR/cache" \
        /bin/bash "$UNDER_TEST" --list \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
    # When PATH lacks coreutils too, `cat` will fail after the warn; we
    # verify the warning fired but cannot meaningfully check exit/stdout
    assert_stderr_contains "stale-curl-missing warns" "curl missing; using existing cache"
}

# --run ---

run_tests "$@"
