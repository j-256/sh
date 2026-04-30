#!/bin/bash
# curl-pipe.test.sh - Verify every script works when piped into bash
#
# Guards against two failures unique to `curl -s .../foo | bash`:
#
#   1. Empty ${BASH_SOURCE[0]} at top level. The tail sourced-check
#      `[ "${BASH_SOURCE[0]}" != "$0" ]` wrongly returns sourced, firing
#      `return` at top level: "return: can only `return' from a function".
#      Guard with `[ -n "${BASH_SOURCE[0]}" ]`.
#
#   2. ${BASH_SOURCE[0]} inside the wrapper function resolves to "bash"
#      (the interpreter reading stdin), so help/errors say "bash" instead
#      of the canonical name. Guard with a case fallback on SCRIPT_NAME.
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# Scripts to check. Excludes:
#   - render-md (doesn't use the wrapper-function boilerplate)
#   - snippets.sh (reference doc, not executable as-is)
#   - test-runner.sh (piping would recursively re-run the suite)
SCRIPTS=(
    bak cf-ddns cf-ips-subnets chrome-ua client-credentials
    colorize-url convert-size curl-timing dkim-pubkey dot-project
    dw-jwt explode find-zone-by-name gen-catalog generate-p12
    git-add-nonsub git-backup httpcode inflate install-bash
    notify ods-usage pin-dns pkce progress
    prompt propfind-p12 pwa-prereqs pwgen s
    screenshot-rename slow-server snippet spf-find-ip stats
    swap tsd unbak verify-p12
)

# Pipe a script's source into `bash -s -- -h`, capturing stdout/stderr/rc
# into $TEST_DIR. Simulates `curl -s URL | bash -s -- -h`.
pipe_script() {
    local script="$1"
    cat "$SCRIPT_DIR/$script" | /bin/bash -s -- -h \
        >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

test_all_scripts_pipe_cleanly() {
    local s
    local combined
    for s in "${SCRIPTS[@]}"; do
        pipe_script "$s"
        assert_rc "$s: pipe -h exits 0" 0
        assert_err_not_contains "$s: no 'return: can only' error" "return: can only"
        # Help-text header must reference the canonical script name, not
        # the interpreter (wrapper-function SCRIPT_NAME fallback). Scripts
        # may emit help on either stdout or stderr, so check both.
        combined="$(get_stdout)$(get_stderr)"
        assert_contains "$s: help mentions '$s'" "$combined" "$s"
        assert_not_contains "$s: help does not say 'bash'" "$combined" "  bash "
    done
}

run_tests "$@"
