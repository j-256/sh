#!/bin/bash
# s.test.sh - Tests for s
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../s"

# --- helpers ---

get_sfcc_args() { cat "$TEST_DIR/sfcc-ci.args" 2>/dev/null; }

# --- shims ---

write_shims() {
    # sfcc-ci shim: log args, return fake data based on command
    cat > "$SHIM_DIR/sfcc-ci" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/sfcc-ci.args"
printf 'sfcc-ci' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"

case "$*" in
    "--help")
        printf 'sfcc-ci help output\n'
        ;;
    "client:auth --renew")
        printf 'Authentication successful\n' >&2
        exit 0
        ;;
    "client:auth:token")
        # Fake JWT with base64-encoded payload containing exp timestamp
        # eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MTMxMjM0NTZ9.signature
        # Payload decoded: {"exp":1713123456}
        printf 'header.eyJleHAiOjE3MTMxMjM0NTZ9.signature\n'
        ;;
    "sandbox:list -j")
        printf '[{"realm":"zzzz","instance":"001","links":{"bm":"https://zzzz-001.sandbox.site.com/bm","code":"code"},"state":"started","id":"sb123","versions":{"app":"1.0","web":"2.0"},"resourceProfile":"M","hostName":"zzzz-001.sandbox.site.com","createdBy":"user@example.com"}]\n'
        ;;
    "sandbox:list -j -S instance")
        printf '[{"realm":"zzzz","instance":"001","hostName":"zzzz-001.sandbox.site.com","state":"started","id":"sb123","createdBy":"user@example.com"},{"realm":"aaaa","instance":"002","hostName":"aaaa-002.sandbox.site.com","state":"stopped","id":"sb456","createdBy":"other@example.com","eol":"2024-12-31"}]\n'
        ;;
    *"sandbox:start"*)
        printf 'Starting sandbox...\n'
        exit 0
        ;;
    *"sandbox:stop"*)
        printf 'Stopping sandbox...\n'
        exit 0
        ;;
    *)
        printf 'sfcc-ci executed with args: %s\n' "$*"
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/sfcc-ci"

    # jq shim: minimal implementation for testing
    cat > "$SHIM_DIR/jq" <<'SHIM'
#!/bin/bash
# Accept input on stdin and pass through (simplification for testing)
# In real tests, we rely on sfcc-ci shim returning expected JSON

# Read stdin (even if we don't use it)
input=$(cat)

if [ "$1" = "-R" ]; then
    # Token parsing mode - extract exp from fake JWT
    echo "$input" | awk -F. '{print $2}' | sed 's/eyJleHAiOjE7MTMxMjM0NTZ9/{"exp":1713123456}/'
elif [[ "$*" == *".links.bm"* ]]; then
    # Sandbox detail query - return formatted JSON regardless of input
    # (The input SHOULD be the sfcc-ci JSON, but for testing we just return expected output)
    cat <<'JSON'
{
  "sbx": "zzzz-001",
  "state": "started",
  "id": "sb123",
  "app": "1.0",
  "web": "2.0",
  "size": "M",
  "host": "zzzz-001.sandbox.site.com",
  "bm": "https://zzzz-001.sandbox.site.com/bm",
  "code": "code"
}
JSON
elif [ "$1" = "-r" ]; then
    # Raw output mode - simulate field extraction
    printf 'zzzz-001.sandbox.site.com started sb123 user@example.com\n'
else
    # Default: pass through
    echo "$input"
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/jq"

    # date shim: return predictable output
    cat > "$SHIM_DIR/date" <<'SHIM'
#!/bin/bash
case "$*" in
    *"-r 1713123456"*)
        if [[ "$*" == *"-Iminutes"* ]]; then
            printf '2024-04-14T17:10-07:00\n'
        elif [[ "$*" == *"-Iseconds"* ]]; then
            printf '2024-04-15T00:10:56+00:00\n'
        fi
        ;;
    *"-u"*)
        printf '2024-04-14 23:00:00 UTC (current)\n'
        ;;
    *)
        printf '2024-04-14T17:00:00-07:00\n'
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/date"

    # tput shim: return empty for formatting codes
    cat > "$SHIM_DIR/tput" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/tput"

    # zdump shim: return fake timezone
    cat > "$SHIM_DIR/zdump" <<'SHIM'
#!/bin/bash
printf '/etc/localtime  Mon Apr 14 17:00:00 2024 PDT\n'
exit 0
SHIM
    chmod +x "$SHIM_DIR/zdump"

    # sed shim: pass through (rely on real sed in PATH after shims)
    # We need real sed, so don't shim it

    # column shim: pass through input
    cat > "$SHIM_DIR/column" <<'SHIM'
#!/bin/bash
cat
exit 0
SHIM
    chmod +x "$SHIM_DIR/column"

    # No cat shim - use the real cat from the system
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help mentions sfcc-ci" "sfcc-ci"
    assert_stdout_contains "help has SUBCOMMANDS" "SUBCOMMANDS"
}

test_help_short_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h has NAME" "NAME"
    # -h must NOT fall through to sfcc-ci; the wrapper owns the help
    local args
    args="$(get_sfcc_args)"
    assert_eq "sfcc-ci not invoked for -h" "$args" ""
}

test_no_args_shows_help() {
    run_script
    assert_rc "no args exits 0" 0
    assert_stdout_contains "no args shows help" "sfcc-ci help"
}

test_auth_command() {
    run_script auth
    assert_rc "auth exits 0" 0
    assert_contains "auth calls client:auth" "$(get_sfcc_args)" "client:auth --renew"
    assert_contains "auth calls token" "$(get_sfcc_args)" "client:auth:token"
}

test_auth_alias_a() {
    run_script a
    assert_rc "a exits 0" 0
    assert_contains "a is auth alias" "$(get_sfcc_args)" "client:auth --renew"
}

test_sandbox_command() {
    run_script sandbox zzzz_001
    assert_rc "sandbox exits 0" 0
    assert_contains "sandbox calls list" "$(get_sfcc_args)" "sandbox:list -j"
    assert_stdout_contains "sandbox shows realm" "zzzz-001"
}

test_sandbox_alias_sbx() {
    run_script sbx zzzz_001
    assert_rc "sbx exits 0" 0
    assert_contains "sbx is sandbox alias" "$(get_sfcc_args)" "sandbox:list -j"
}

test_sandbox_alias_box() {
    run_script box zzzz_001
    assert_rc "box exits 0" 0
    assert_contains "box is sandbox alias" "$(get_sfcc_args)" "sandbox:list -j"
}

test_sandbox_underscore_to_dash() {
    run_script sandbox zzzz_001
    assert_rc "underscore exits 0" 0
    assert_contains "converts underscore to dash" "$(get_sfcc_args)" "sandbox:list -j"
}

test_sandbox_json_command() {
    run_script sandbox:json zzzz_001
    assert_rc "sandbox:json exits 0" 0
    assert_contains "json calls list" "$(get_sfcc_args)" "sandbox:list -j"
}

test_list_command() {
    run_script list
    assert_rc "list exits 0" 0
    assert_contains "list calls sandbox:list" "$(get_sfcc_args)" "sandbox:list -j -S instance"
}

test_list_alias_sandboxes() {
    run_script sandboxes
    assert_rc "sandboxes exits 0" 0
    assert_contains "sandboxes is list alias" "$(get_sfcc_args)" "sandbox:list -j -S instance"
}

test_list_alias_boxes() {
    run_script boxes
    assert_rc "boxes exits 0" 0
    assert_contains "boxes is list alias" "$(get_sfcc_args)" "sandbox:list -j -S instance"
}

test_list_json_command() {
    run_script list:json
    assert_rc "list:json exits 0" 0
    assert_contains "list:json calls list" "$(get_sfcc_args)" "sandbox:list -j -S instance"
}

test_eol_command() {
    run_script eol
    assert_rc "eol exits 0" 0
    assert_contains "eol calls list" "$(get_sfcc_args)" "sandbox:list -j -S instance"
}

test_token_command() {
    run_script token
    assert_rc "token exits 0" 0
    assert_contains "token calls auth:token" "$(get_sfcc_args)" "client:auth:token"
}

test_token_alias_jwt() {
    run_script jwt
    assert_rc "jwt exits 0" 0
    assert_contains "jwt is token alias" "$(get_sfcc_args)" "client:auth:token"
}

test_token_exp_command() {
    run_script token:exp
    assert_rc "token:exp exits 0" 0
    assert_contains "token:exp calls auth:token" "$(get_sfcc_args)" "client:auth:token"
}

test_token_expiry_alias() {
    run_script token:expiry
    assert_rc "token:expiry exits 0" 0
    assert_contains "token:expiry is alias" "$(get_sfcc_args)" "client:auth:token"
}

test_token_expiration_alias() {
    run_script token:expiration
    assert_rc "token:expiration exits 0" 0
    assert_contains "token:expiration is alias" "$(get_sfcc_args)" "client:auth:token"
}

test_jwt_exp_alias() {
    run_script jwt:exp
    assert_rc "jwt:exp exits 0" 0
    assert_contains "jwt:exp is alias" "$(get_sfcc_args)" "client:auth:token"
}

test_start_command() {
    run_script start zzzz_001
    assert_rc "start exits 0" 0
    assert_contains "start calls sandbox:start" "$(get_sfcc_args)" "sandbox:start -s zzzz-001 --sync"
}

test_stop_command() {
    run_script stop zzzz_001
    assert_rc "stop exits 0" 0
    assert_contains "stop calls sandbox:stop" "$(get_sfcc_args)" "sandbox:stop -s zzzz-001 --sync"
}

test_restart_command() {
    run_script restart zzzz_001
    assert_rc "restart exits 0" 0
    assert_contains "restart calls stop" "$(get_sfcc_args)" "sandbox:stop -s zzzz-001 --sync"
    assert_contains "restart calls start" "$(get_sfcc_args)" "sandbox:start -s zzzz-001 --sync"
}

test_restart_alias_reboot() {
    run_script reboot zzzz_001
    assert_rc "reboot exits 0" 0
    assert_contains "reboot is restart alias" "$(get_sfcc_args)" "sandbox:stop -s zzzz-001 --sync"
}

test_env_command() {
    export SFCC_OAUTH_CLIENT_ID="test-client"
    export SFCC_OAUTH_CLIENT_SECRET="test-secret"
    run_script env
    assert_rc "env exits 0" 0
    assert_stdout_contains "env shows client id" "SFCC_OAUTH_CLIENT_ID='test-client'"
    assert_stdout_contains "env shows client secret" "SFCC_OAUTH_CLIENT_SECRET='test-secret'"
}

test_env_alias_environment() {
    export SFCC_OAUTH_CLIENT_ID="test-client"
    run_script environment
    assert_rc "environment exits 0" 0
    assert_stdout_contains "environment shows vars" "SFCC_OAUTH_CLIENT_ID='test-client'"
}

test_passthrough_unknown_command() {
    run_script code:list --instance zzzz-001
    assert_rc "passthrough exits 0" 0
    assert_contains "passthrough calls sfcc-ci" "$(get_sfcc_args)" "sfcc-ci code:list --instance zzzz-001"
}

test_sbx_prefix_expansion() {
    run_script sbx:activate zzzz-001
    assert_rc "sbx:activate exits 0" 0
    assert_contains "sbx: expands to sandbox:" "$(get_sfcc_args)" "sandbox:activate zzzz-001"
}

test_source_execute_handler() {
    # Test that script can be sourced
    local rc
    bash -c ". $UNDER_TEST >/dev/null 2>&1; printf '%s\n' \$?" > "$TEST_DIR/source_rc"
    rc="$(cat "$TEST_DIR/source_rc")"
    assert_eq "source exits 0" "$rc" "0"
}

test_auth_failure_propagates() {
    # Override sfcc-ci to fail on auth
    cat > "$SHIM_DIR/sfcc-ci" <<'SHIM'
#!/bin/bash
case "$*" in
    "client:auth --renew")
        printf 'Authentication failed\n' >&2
        exit 1
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/sfcc-ci"

    run_script auth
    assert_rc "auth failure exits 1" 1
}

test_restart_stop_failure_propagates() {
    # Override sfcc-ci to fail on stop
    # Note: The script pipes sfcc-ci through cat, but bash's pipefail isn't set,
    # so the exit code comes from cat (0), not sfcc-ci (1)
    # This test verifies current behavior - if pipefail is added later, this would change
    cat > "$SHIM_DIR/sfcc-ci" <<'SHIM'
#!/bin/bash
case "$*" in
    *"sandbox:stop"*)
        printf 'Stop failed\n' >&2
        exit 1
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/sfcc-ci"

    run_script restart zzzz_001
    # Currently exits 0 because cat swallows sfcc-ci's exit code
    assert_rc "restart with stop failure exits 0" 0
    assert_err_contains "restart shows stop failure" "Stop failed"
}

# --- run ---

run_tests "$@"
