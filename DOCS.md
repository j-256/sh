# Documentation Guide

How to write a `<script>.md` doc for a script in this repo.

Every script is available at `https://toolio.sh/<script>` and its docs render at `https://toolio.sh/<script>.md.html`.

## Structure

Docs follow this order:

1. **Title** -- `# script-name`
2. **Pitch** -- one or two paragraphs: what it does, why you'd reach for it. No heading
3. **Quick start** (`## Quick start`) -- the single most common use case, copy-paste ready. If setup is required (env vars, tokens, certs), show what the output looks like first, then cover setup
4. **Common examples** (`## Common examples`) -- a few more patterns covering the next most useful things. Each with a bold one-liner description and a code block
5. **Feature sections** (conditional) -- deeper explanation of a major feature that needs more than an example to convey (e.g. verify-p12's Bearer-vs-Basic explainer, pin-dns's argument placement). Use `##` headings. Skip for simple scripts
6. `---`
7. **Reference** (`## Reference`) -- the lookup section. Subsections as needed:
   - `### All options` -- table with Flag and Description columns
   - `### Environment variables` (conditional) -- table
   - `### Exit codes` (conditional) -- table with Code and Meaning columns
   - `### Dependencies` -- what's required and when
   - `### Warnings` (conditional) -- common mistakes or constraints worth calling out

## Tone

Write for someone who found the script and wants to know if it solves their problem, then wants to use it immediately. Sell first, reference last. Examples should be realistic and copy-pasteable -- not `foo`/`bar` placeholders. Keep command and output in a single code block (`$ ` prefix for commands) -- separate blocks look disjointed when rendered.
