# get

[View script](../scripts/get)

Pipeable installer for scripts from this repo. Instead of cloning or `curl`-ing scripts one at a time, pipe `get` into bash with the names you want and they land on your `$PATH`.

## Quick start

Install a few scripts:

    $ curl -fsS https://toolio.sh/get | bash -s -- tsd pin-dns inflate
    installed: tsd
    installed: pin-dns
    installed: inflate
    3 requested: 3 installed, 0 updated, 0 up to date, 0 failed

Run with no args to see the full catalog grouped by category:

    $ curl -fsS https://toolio.sh/get | bash
    Shell scripting
      prompt     Sourced interactive prompt with default value, placeholder, and Ctrl-C safety
      progress   Single-line progress bar with percentage completion
    ...

Re-running is the upgrade path. Unchanged files stay put; changed files are replaced atomically.

## Common examples

**Install everything:**

    curl -fsS https://toolio.sh/get | bash -s -- --all

**Custom install directory:**

    curl -fsS https://toolio.sh/get | INSTALL_DIR=~/bin bash -s -- tsd

**Install `get` itself so you don't have to pipe it next time:**

    curl -fsS https://toolio.sh/get | bash -s -- get
    # then later:
    get pin-dns

## Installing the agent skill

`--skill` installs the `toolio` agent skill instead of any script. The skill is a routing table for coding agents: it points at the handful of tools here where a hand-rolled version tends to be subtly wrong (SPF resolution, DKIM key extraction, PKCE challenges, and so on) and defers to each script's own `-h` for flags.

    $ get --skill
    installed: toolio -> /Users/you/.claude/skills/toolio
    installed: toolio -> /Users/you/.codex/skills/toolio
    2 skill locations: 2 installed, 0 updated, 0 up to date, 0 failed

With no `SKILL_DIR` set, every harness whose config directory already exists gets a copy – `~/.claude/skills/toolio/` for Claude Code and `~/.codex/skills/toolio/` for Codex. Both read the same `<name>/SKILL.md` layout, so one payload serves both, and a harness you don't use is skipped rather than created. If neither is present, `get` exits 2 and names `SKILL_DIR`.

To install somewhere specific, point `SKILL_DIR` at the skills *root* – the payload lands in a `toolio/` subdirectory of it:

    SKILL_DIR=~/.config/skills get --skill
    # -> ~/.config/skills/toolio/SKILL.md

Re-running upgrades in place, same as for scripts. `--skill` is standalone: it cannot be combined with script names or `--all`.

---

## Reference

### All options

| Flag | Description |
|------|-------------|
| (no args) | Print the catalog grouped by category, exit 0 |
| `<name>...` | Install each named script |
| `-a`, `--all` | Install every script in the catalog |
| `-s`, `--skill` | Install the `toolio` agent skill instead of any script |
| `-h`, `--help` | Show help |

### Environment variables

| Name | Default | Description |
|------|---------|-------------|
| `INSTALL_DIR` | `~/.local/bin` | Directory to install scripts into |
| `SKILL_DIR` | detected | Agent-skill root for `--skill`; the skill installs to `$SKILL_DIR/toolio`. When unset, each existing harness root is used (`~/.claude/skills`, `~/.codex/skills`) |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | All requested scripts installed/up-to-date (or list printed) |
| 1 | One or more scripts failed (network, write failure) |
| 2 | Argument error: unknown script, bad flag, `--all` combined with names, `--skill` combined with either, or no skill root found |
| 3 | Missing dependency: `curl` |

### Dependencies

`curl`. Also assumes `awk`, `mktemp`, `cmp`, `mv`, `chmod`, `mkdir` — all shebang-implied.

### Warnings

Re-running replaces any file whose content differs from the catalog version. If you've locally edited an installed script, back it up (e.g. via `bak`) before re-running `get`. The same applies to `--skill`: a locally edited `SKILL.md` is overwritten.
