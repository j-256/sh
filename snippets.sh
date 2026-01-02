#!/usr/bin/env bash
#! tested in: GNU bash, version 5.2.15(1)-release (x86_64-apple-darwin22.1.0) | older versions and other shells will work but not guaranteed

##########################################################
# Snippets which may or may not be useful at some point. #
##########################################################

#region string.contains(substr)
# Returns 0 if $1 contains $2, otherwise returns 1
contains() {
    # If $1 contains $2, everything up to and including $2 will be removed and it will therefore no longer equal $1
    [ "${1#*"$2"}" != "$1" ]
}
#endregion



#region Bash bitmap/bitmask - multiple values in one integer
# There should be 64 bits to work with, which is:
# 8 numbers in [0,255] (8 bits each)
# 4 numbers in [0,65535] (16 bits each)
# 2 numbers in [0,4294967295] (32 bits each)
# (or any combination thereof)

# Configure bits per value (max values = 64/n)
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

printf 'max: %d\n\n' $max

echo $ev1
echo $ev2
echo $ev3
echo
#endregion


#region Dynamic positions
# Reinitialize bitmap
bitmap=0

# Define values to encode
values=(
    $v1
    $v2
    $v3
    150 #1
    # 149 #2
    # 148 #3
    # 147 #4
    # 146 #5
    # 145 #6
    # 144 #7
    # 143 #8
    # 142 #9
    # 141 #10
    # 140 #11
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
    [ $i -lt 9 ] || unset padding
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
# If $0 is the name of a shell rather than some other filename, presumably the script was sourced
# There are various methods with their own pros and cons
# $0 is /path/to/bash or -bash if sourced and ZSH_EVAL_CONTEXT contains "file" if sourced
_basename="${0##*'/'}"
if { [ "$BASH_VERSION" ] && [ "${_basename#'-'}" != "bash" ]; } || { [ "$ZSH_VERSION" ] && [ "${ZSH_EVAL_CONTEXT#*"file"}" = "$ZSH_EVAL_CONTEXT" ]; }; then
    echo "Executed"
fi
unset _basename
#endregion



#region cURL - all timing fields
curl_format="appconnect: %{time_appconnect}\nconnect: %{time_connect}\nnamelookup: %{time_namelookup}\npretransfer: %{time_pretransfer}\nredirect: %{time_redirect}\nstarttransfer: %{time_starttransfer}\ntotal: %{time_total}\n"
curl -sfS -w "$curl_format" -o /dev/null "$url"
#endregion



#region Check for script dependencies
func() {
    # Check for dependencies
    local dependencies="socat jq"
    local missing_deps=false
    local dependency
    for dependency in $dependencies; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            echo "Missing dependency: $dependency" >&2
            missing_deps=true
        fi
    done
    if $missing_deps; then
        echo "ERROR: Missing dependencies" >&2
        return 1
    fi
}
#endregion



#region Print a string n times
repeat() {
    printf "%$2s" | sed "s/ /$1/g"
}
hr() { # horizontal rule, as in <hr> in HTML
    _repeat '-' "$(tput cols)"
}
#endregion



#region Function/command skeleton - parameter handling, help, cleanup trap
shell_func() {
    # Array to compile positional arguments
    local args=()
    # OPTION 1: Read piped/redirected input as one long string
    [ -t 0 ] || args=("$(cat)")
    # OPTION 2: Read piped/redirected input as an array of lines
    [ -t 0 ] || while IFS= read -r; do args+=("$REPLY"); done
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
        # Fall back to empty string if tput is unavailable
        local s; [ -t 1 ] && s="$(tput smul 2>/dev/null || echo '')"
        local r; [ -t 1 ] && r="$(tput rmul 2>/dev/null || echo '')"
        echo "NAME"
        echo "  shell_func - do cool things"
        echo "SYNOPSIS"
        echo "  shell_func [-v] -r ${s}value${r} [-o [${s}value${r}]] [${s}args${r} ${s}...${r}]"
        echo "  shell_func -h"
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
        echo "[ERR] shell_func: $*" >&2
    }
    _warn() {
        echo "[WRN] shell_func: $*" >&2
    }
    _info() {
        echo "[INF] shell_func: $*"
    }

    local __old_trap; __old_trap="$(trap -p RETURN)"
    trap 'unset -f _show_help _verbose _error _warn _info; [ "$__old_trap" ] && eval "$__old_trap" || trap - RETURN' RETURN

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
                    opt_flag_optional=true
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
    if [ $max_args -ne 0 ] && [ ${#args[@]} -gt $max_args ]; then
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
}
#endregion
