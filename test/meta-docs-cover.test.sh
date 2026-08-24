#!/bin/bash
# meta-docs-cover.test.sh - Verify the repository documentation cover
#
# Cross-cutting meta-test for the public documentation surface
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

REPO_DIR="$SCRIPT_DIR/.."
COVER_PATH="$REPO_DIR/docs/screenshots/cover.png"
MAX_COVER_BYTES=8388608
PNG_SIGNATURE="89504e470d0a1a0a"

test_documentation_cover_is_a_bounded_png() {
    assert_file_exists "documentation cover: present" "$COVER_PATH"
    [ -f "$COVER_PATH" ] || return

    local cover_bytes; cover_bytes="$(wc -c < "$COVER_PATH" | tr -d '[:space:]')"
    if [ "$cover_bytes" -le "$MAX_COVER_BYTES" ]; then
        _ok "documentation cover: within size limit"
    else
        _fail "documentation cover: exceeds size limit"
    fi

    local actual_signature; actual_signature="$(od -An -tx1 -N8 "$COVER_PATH" | tr -d '[:space:]')"
    assert_eq "documentation cover: PNG signature" "$actual_signature" "$PNG_SIGNATURE"
}

run_tests "$@"
