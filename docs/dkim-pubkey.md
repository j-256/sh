# dkim-pubkey

[View script](../dkim-pubkey)

Extract the base64-encoded public key from a DKIM DNS record.

DKIM records are published as TXT records at `<selector>._domainkey.<domain>`. This script queries that record, parses the response, and extracts just the public key value (the `p=` field) -- useful when you need to verify DKIM signatures, audit email authentication setup, or compare keys across selectors.

The raw DNS response goes to stderr so you can see what came back; the extracted key goes to stdout so you can pipe it to other tools.

## Quick start

```
$ dkim-pubkey s1 github.com
$ dig +short TXT "s1._domainkey.github.com"
s1.domainkey.u51742174.wl175.sendgrid.net.
"k=rsa; t=s; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyn3fMCVpb7ryIRKOGXhXVGYmsWUitNlSckqGHOwNFZgFadplOrD+Qzf1XQkP7MH/VB/97DsAAJGtEXW1Uq71Hjnfr/DuBN/YfjF/gU70qEFb7q1sdIiNtjFL2TkOpoW+X/bhhPNheW/fYwyFb6ZHFM6LTgXyuimWRHTOUP3VjZzhNVda79nt+2WZYbS4l8HdMgWpT" "NHjpVw5PtXESA9KBg/evSRk5fIaXIX5eRXW3baoV9yVzD8O29/IL/DiSk+yNvaO0EHL5c4yGuZJhGzvpiznb2IDVdemJK4Dqzdy5FTN/SGYZhAEr7MguG3Z314hMS2scgMsOMgB64uj/6+6UwIDAQAB"

MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyn3fMCVpb7ryIRKOGXhXVGYmsWUitNlSckqGHOwNFZgFadplOrD+Qzf1XQkP7MH/VB/97DsAAJGtEXW1Uq71Hjnfr/DuBN/YfjF/gU70qEFb7q1sdIiNtjFL2TkOpoW+X/bhhPNheW/fYwyFb6ZHFM6LTgXyuimWRHTOUP3VjZzhNVda79nt+2WZYbS4l8HdMgWpTNHjpVw5PtXESA9KBg/evSRk5fIaXIX5eRXW3baoV9yVzD8O29/IL/DiSk+yNvaO0EHL5c4yGuZJhGzvpiznb2IDVdemJK4Dqzdy5FTN/SGYZhAEr7MguG3Z314hMS2scgMsOMgB64uj/6+6UwIDAQAB
```

The last line on stdout is the extracted public key, ready to save to a file or verify against a signature. The stderr block above shows the raw DNS response (including the CNAME target on line 1) and the `dig` command for transparency.

## Common examples

**Capture just the key** (silence stderr):

```
$ dkim-pubkey s1 github.com 2>/dev/null
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyn3fMCVpb7ryIRKOGXhXVGYmsWUitNlSckqGHOwNFZgFadplOrD+Qzf1XQkP7MH/VB/97DsAAJGtEXW1Uq71Hjnfr/DuBN/YfjF/gU70qEFb7q1sdIiNtjFL2TkOpoW+X/bhhPNheW/fYwyFb6ZHFM6LTgXyuimWRHTOUP3VjZzhNVda79nt+2WZYbS4l8HdMgWpTNHjpVw5PtXESA9KBg/evSRk5fIaXIX5eRXW3baoV9yVzD8O29/IL/DiSk+yNvaO0EHL5c4yGuZJhGzvpiznb2IDVdemJK4Dqzdy5FTN/SGYZhAEr7MguG3Z314hMS2scgMsOMgB64uj/6+6UwIDAQAB
```

**Save the key to a file:**

```bash
dkim-pubkey selector1 example.com 2>/dev/null > dkim-key.txt
```

**Check multiple selectors** for the same domain to see which one is active:

```bash
for sel in default selector1 s1 google; do
  echo "Checking $sel:"
  dkim-pubkey "$sel" example.com
  echo
done
```

**Verify a DKIM key matches what you expect** (compare against a known good key):

```bash
current_key=$(dkim-pubkey s1 yourdomain.com 2>/dev/null)
if [ "$current_key" = "$EXPECTED_KEY" ]; then
  echo "Key matches"
else
  echo "Key mismatch!"
fi
```

## How it works

The script:

1. Queries `<selector>._domainkey.<domain>` using `dig +short TXT`
2. Echoes the `dig` command and raw response to stderr
3. Parses the response to extract the `p=` value (strips quotes, joins multi-line records)
4. Prints the base64-encoded public key to stdout

DKIM TXT records follow the format `"k=rsa; p=<base64-key>"` (sometimes with additional tags like `t=s`, `h=sha256`). The `p=` value is the RSA public key in base64 format. DNS responses may split long TXT records across multiple quoted strings; the script joins these automatically.

## Common scenarios

**Selector not found:**

```
$ dkim-pubkey nonexistent example.com
$ dig +short TXT "nonexistent._domainkey.example.com"
[ERR][dkim-pubkey] DNS response empty
```

This means either the selector doesn't exist, or the domain doesn't have DKIM configured. Check your email provider's documentation for the correct selector name -- common ones are `default`, `selector1`, `selector2`, `google`, `k1`, `s1`.

**CNAME redirects:**

Some DKIM records use CNAMEs that point to a third-party email provider's infrastructure (e.g., Sendgrid, Mailgun). When `dig +short TXT` follows the CNAME and returns both the CNAME target and the resolved TXT record on separate lines, the script picks the line containing `p=` and discards the rest -- stdout always contains exactly one line (the key) on success. The CNAME target is still visible in the stderr block for context.

If the CNAME target itself does not resolve to a TXT record, `dig` returns nothing for `p=` and the script exits 4.

**Validating the extracted key:**

Pass `--validate` (or `-V`) to verify the key is well-formed. The check has two stages: a strict base64 shape check (alphabet, padding, no whitespace), then a structural decode via `openssl pkey -pubin -inform DER` to confirm the bytes parse as a public key. On success, an `[INF]` line summarizing the key (algorithm and size) is printed to stderr; the key still goes to stdout. On failure, the key is still printed (so you can see what was found) and the script exits 5.

```
$ dkim-pubkey --validate s1 github.com
$ dig +short TXT "s1._domainkey.github.com"
s1.domainkey.u51742174.wl175.sendgrid.net.
"k=rsa; t=s; p=MIIBIjANBgkqhkiG9w0BAQ..."

[INF][dkim-pubkey] Key valid (Public-Key: (2048 bit))
MIIBIjANBgkqhkiG9w0BAQ...
```

DKIM records sometimes get corrupted in transit -- a stray space, a truncated line, or a copy/paste error in the DNS provider's editor. The base64 stage catches encoding-level damage; the openssl stage catches structurally invalid keys (right alphabet, wrong bytes). `openssl` is required only when `--validate` is used.

**Querying a specific DNS server:**

By default the script uses the system resolver. Pass `-s <host>`, `--server <host>`, or the dig-style `@host` shorthand to override -- handy when you want to compare what different resolvers see for a record (caching divergence, propagation delays, regional differences):

```bash
dkim-pubkey s1 github.com @8.8.8.8           # Google DNS
dkim-pubkey --server 1.1.1.1 s1 github.com   # Cloudflare DNS
dkim-pubkey s1 github.com @9.9.9.9           # Quad9
```

`--server` and `@host` are interchangeable but not combinable -- specifying both (or `--server` twice) is a usage error.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `selector` | DKIM selector (first positional argument, required) |
| `domain` | Domain name (second positional argument, required) |
| `-s, --server <host>` | Query `<host>` instead of the system resolver (also `@host`) |
| `-V, --validate` | Verify the extracted key is a well-formed public key |
| `-h, --help` | Display help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (key extracted and printed) |
| 1 | Runtime failure (DNS response empty) |
| 2 | Usage error (missing selector or domain) |
| 3 | Dependency error (`dig` missing, or `openssl` missing with `--validate`) |
| 4 | Domain-specific: record found but `p=` value missing (malformed record) |
| 5 | Validation failed (with `--validate`) |

### Dependencies

- `dig` (part of BIND tools, typically pre-installed on most systems)
- `openssl` (required only for `--validate`)
