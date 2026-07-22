#!/bin/bash
# meta-comment-style.test.sh - Verify comments obey the no-trailing-terminator rule
#
# Cross-cutting meta-test (meta-*.test.sh): validates a convention across the
# whole script fleet rather than a single script. See TESTING.md.
#
# Enforces the CONVENTIONS.md Style rule:
#   "No trailing `.` or `!` on comments, even on multi-sentence ones."
#
# The rule is about the TRAILING terminator, mirroring the error-message rule it
# cites ("X failed. Run -h for usage" keeps the internal period, drops the
# trailing one). So a multi-line comment block is treated as one message:
#
#     # Reassemble the record: join boundaries, strip quotes. A clean       <- internal . OK
#     # record passes through untouched                                     <- block end, no .
#
# Only the block's FINAL line may not end in `.`/`!`. "Final" is mechanical --
# the next line is not itself a full-line comment (it's code, blank, or EOF).
# Internal lines (a comment follows) may end in `.` to separate sentences, which
# is the dominant style across the fleet and needs no prose-vs-fragment guess.
#
# Scope and deliberate non-goals:
#   - `.` and `!` only. The trailing-`:` rule (CONVENTIONS Style) has a
#     load-bearing-colon carveout (a `:` that introduces a following list of
#     comment lines is kept) that needs human judgment; linting it would
#     false-positive, so it is intentionally NOT checked here.
#   - Shebang (`#!`) is skipped.
#   - Ellipsis (`...`) and `etc.` are caught like any other trailing `.`; the
#     rule's intent is no script comment ends on a terminator. Reword to avoid.
#
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."

# Test bash scripts only: shebang must be /bin/bash or /usr/bin/env bash.
# Skips the .md/.sh/.json files at the repo root, and any subdirectories.
# Identical to the filter in meta-coverage.test.sh and meta-curl-pipe.test.sh
_is_bash_script() {
    local file="$1"
    [ -f "$file" ] || return 1
    case "$(basename "$file")" in *.md|*.sh|*.json) return 1 ;; esac
    local first_line; first_line="$(head -1 "$file")"
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash') return 0 ;;
        *) return 1 ;;
    esac
}

# Bash scripts to skip these checks, as a space-padded membership string
# (e.g. " foo bar "). Empty today: every bash script's comments conform. Add a
# name here only if a script genuinely needs a trailing comment terminator
EXCLUDE=" "
_is_excluded() { case "$EXCLUDE" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Print "line: text" for each block-final comment line ending in . or ! in the
# given file. A comment block is a run of consecutive full-line (^\s*#) comments;
# only its last line is "trailing". The shebang is skipped. No output = clean
_violations() {
    awk '
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                t = lines[i]; sub(/[[:space:]]+$/, "", t)
                if (t !~ /^[[:space:]]*#/) continue   # not a full-line comment
                if (t ~ /^#!/) continue               # shebang
                if (t !~ /[.!]$/) continue            # no trailing . or !
                nxt = lines[i+1]; sub(/[[:space:]]+$/, "", nxt)
                if (nxt ~ /^[[:space:]]*#/) continue  # block continues -> internal
                printf "%d: %s\n", i, t
            }
        }
    ' "$1"
}

test_all_scripts_comments_conform() {
    local script
    for script in "$REPO_DIR"/*; do
        _is_bash_script "$script" || continue
        local s; s="$(basename "$script")"
        _is_excluded "$s" && continue
        local hits; hits="$(_violations "$script")"
        # assert_eq gives a useful diff (the offending "line: text") on failure
        assert_eq "$s: no comment ends in a trailing . or !" "$hits" ""
    done
}

run_tests "$@"
