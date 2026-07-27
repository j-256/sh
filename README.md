# sh

A mixed collection of small shell utilities I've written over the years to make my own life easier. Some are broadly useful; plenty are niche to my own workflow. Every script has a doc, and every bash script has a test.

- Browse the catalog: [INDEX.md](INDEX.md) – rendered at <https://toolio.sh>
- Rendered docs: `https://toolio.sh/<script>.md.html` (e.g. [tsd](https://toolio.sh/tsd.md.html))
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md) – setup, conventions, and tests
- Conventions: [CONVENTIONS.md](CONVENTIONS.md), [DOCS.md](DOCS.md), [TESTING.md](TESTING.md)

## Some picks

A few that might be worth a look before you scroll the catalog. These are mostly the ones where the script does something non-obvious or solves a recurring annoyance.

- [`prompt`](docs/prompt.md) ([script](scripts/prompt)) – sourced interactive prompt with default value and placeholder
- [`tsd`](docs/tsd.md) ([script](scripts/tsd)) – paste any number, get back a timestamp or a duration
- [`inflate`](docs/inflate.md) ([script](scripts/inflate)) – historical USD amounts adjusted for inflation
- [`pin-dns`](docs/pin-dns.md) ([script](scripts/pin-dns)) – curl wrapper that overrides DNS without touching `/etc/hosts`, and impersonates a real Chrome: full headers by default, plus TLS/JA3 fingerprint when `curl-impersonate` is installed
- [`curl-timing`](docs/curl-timing.md) ([script](scripts/curl-timing)) – time HTTP requests and compare URLs head-to-head
- [`explode`](docs/explode.md) ([script](scripts/explode)) – move a directory's contents up one level after a nested-folder unzip

## Usage

Every script is a one-liner away – no install step. Pipe it straight into bash:

    curl -fsS https://toolio.sh/tsd | bash -s -- 1800
    curl -fsS https://toolio.sh/inflate | bash -s -- 150 1970

The exceptions are [`prompt`](docs/prompt.md) and [`dbg`](docs/dbg.md), which must be sourced so they can read from (and, for `prompt`, write to) your shell. For a one-shot run without installing:

    . <(curl -fsS https://toolio.sh/prompt) name "Name: "
    . <(curl -fsS https://toolio.sh/dbg) name

## Installation

To put scripts on your `$PATH` for repeated use, pipe [`get`](docs/get.md) to bash with the names you want:

    curl -fsS https://toolio.sh/get | bash -s -- tsd pin-dns inflate

Run with no args to see what's available:

    curl -fsS https://toolio.sh/get | bash

Scripts install to `~/.local/bin` by default; override with e.g. `INSTALL_DIR=~/bin`. See [`get`](docs/get.md) for the full reference.

### Or, manually

If you'd rather not pipe to bash:

    curl -fsS https://toolio.sh/tsd -o ~/.local/bin/tsd
    chmod +x ~/.local/bin/tsd

## For coding agents

A few of these tools cover tasks where an improvised version is usually subtly wrong rather than merely longer – SPF include recursion and lookup limits, DKIM keys split across TXT chunks, base64url for PKCE, live CPI data for inflation. [`skills/toolio/SKILL.md`](skills/toolio/SKILL.md) is an agent skill that routes those tasks to the right script and otherwise defers to each script's `-h`:

    curl -fsS https://toolio.sh/get | bash -s -- --skill

That installs into every harness present – `~/.claude/skills/toolio/` for Claude Code, `~/.codex/skills/toolio/` for Codex – since both read the same layout. Override the destination with `SKILL_DIR`. It is deliberately narrow: the rest of the catalog is conveniences for a human at a prompt, which an agent can improvise safely.

## License
[AGPL-3.0-only](LICENSE). Copying a script out of here and into your own dotfiles is exactly what it is for; redistributing a modified catalog, or running one as a network service, carries the obligation to share those changes.

## Notes
macOS ships with an ancient (2007) version of Bash, but every script in this repo targets Bash 3.2, so they run on stock macOS without [Homebrew](https://brew.sh) or a shebang swap. The reason it's that old: Bash moved from GPLv2 to a license that demands more openness from distributors – _"GPLv3 is to Silicon Valley as garlic is to vampires"_. Without opening up their own software, Apple cannot distribute Bash 4.0+ with their OS, which is also why recent versions of macOS have `zsh` as the default interpreter/shell.  

Fun fact: `/bin/sh` is effectively a symlink to run `/bin/bash --posix` – it doesn't actually run the [Bourne shell](https://en.wikipedia.org/wiki/Bourne_shell).  
```sh
$ /bin/sh --version
GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin23)
Copyright (C) 2007 Free Software Foundation, Inc.
```
