# get

[View script](../get)

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

---

## Reference

### All options

| Flag | Description |
|------|-------------|
| (no args) | Print the catalog grouped by category, exit 0 |
| `<name>...` | Install each named script |
| `--all` | Install every script in the catalog |
| `-h`, `--help` | Show help |

### Environment variables

| Name | Default | Description |
|------|---------|-------------|
| `INSTALL_DIR` | `~/.local/bin` | Directory to install into |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | All requested scripts installed/up-to-date (or list printed) |
| 1 | One or more scripts failed (network, write failure) |
| 2 | Argument error: unknown script, bad flag, `--all` combined with names |
| 3 | Missing dependency: `curl` |

### Dependencies

`curl`. Also assumes `awk`, `mktemp`, `cmp`, `mv`, `chmod`, `mkdir` — all shebang-implied.

### Warnings

Re-running replaces any file whose content differs from the catalog version. If you've locally edited an installed script, back it up (e.g. via `bak`) before re-running `get`.
