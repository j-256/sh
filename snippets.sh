#!/bin/bash
# snippets.sh - reference patterns to copy-paste from when writing new scripts
#
# Not meant to be executed as-is; many regions assume variables that don't exist
# here, some print demo output, and the find example would traverse your home
# Open it, find the pattern you need, copy it

#region string.contains(substr)
# Returns 0 if $1 contains $2, otherwise returns 1
contains() {
    # If $1 contains $2, everything up to and including $2 will be removed and it will therefore no longer equal $1
    [ "${1#*"$2"}" != "$1" ]
}
#endregion



#region Bash bitmap/bitmask - multiple values in one integer
# Bash integers are signed 64-bit, so 63 bits are safely available for packed
# values -- writing to the top bit wraps the whole number negative, which
# breaks extraction (bash right-shift is arithmetic, not logical). With `n`
# bits per slot, you get floor(63/n) slots of values in [0, 2^n - 1]
#   n= 1 -> 63 slots, [0,1]              (pure boolean flags)
#   n= 2 -> 31 slots, [0,3]
#   n= 4 -> 15 slots, [0,15]
#   n= 8 ->  7 slots, [0,255]
#   n=16 ->  3 slots, [0,65535]
#   n=32 ->  1 slot,  [0,4294967295]
# Or any mix of widths, as long as the total never exceeds 63 bits

# Configure bits per value (max values = floor(63/n))
n=8

# Calculate max quantity per value, for masking/shifting
max=$(((1 << n) - 1))
#max=$(((2 ** n) - 1)) # equivalent to above


#region Static positions
# Initialize bitmap
bitmap=0

# Generate values
v1=$((max-0))
v2=$((max-1))
v3=$((max-2))

bitmap=$(( bitmap | (v1 & max) << 0*n ))
bitmap=$(( bitmap | (v2 & max) << 1*n ))
bitmap=$(( bitmap | (v3 & max) << 2*n ))

# Extract values from the bitmap
ev1=$(( bitmap >> 0*n & max ))
ev2=$(( bitmap >> 1*n & max ))
ev3=$(( bitmap >> 2*n & max ))

printf 'max: %d\n\n' "$max"

echo "$ev1"
echo "$ev2"
echo "$ev3"
echo
#endregion


#region Dynamic positions
# Reinitialize bitmap
bitmap=0

# Define values to encode. n=8 gives 7 slots; v1/v2/v3 take three, leaving
# room for up to four more before the 64th bit flips the number negative and
# extraction breaks
values=(
    "$v1"
    "$v2"
    "$v3"
    150 #1
    # 149 #2
    # 148 #3
    # 147 #4
)

# Construct bitmap
for ((i = 0; i < ${#values[@]}; i++)); do
    # Extra parentheses to make order of operations obvious
    bitmap=$(( bitmap | ((values[i] & max) << i*n) ))
    #bitmap=$(( bitmap | (values[i] & max) << i*n ))
done

# Extract values from bitmap
for ((i = 0; i < ${#values[@]}; i++)); do
    # Extra parentheses to make order of operations obvious
    extracted_value=$(( (bitmap >> i*n) & max ))
    #extracted_value=$(( bitmap >> i*n & max ))
    padding=0 # quick-n-dirty 0-padding works up to 99
    [ "$i" -lt 9 ] || unset padding
    echo "$padding$((i + 1)): $extracted_value"
done
#endregion


#region Mask explanation
: <<'INFO'
`& ((1 << n) - 1)` or `& max`
Uses bitwise operations to ensure that only the rightmost n bits of a number are considered, effectively creating a mask for the lower n bits.
"(1 << n) - 1" is the highest integer which can be stored in n bits
(1 << n): Performs a left shift operation. It shifts the binary representation of 1 to the left by n positions. In other words, it creates a binary number with a single '1' bit at the n-th position from the right. For example, if n is 3, this expression would result in 0b1000.
((1 << n) - 1): Subtracts 1 from the result of the left shift. This has the effect of setting all bits to the right of the n-th bit to '1'. In binary, subtracting 1 from a power of 2 flips all the bits to the right of the rightmost '1'. For example, if n is 3, this expression would result in 0b111.
&: Effectively masks the original value, keeping only the rightmost n bits and setting all bits to the left of the n-th bit to 0.

1 << 8 == 2 ** 8
1 << n == 2 ** n
INFO
#endregion
#endregion



#region Detect sourced or executed (`. script`/`source script` vs `script`)
# When sourced by bash, $0 is "/path/to/bash" or "-bash"
# When sourced by zsh, ZSH_EVAL_CONTEXT contains "file"
_basename="${0##*'/'}"
if { [ "$BASH_VERSION" ] && [ "${_basename#'-'}" != "bash" ]; } || { [ "$ZSH_VERSION" ] && [ "${ZSH_EVAL_CONTEXT#*"file"}" = "$ZSH_EVAL_CONTEXT" ]; }; then
    echo "was executed"
else
    echo "was sourced"
fi
unset _basename
#endregion



#region cURL - all timing fields
curl_format="appconnect: %{time_appconnect}\nconnect: %{time_connect}\nnamelookup: %{time_namelookup}\npretransfer: %{time_pretransfer}\nredirect: %{time_redirect}\nstarttransfer: %{time_starttransfer}\ntotal: %{time_total}\n"
# shellcheck disable=SC2154 # "var is referenced but not assigned." -- $url is a placeholder for the caller's URL
curl -sfS -w "$curl_format" -o /dev/null "$url"
#endregion



#region Check for script dependencies
dependencies="socat jq"
missing_deps=false
for dependency in $dependencies; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "Missing dependency: $dependency" >&2
        missing_deps=true
    fi
done
if $missing_deps; then
    echo "ERROR: Missing dependencies" >&2
    return 1 # or exit 1 when not in a function
fi
#endregion



#region Print a string n times
repeat() {
    printf "%$2s" | sed "s/ /$1/g"
}
hr() { # horizontal rule, as in <hr> in HTML
    repeat '-' "$(tput cols)"
}
#endregion



#region Function/command skeleton - parameter handling, help
# Wrapper body is a subshell `( ... )`, not braces. Helpers, locals, traps,
# and any shell state set inside die with the subshell on return. `return N`
# still propagates as the function's exit status, so source/execute dispatch
# at the bottom of a real script works unchanged. For a script that needs to
# mutate the caller's shell (`prompt`, `dbg`), use a `{ ... }` body and the
# cleanup-trap pattern -- see CONVENTIONS.md "Source-only scripts"
shell_func() (
    # ${BASH_SOURCE[0]} resolves to the *definition file*, which is what you want
    # for a standalone script. For a function pasted into ~/.bash_profile or
    # similar, replace this with `local SCRIPT_NAME="shell_func"` -- otherwise it
    # will identify itself as ".bash_profile" in help/error output
    local SCRIPT_NAME; SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    # Pipe invocation (curl ... | bash) has no filename: inside a function
    # ${BASH_SOURCE[0]} is the interpreter ("bash"); at top level it's empty
    # Fall back to the canonical name so help/errors aren't "bash: ..."
    case "$SCRIPT_NAME" in ""|bash|sh|zsh|dash) SCRIPT_NAME="shell_func" ;; esac
    # Positional arguments. `[ -t 0 ]` is true when stdin is a terminal; negate
    # it to detect piped/redirected input -- each line becomes another arg
    # The `|| [ -n "$line" ]` clause appends the final line when stdin lacks a
    # trailing newline, which would otherwise cause read to return non-zero and
    # exit the loop with the last line still unread
    # (For whole-stdin-as-content, use `local stdin; [ -t 0 ] || stdin="$(cat)"` instead.)
    local args=()
    local line
    [ -t 0 ] || while IFS= read -r line || [ -n "$line" ]; do args+=("$line"); done
    # Allow n positional args, 0 for infinite
    local max_args=0
    # If true, print extra information
    local verbose=false
    # Required argument, guaranteed a value later
    local opt_val_required
    # If true, the optional argument was specified by the caller
    local opt_flag_optional=false
    local opt_val_optional="default_value"

    # Print usage (help) info - below mimics the format of most manpages
    _show_help() {
        # Underline only if output is a terminal (not a pipe or file)
        local s; [ -t 1 ] && s=$'\033[4m'
        local r; [ -t 1 ] && r=$'\033[24m'
        echo "NAME"
        echo "  $SCRIPT_NAME - do cool things"
        echo "SYNOPSIS"
        echo "  $SCRIPT_NAME [-v] -r ${s}value${r} [-o [${s}value${r}]] [${s}args${r} ${s}...${r}]"
        echo "  $SCRIPT_NAME -h"
        echo "OPTIONS"
        echo "  -r, --val-required ${s}value${r}    Specify an option, ${s}value${r} required"
        echo "  -o, --val-optional [${s}value${r}]  Specify an option, ${s}value${r} optional"
        echo "  -v, --verbose               Enable verbose output"
        echo "  -h, --help                  Show this help message"
    }

    # True if verbose flag is set
    _verbose() { [ "$verbose" = true ]; }

    # Print user messages with prefix
    _error() {
        echo "[ERR] $SCRIPT_NAME: $*" >&2
    }
    _warn() {
        echo "[WRN] $SCRIPT_NAME: $*" >&2
    }
    _info() {
        echo "[INF] $SCRIPT_NAME: $*"
    }

    # Parse parameters
    while [ $# -gt 0 ]; do
        case "$1" in
            # Handle verbose first in case it is used during arg parsing
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                _show_help
                return 0
                ;;
            -r|--val-required)
                # This option must be followed by a value, so use $2 even if it starts with a dash, unlike with -o
                if [ "${2+x}" ]; then # recognize an empty string as set
                    opt_val_required="$2"
                    shift 2
                else
                    _error "Missing value for option '$1'."
                    return 1
                fi
                ;;
            -o|--val-optional)
                opt_flag_optional=true
                # If a value follows the key which doesn't begin with a dash, use it,
                # otherwise interpret it as the next option and move on
                if [ "$2" ] && [ "${2#'-'}" = "$2" ]; then
                    opt_val_optional="$2"
                    shift
                else
                    _verbose && _warn "No value provided for $1"
                fi
                shift
                ;;
            # End of options, parse remainder as positional
            --)
                shift # discard "--"
                while [ $# -gt 0 ]; do
                    args+=("$1")
                    shift
                done
                ;;
            # Unknown option
            -*)
                _error "Unknown option '$1'."
                return 1
                ;;
            # Positional argument
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Ensure mandatory arguments have been provided - absence of ${+x} disallows empty strings
    if [ -z "$opt_val_required" ]; then
        _error "-r, --val-required is required"
        return 1
    fi

    # Check positional arg quantity outside of loop to avoid having two different error messages for -- and *
    if [ "$max_args" -ne 0 ] && [ "${#args[@]}" -gt "$max_args" ]; then
        _error "Only $max_args positional arguments allowed. Provided: ${#args[@]}."
        return 1
    fi

    # Debug output (if verbose is enabled)
    _verbose && _info "This is verbose" >&2

    # Replace with function logic
    echo "opt_val_required: $opt_val_required"
    echo "opt_flag_optional: $opt_flag_optional"
    echo "opt_val_optional: $opt_val_optional"
    echo "verbose: $verbose"
    echo "Positional parameters: $(printf '[%s] ' "${args[@]}")"
)
#endregion



#region jq - extract multiple fields into bash variables (single jq call)
# @tsv outputs tab-separated values; IFS=$'\t' prevents splitting on spaces in values
# name/version/count and $json are placeholders -- in real use the caller supplies
# $json and consumes name/version/count afterwards
# shellcheck disable=SC2034,SC2154 # "foo appears unused. Verify it or export it." / "var is referenced but not assigned." -- reference snippet: name/version/count are consumed by the caller and $json is supplied by the caller, neither visible in this excerpt
IFS=$'\t' read -r name version count \
    < <(jq -r '[
        (.name // ""),
        (.version // 0 | floor),
        (.items | length)
    ] | @tsv' <<< "$json")
#endregion



#region find with -prune
# Traverses the tree under the target directory, skipping listed paths entirely,
# then runs -exec on the files that remain. Swap the target and -iname/-exec to
# taste
find -L /path/to/dir \
    \( \
        -ipath '*/node_modules/*' \
        -o -ipath '*/cache/*' \
        -o -ipath '*/tmp/*' \
    \) -prune \
    -o -iname '*.bak' -exec trash -v {} +
#endregion
