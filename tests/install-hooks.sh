#!/bin/bash
# install-hooks.sh - Activate this repo's tracked git hooks
#
# Points git's core.hooksPath at tests/hooks/, so the tracked pre-commit hook
# runs without copying anything into .git/hooks. Because the hooks are
# version-controlled, every clone activates the same set with one command, and
# edits take effect immediately -- no re-install. Usually run via `make setup`,
# but works standalone too.
#
# Usage:
#   tests/install-hooks.sh             Activate the hooks
#   tests/install-hooks.sh --uninstall   Restore git's default hooks path
#
# Run from anywhere inside the repo.

set -e

# Resolve to physical paths (pwd -P) so the prefix strip below works even when
# the repo is reached through a symlink: git rev-parse --show-toplevel always
# returns the resolved path, so the hooks dir must be resolved to match. The
# hooks live in the hooks/ subdir next to this script (tests/hooks/)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
hooks_dir="$(cd "$script_dir/hooks" && pwd -P)"
repo_root="$(cd "$(git -C "$script_dir" rev-parse --show-toplevel)" && pwd -P)"

# Store the hooks path relative to the repo root, so it stays valid no matter
# where the repo is checked out
rel="${hooks_dir#"$repo_root"/}"

case "${1-}" in
    --uninstall)
        git -C "$repo_root" config --unset core.hooksPath 2>/dev/null || true
        echo "Uninstalled: git hooks restored to the default (.git/hooks)."
        ;;
    "")
        git -C "$repo_root" config core.hooksPath "$rel"
        echo "Installed: core.hooksPath -> $rel"
        echo "The pre-commit hook now runs the static convention checks on every commit."
        echo "Bypass once with: git commit --no-verify"
        ;;
    *)
        echo "install-hooks.sh: unknown argument '$1' (use --uninstall or no argument)" >&2
        exit 2
        ;;
esac
