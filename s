#!/bin/bash
# s - sfcc-ci wrapper with convenient shortcuts and augmented output
#
# Usage:
#   s <subcommand> [args...]
#   s -h
#
# Runs augmented subcommands (a/auth, sbx, list, etc.) via sfcc-ci and
# falls through to sfcc-ci for anything unrecognized.

_s() {
    local SCRIPT_NAME; SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    case "$SCRIPT_NAME" in ""|bash|sh|zsh|dash) SCRIPT_NAME="s" ;; esac

    _show_help() {
        local s; [ -t 1 ] && s="$(tput smul 2>/dev/null || echo '')"
        local r; [ -t 1 ] && r="$(tput rmul 2>/dev/null || echo '')"
        echo "NAME"
        echo "  $SCRIPT_NAME - sfcc-ci wrapper with shortcuts and enhanced output"
        echo "SYNOPSIS"
        echo "  $SCRIPT_NAME ${s}subcommand${r} [${s}args${r}...]"
        echo "  $SCRIPT_NAME -h"
        echo "DESCRIPTION"
        echo "  Thin wrapper around the official sfcc-ci CLI that adds convenience"
        echo "  subcommands, human-readable output for common queries, and"
        echo "  translates 'sbx:' prefixes to 'sandbox:'. Any subcommand the"
        echo "  wrapper doesn't recognize falls through to sfcc-ci."
        echo ""
        echo "  With no args, prints sfcc-ci's own help (help is the natural default)."
        echo "SUBCOMMANDS"
        echo "  a, auth                  Authenticate (client credentials) and print"
        echo "                           token expiration in local and UTC time"
        echo "  sbx, sandbox, box ${s}inst${r}   Human-readable single-sandbox details"
        echo "                           (accepts zzzz_001 or zzzz-001)"
        echo "  sbx:json, sandbox:json   Raw JSON for a single sandbox"
        echo "  list, sandboxes, boxes   Tabular sandbox list (host/state/id/creator)"
        echo "  list:json, ...           Same list as JSON"
        echo "  eol                      List sandboxes with a TTL (auto-delete date)"
        echo "  token, jwt               Decode the JWT payload of the current token"
        echo "  token:exp, token:expiry  Show token expiration (local+UTC) vs. now"
        echo "  start ${s}inst${r}               Start a sandbox synchronously"
        echo "  stop ${s}inst${r}                Stop a sandbox synchronously"
        echo "  restart, reboot ${s}inst${r}     Stop then start a sandbox synchronously"
        echo "  env, environment         Print SFCC_* env vars and their values"
        echo "  sbx:${s}anything${r}             Shorthand for sandbox:${s}anything${r}"
        echo "  (anything else)          Passed through to sfcc-ci unchanged"
        echo "  -h, --help               Show this help message"
        echo "ENVIRONMENT"
        echo "  Inherits sfcc-ci's configuration (dw.json, SFCC_OAUTH_*, SFCC_LOGIN_URL,"
        echo "  SFCC_SANDBOX_API_HOST, SFCC_SCAPI_*, DEBUG, etc.). Run \`$SCRIPT_NAME env\`"
        echo "  to see all recognized variables and their current values."
        echo "EXIT STATUS"
        echo "  *  Pass-through from sfcc-ci (or jq, for subcommands that parse JSON)"
        echo "DEPENDENCIES"
        echo "  sfcc-ci, jq"
        echo "SEE ALSO"
        echo "  sfcc-ci --help"
    }

    __unset() {
        unset -f __unset _show_help
    }
    trap '__unset || echo "'"$SCRIPT_NAME"' trap failed!" >&2; trap - RETURN' RETURN

    case "$1" in
        -h|--help) _show_help; return 0 ;;
    esac

    local option="$1" && shift
    case "$option" in
        # Authenticate with client credentials using dw.json or environment variables
        # Prints expiration time in user's time zone after authenticating
        'a'|'auth')
            sfcc-ci client:auth --renew || return $?
            local exp; exp="$(sfcc-ci client:auth:token | jq -R -r 'split(".") | .[1] | @base64d | fromjson | .exp')"
            # TODO: Simplify date - use more format rather than sed
            local tz; tz="$(zdump /etc/localtime | sed 's/.* //g')"
            echo "Expires at $(tput smul)$(TZ="/etc/localtime" date -r "$exp" -Iminutes | sed "s/.*T//; s/[-+][0-9]\{2\}:[0-9]\{2\}/ $tz/")$(tput rmul) ($(TZ=UTC date -u -r "$exp" -Iseconds | sed 's/T/ /; s/+00:00/ UTC/'))"
        ;;
        # Get a single instance and print important fields in a human-readable format
        'sbx'|'sandbox'|'box')
            local instance="${1/_/-}" # zzzz_001 -> zzzz-001
            sfcc-ci sandbox:list -j \
              | jq -M --arg i "$instance" '.[] | select(.links.bm | contains($i)) | {sbx: "\(.realm)-\(.instance)", state, id, app: .versions.app, web: .versions.web, size: .resourceProfile, host: .hostName, bm: .links.bm, code: .links.code}' \
              | sed '
                  s/^ \{0,\}"//;         # Remove leading spaces and first double-quote of the key
                  s/": "\{0,1\}/: /;     # Remove double-quote after key and before value
                  s/"\{0,1\},\{0,1\}$//; # Remove trailing double-quote and comma
                  / \{0,\}[\{\}]/d;      # Delete lines with only spaces and curly braces' \
              | column -t
        ;;
        # Get a single instance and print the JSON object
        'sbx:json'|'sandbox:json'|'box:json')
            local instance="${1/_/-}" # zzzz_001 -> zzzz-001
            sfcc-ci sandbox:list -j \
              | jq -M --arg i "$instance" '.[] | select(.links.bm | contains($i))'
        ;;
        # List instances but only print the most important fields, space-delimited:
        #  hostname, state, id, createdBy
        'list'|'sandboxes'|'boxes'|'sbx:list'|'sandbox:list'|'box:list')
            sfcc-ci sandbox:list -j -S instance \
              | jq -r '.[] | "\(.hostName) \(.state) \(.id) \(.createdBy)"' \
              | column -t
        ;;
        # List instances as JSON
        'list:json'|'sandboxes:json'|'boxes:json'|'sbx:list:json'|'sandbox:list:json'|'box:list:json')
            sfcc-ci sandbox:list -j -S instance
        ;;
        # List sandboxes with a TTL set
        'eol')
            sfcc-ci sandbox:list -j -S instance | jq -r '.[] | select(has("eol")) | "\(.realm)-\(.instance) \(.eol) \(.state) \(.id) \(.createdBy)"' \
              | column -t
        ;;
        # Print details of current bearer token (payload section of JWT)
        'token'|'jwt')
            sfcc-ci client:auth:token \
              | jq -R 'split(".") | .[1] | @base64d | fromjson'
        ;;
        # Check when your current access token expires (also prints current time for comparison)
        'token:exp'|'token:expiry'|'token:expiration'|'jwt:exp'|'jwt:expiry'|'jwt:expiration')
            sfcc-ci client:auth:token \
              | jq -R -r  'split(".") | .[1] | @base64d | fromjson | .exp | todateiso8601' \
              | sed 's/T/ /; s/Z/ UTC/; s/$/ (expires)/'
            # To include issued timestamp too:
            # | jq -R -r 'split(".") | .[1] | @base64d | fromjson | .iat, .exp | todateiso8601' \
            # | sed 's/T/ /; s/Z/ UTC/; 1s/$/ (issued)/; 2s/$/ (expires)/'
            TZ=UTC date -u "+%Y-%m-%d %H:%M:%S UTC (current)"
        ;;
        # Start an instance, waiting for it to finish (--sync)
        # FORCE_COLOR=0 disables chalk's coloring in sfcc-ci so output lands
        # in the default terminal color (sfcc-ci would otherwise emit gray).
        'start')
            local instance="${1/_/-}" # zzzz_001 -> zzzz-001
            FORCE_COLOR=0 sfcc-ci sandbox:start -s "$instance" --sync
        ;;
        # Stop an instance, waiting for it to finish (--sync)
        'stop')
            local instance="${1/_/-}" # zzzz_001 -> zzzz-001
            FORCE_COLOR=0 sfcc-ci sandbox:stop -s "$instance" --sync
        ;;
        # Restart an instance synchronously (--sync), waiting for both start and stop
        'restart'|'reboot')
            local instance="${1/_/-}" # zzzz_001 -> zzzz-001
            FORCE_COLOR=0 sfcc-ci sandbox:stop -s "$instance" --sync \
                && FORCE_COLOR=0 sfcc-ci sandbox:start -s "$instance" --sync
        ;;
        # Print all relevant environment variables and their values
        'env'|'environment')
            local vars=(SFCC_LOGIN_URL
                        SFCC_OAUTH_LOCAL_PORT
                        SFCC_OAUTH_CLIENT_ID
                        SFCC_OAUTH_CLIENT_SECRET
                        SFCC_OAUTH_USER_NAME
                        SFCC_OAUTH_USER_PASSWORD
                        SFCC_SANDBOX_API_HOST
                        SFCC_SANDBOX_API_POLLING_TIMEOUT
                        SFCC_SCAPI_SHORTCODE
                        SFCC_SCAPI_TENANTID
                        DEBUG)
            for var in "${vars[@]}"; do
                echo "$var='$(eval printf '%s\\n' "\${$var}")'"
            done
        ;;
        '') # If no option provided, show help
            # We can't let it fall through to * because then we end up passing two empty strings,
            # which the shell (rightfully) differentiates from one empty string
            sfcc-ci --help
        ;;
        *)
            # Allow "sbx:" as a shorthand for "sandbox:"
            option="$(printf %s "$option" | sed 's/^sbx:/sandbox:/g')"
            sfcc-ci "$option" "$@"
        ;;
    esac
}

_s "$@"
__s_rc=$?
unset -f _s
if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
    eval "unset __s_rc; return $__s_rc"
fi
eval "unset __s_rc; exit $__s_rc"
