---
name: toolio
description: Working shell implementations of a few tasks that are easy to get subtly wrong by hand. Use when a task involves SPF records (include recursion, the 10-lookup limit, whether an IP is authorized), DKIM public keys in DNS, sending an HTTP request that looks like real Chrome, timing or comparing HTTP request latency, OAuth2 PKCE verifiers and S256 challenges, historical USD inflation, or recovering truncated Claude Code tool output.
---

# toolio

Seven tools from <https://toolio.sh>, each covering a task where a hand-rolled version is usually *subtly wrong* rather than merely longer. Reach for one when the row below matches what you're about to build with `dig`, `openssl`, `awk`, or `curl`.

This is not a general-purpose shell toolkit index. The catalog holds about forty more scripts, but most are conveniences for a human at a prompt – improvising an equivalent inline is fine for those. These seven are the ones where improvising produces a plausible answer that happens to be incorrect.

| Task | Tool | Why not hand-roll it |
|---|---|---|
| Is an IP authorized to send for a domain? Flatten, health-check, or tree an SPF record | `spf` | Resolves `include:` and `redirect=` recursively, counts the 10-lookup and 2-void limits, matches both IPv4 and IPv6 CIDRs, and expands `%{d}` macros |
| Get a DKIM public key out of DNS | `dkim-pubkey` | CNAME-fronted records (Sendgrid, Mailgun) make `dig +short TXT` return the CNAME target *and* the body on separate lines, and the key arrives split across quoted chunks that need rejoining |
| Send a request a server accepts as real Chrome, and/or pin a hostname to an IP | `pin-dns` | Sends the full client-hint and `Sec-Fetch-*` set in Chrome's own header order, and matches Chrome's TLS/JA3 and HTTP/2 fingerprint when `curl-impersonate` is installed. Pins DNS without touching `/etc/hosts` |
| Measure endpoint latency, or compare two URLs head-to-head | `curl-timing` | Repeated sampling with optional warmups, then IQR-based outlier detection. A single request or a naive mean misreads any noisy endpoint |
| Produce an OAuth2 PKCE verifier and its S256 challenge | `pkce` | base64url is not base64: padding stripped, `+/` mapped to `-_`. Getting it wrong yields a token rejection with no useful error text |
| What is a historical USD amount worth today | `inflate` | Fetches live BLS CPI data. Answering from model memory is guessing, and the CPI series is revised |
| Recover a Claude Code tool result that was truncated | `find-cc-tool-output` | Reads transcript JSONL under `~/.claude/projects`, then de-duplicates identical bodies across sessions so a repeated output lists once |

## Running them

Pipe the tool straight into bash – there is no install step:

```sh
curl -fsS https://toolio.sh/spf | bash -s -- find example.com 192.0.2.1
curl -fsS https://toolio.sh/pkce | bash
```

For anything you'll call more than once or twice, install it onto `$PATH` first and invoke it directly:

```sh
curl -fsS https://toolio.sh/get | bash -s -- spf pkce
spf find example.com 192.0.2.1
```

If a tool is already on `$PATH`, just run it.

## Flags

Read `<tool> -h` before the first call. Every script is fully self-documenting from `-h` alone – subcommands, flags, environment variables, exit codes, and dependencies. This file deliberately does not restate any of that, so there is nothing here to fall out of date.

`spf` also has per-verb help: `spf find -h`.

## Before you call one

- **`spf` exits 4 for a negative answer.** "This IP is not authorized" or "problems found" is a *correct result*, not a failure – the same way `grep` exits 1 on no match. Don't retry or report it as an error.
- **`curl-timing` writes log and stats files into the current directory** by default. Pass `--no-save` unless you want those artifacts.
- **`find-cc-tool-output` reads your own transcripts** under `~/.claude/projects`, so it only finds output from sessions on this machine.
- **Network and dependencies:** `spf` and `dkim-pubkey` need `dig`; `spf` needs `python3` for IPv6 matching only, and warns when it's missing rather than failing. `inflate`, `curl-timing`, and `pin-dns` need `curl` and network access. `pkce` needs `openssl`. `find-cc-tool-output` is entirely local.

## The rest of the catalog

`curl -fsS https://toolio.sh/get | bash` prints the live catalog, grouped by category. Worth a look when a task is a close miss for one of the rows above – but assume anything not listed here is a human-ergonomics tool, not a correctness one.
