#!/bin/bash
# colorize-url.test.sh - Tests for colorize-url
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../colorize-url"

# --- helpers ---

strip_ansi() {
    # Strip ANSI escape sequences from output for content testing
    sed 's/\x1b\[[0-9;]*m//g'
}

get_stdout_stripped() {
    get_stdout | strip_ansi
}

assert_has_ansi() {
    local label="$1"
    local output; output="$(get_stdout)"
    if printf '%s' "$output" | grep -q $'\033'; then
        _ok "$label"
    else
        _fail "$label: expected ANSI codes in output"
    fi
}

# --- shims ---

write_shims() {
    # tput shim: return underline codes
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
case "$1" in
    smul) printf '\033[4m' ;;
    rmul) printf '\033[24m' ;;
    *) exit 1 ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"

    # grep shim: pass through to real grep
    cat > "$SHIM_DIR/grep" <<'SHIM'
#!/bin/bash
exec /usr/bin/grep "$@"
SHIM
    chmod +x "$SHIM_DIR/grep"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
}

test_help_short() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
}

test_no_url_error() {
    run_script
    assert_rc "no url exits 2" 2
    assert_stderr_contains "error message" "[ERR][colorize-url] No URL provided"
}

test_simple_url() {
    run_script "https://example.com"
    assert_rc "simple url exits 0" 0
    assert_eq "simple url content" "$(get_stdout_stripped)" "https://example.com"
    assert_has_ansi "simple url has colors"
}

test_url_with_path() {
    run_script "https://example.com/path/to/resource"
    assert_rc "path url exits 0" 0
    assert_eq "path url content" "$(get_stdout_stripped)" "https://example.com/path/to/resource"
    assert_has_ansi "path url has colors"
}

test_url_with_trailing_slash() {
    run_script "https://example.com/"
    assert_rc "trailing slash exits 0" 0
    assert_eq "trailing slash content" "$(get_stdout_stripped)" "https://example.com/"
    assert_has_ansi "trailing slash has colors"
}

test_url_with_query_string() {
    run_script "https://example.com/path?key1=value1&key2=value2"
    assert_rc "query exits 0" 0
    assert_eq "query content" "$(get_stdout_stripped)" "https://example.com/path?key1=value1&key2=value2"
    assert_has_ansi "query has colors"
}

test_url_with_query_no_path() {
    run_script "https://example.com?key1=value1"
    assert_rc "query no path exits 0" 0
    assert_eq "query no path content" "$(get_stdout_stripped)" "https://example.com?key1=value1"
    assert_has_ansi "query no path has colors"
}

test_url_with_empty_query_value() {
    run_script "https://example.com?key1=&key2=value2"
    assert_rc "empty value exits 0" 0
    assert_eq "empty value content" "$(get_stdout_stripped)" "https://example.com?key1=&key2=value2"
    assert_has_ansi "empty value has colors"
}

test_url_with_query_key_no_equals() {
    run_script "https://example.com?key1&key2=value2"
    assert_rc "no equals exits 0" 0
    assert_eq "no equals content" "$(get_stdout_stripped)" "https://example.com?key1&key2=value2"
    assert_has_ansi "no equals has colors"
}

test_url_with_fragment() {
    run_script "https://example.com/path#section"
    assert_rc "fragment exits 0" 0
    assert_eq "fragment content" "$(get_stdout_stripped)" "https://example.com/path#section"
    assert_has_ansi "fragment has colors"
}

test_url_with_fragment_no_path() {
    run_script "https://example.com#section"
    assert_rc "fragment no path exits 0" 0
    assert_eq "fragment no path content" "$(get_stdout_stripped)" "https://example.com#section"
    assert_has_ansi "fragment no path has colors"
}

test_url_with_query_and_fragment() {
    run_script "https://example.com/path?key=value#section"
    assert_rc "query and fragment exits 0" 0
    assert_eq "query and fragment content" "$(get_stdout_stripped)" "https://example.com/path?key=value#section"
    assert_has_ansi "query and fragment has colors"
}

test_url_with_query_and_fragment_no_path() {
    run_script "https://example.com?key=value#section"
    assert_rc "query fragment no path exits 0" 0
    assert_eq "query fragment no path content" "$(get_stdout_stripped)" "https://example.com?key=value#section"
    assert_has_ansi "query fragment no path has colors"
}

test_url_http_scheme() {
    run_script "http://example.com/path"
    assert_rc "http exits 0" 0
    assert_eq "http content" "$(get_stdout_stripped)" "http://example.com/path"
    assert_has_ansi "http has colors"
}

test_url_with_port() {
    run_script "https://example.com:8080/path"
    assert_rc "port exits 0" 0
    assert_eq "port content" "$(get_stdout_stripped)" "https://example.com:8080/path"
    assert_has_ansi "port has colors"
}

test_url_with_subdomain() {
    run_script "https://api.subdomain.example.com/v1/resource"
    assert_rc "subdomain exits 0" 0
    assert_eq "subdomain content" "$(get_stdout_stripped)" "https://api.subdomain.example.com/v1/resource"
    assert_has_ansi "subdomain has colors"
}

test_url_complex_query() {
    run_script "https://example.com/search?q=test&page=2&sort=desc&filter="
    assert_rc "complex query exits 0" 0
    assert_eq "complex query content" "$(get_stdout_stripped)" "https://example.com/search?q=test&page=2&sort=desc&filter="
    assert_has_ansi "complex query has colors"
}

test_url_deep_path() {
    run_script "https://example.com/a/b/c/d/e/f"
    assert_rc "deep path exits 0" 0
    assert_eq "deep path content" "$(get_stdout_stripped)" "https://example.com/a/b/c/d/e/f"
    assert_has_ansi "deep path has colors"
}

test_url_encoded_characters() {
    run_script "https://example.com/path?key=%20value%21"
    assert_rc "encoded exits 0" 0
    assert_eq "encoded content" "$(get_stdout_stripped)" "https://example.com/path?key=%20value%21"
    assert_has_ansi "encoded has colors"
}

test_url_localhost() {
    run_script "http://localhost:3000/api/users"
    assert_rc "localhost exits 0" 0
    assert_eq "localhost content" "$(get_stdout_stripped)" "http://localhost:3000/api/users"
    assert_has_ansi "localhost has colors"
}

test_url_ip_address() {
    run_script "http://192.168.1.1/admin"
    assert_rc "ip exits 0" 0
    assert_eq "ip content" "$(get_stdout_stripped)" "http://192.168.1.1/admin"
    assert_has_ansi "ip has colors"
}

test_url_fragment_only() {
    run_script "https://example.com#top"
    assert_rc "fragment only exits 0" 0
    assert_eq "fragment only content" "$(get_stdout_stripped)" "https://example.com#top"
    assert_has_ansi "fragment only has colors"
}

test_url_empty_fragment() {
    run_script "https://example.com/path#"
    assert_rc "empty fragment exits 0" 0
    assert_eq "empty fragment content" "$(get_stdout_stripped)" "https://example.com/path#"
    assert_has_ansi "empty fragment has colors"
}

test_url_multiple_slashes_in_path() {
    run_script "https://example.com//double//slashes//path"
    assert_rc "double slashes exits 0" 0
    assert_eq "double slashes content" "$(get_stdout_stripped)" "https://example.com//double//slashes//path"
    assert_has_ansi "double slashes has colors"
}

test_url_special_chars_in_fragment() {
    run_script "https://example.com#section:subsection"
    assert_rc "special fragment exits 0" 0
    assert_eq "special fragment content" "$(get_stdout_stripped)" "https://example.com#section:subsection"
    assert_has_ansi "special fragment has colors"
}

test_url_question_in_fragment() {
    run_script "https://example.com#what?why"
    assert_rc "question in fragment exits 0" 0
    assert_eq "question in fragment content" "$(get_stdout_stripped)" "https://example.com#what?why"
    assert_has_ansi "question in fragment has colors"
}

test_url_no_path_with_trailing_slash() {
    run_script "https://example.com/"
    assert_rc "no path trailing slash exits 0" 0
    assert_eq "no path trailing slash content" "$(get_stdout_stripped)" "https://example.com/"
    assert_has_ansi "no path trailing slash has colors"
}

test_sourcing_with_args() {
    # Test that script can be sourced with args
    local out; out="$(bash -c 'source "$1" "https://example.com"' -- "$UNDER_TEST" 2>&1 | strip_ansi)"
    local rc=$?
    assert_eq "sourcing with args exits 0" "$rc" "0"
    assert_eq "sourcing with args content" "$out" "https://example.com"
}

# --- run ---

run_tests "$@"
