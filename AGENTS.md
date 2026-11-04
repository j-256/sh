# Agent guidance

Read @CONTRIBUTING.md first. It is the hub for working in this repo, human or agent: setup, the doc + test + INDEX.md entry every script ships with, and test entrypoints. From there it links to the detailed standards: CONVENTIONS.md (script structure), DOCS.md (doc format), and TESTING.md (tests and meta-tests).

## Verification scope

Do not run the repository-wide full test suite for a localized script change. Use `make test ARGS="<script>"` and the applicable static or meta-tests, plus affected integration checks. Reserve bare `make test` for sweeping or cross-cutting changes affecting many scripts, shared runtime or test infrastructure, or an explicit user request. State the broad impact before choosing it. A commit, synchronization, or integration step does not require repeating unrelated tests; reuse still-valid passing evidence.
