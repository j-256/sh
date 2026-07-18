# Contributing

Notes for working on the scripts in this repo (whether you're a human or an agent). This is a hub: it points at the detailed conventions rather than restating them, so there's a single source of truth for each.

## Setup

```sh
git clone https://github.com/j-256/sh
cd sh
make setup         # activates the git hooks
```

`make setup` runs [`tests/install-hooks.sh`](tests/install-hooks.sh), which points git's `core.hooksPath` at [`tests/hooks/`](tests/hooks) so the tracked [`pre-commit`](tests/hooks/pre-commit) hook runs on every commit. To activate the hooks without make, run `tests/install-hooks.sh` directly; to remove them, `make uninstall` (or `tests/install-hooks.sh --uninstall`).

There are no runtime dependencies – the scripts target Bash 3.2 and stock POSIX tools. The [`Makefile`](Makefile) is just a thin task runner (`make test`, `make setup`, `make uninstall`); it needs only GNU Make and bash, both of which ship with macOS.

## Conventions

Every script is paired with a doc and a test, and follows a shared set of standards. Read the relevant file before adding or changing one:

- **Script standards** – [`CONVENTIONS.md`](CONVENTIONS.md): header shape, `$SCRIPT_NAME`, `--help`, exit codes, error messages, argument parsing, the source/execute wrapper, and the commit style.
- **Docs** – [`DOCS.md`](DOCS.md): how to write a `<script>.md` doc.
- **Tests** – [`TESTING.md`](TESTING.md): how to write a `<script>.test.sh`, plus the cross-cutting [meta-tests](TESTING.md#meta-tests) and the [pre-commit hook](TESTING.md#pre-commit-hook).

A new script needs all four to land together: the script, its `docs/<name>.md`, its `tests/<name>.test.sh`, and an entry in [`INDEX.md`](INDEX.md). The `meta-coverage` test enforces that this set stays complete.

## Before committing

```sh
make test          # runs the full suite (tests/test-runner.sh)
```

The pre-commit hook automatically runs the fast, static checks (currently the comment-style lint) on every commit, but it only covers a subset and can be bypassed with `git commit --no-verify`. Run `make test` yourself before pushing to catch everything – the hook is a convenience gate, not a substitute for the full suite.
