#!/usr/bin/env bash
#! tested in: GNU bash, version 5.2.15(1)-release (x86_64-apple-darwin22.1.0) | older versions and other shells will work but not guaranteed

##########################################################
# Snippets which may or may not be useful at some point. #
##########################################################


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

# 1
# Check whether $0 equals the basename of $SHELL (which should be the path to the currently-running shell)
if [ "${0//-}" != "$(basename "$SHELL")" ]; then
    echo "This script has been executed."
fi

# 2
# Quite slow given the amount of I/O
# Check whether $0 equals the basename of any lines in /etc/shells (the allowed shells)
SOURCED=''
while IFS= read -r line; do
    # We have to basename $line because $0 isn't a full path, from testing
    # Bash's $0 is "-bash" for some reason, so remove hyphens
    if [ "${0//-}" = "$(basename "$line")" ]; then
        SOURCED=true
    fi
done < "/etc/shells"
[ $SOURCED = true ] || echo "This script has been executed."
#endregion



#region cURL - all timing fields
curl_format="appconnect: %{time_appconnect}\nconnect: %{time_connect}\nnamelookup: %{time_namelookup}\npretransfer: %{time_pretransfer}\nredirect: %{time_redirect}\nstarttransfer: %{time_starttransfer}\ntotal: %{time_total}\n"
curl -sS -w "$curl_format" -o /dev/null "$url"
#endregion
