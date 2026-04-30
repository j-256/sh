# dkim-pubkey

Extract the base64-encoded public key from a DKIM DNS record.

DKIM records are published as TXT records at `<selector>._domainkey.<domain>`. This script queries that record, parses the response, and extracts just the public key value (the `p=` field) -- useful when you need to verify DKIM signatures, audit email authentication setup, or compare keys across selectors.

The raw DNS response goes to stderr so you can see what came back; the extracted key goes to stdout so you can pipe it to other tools.

## Quick start

```
$ dkim-pubkey s1 github.com
$ dig +short TXT "s1._domainkey.github.com"
s1.domainkey.u51742174.wl175.sendgrid.net.
"k=rsa; t=s; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyn3fMCVpb7ryIRKOGXhXVGYmsWUitNlSckqGHOwNFZgFadplOrD+Qzf1XQkP7MH/VB/97DsAAJGtEXW1Uq71Hjnfr/DuBN/YfjF/gU70qEFb7q1sdIiNtjFL2TkOpoW+X/bhhPNheW/fYwyFb6ZHFM6LTgXyuimWRHTOUP3VjZzhNVda79nt+2WZYbS4l8HdMgWpT" "NHjpVw5PtXESA9KBg/evSRk5fIaXIX5eRXW3baoV9yVzD8O29/IL/DiSk+yNvaO0EHL5c4yGuZJhGzvpiznb2IDVdemJK4Dqzdy5FTN/SGYZhAEr7MguG3Z314hMS2scgMsOMgB64uj/6+6UwIDAQAB"

s1.domainkey.u51742174.wl175.sendgrid.net.
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyn3fMCVpb7ryIRKOGXhXVGYmsWUitNlSckqGHOwNFZgFadplOrD+Qzf1XQkP7MH/VB/97DsAAJGtEXW1Uq71Hjnfr/DuBN/YfjF/gU70qEFb7q1sdIiNtjFL2TkOpoW+X/bhhPNheW/fYwyFb6ZHFM6LTgXyuimWRHTOUP3VjZzhNVda79nt+2WZYbS4l8HdMgWpTNHjpVw5PtXESA9KBg/evSRk5fIaXIX5eRXW3baoV9yVzD8O29/IL/DiSk+yNvaO0EHL5c4yGuZJhGzvpiznb2IDVdemJK4Dqzdy5FTN/SGYZhAEr7MguG3Z314hMS2scgMsOMgB64uj/6+6UwIDAQAB
```

The last line is the extracted public key, ready to save to a file or verify against a signature.

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
ERROR: DNS response empty
```

This means either the selector doesn't exist, or the domain doesn't have DKIM configured. Check your email provider's documentation for the correct selector name -- common ones are `default`, `selector1`, `selector2`, `google`, `k1`, `s1`.

**CNAME redirects:**

Some DKIM records use CNAMEs that point to a third-party email provider's infrastructure (e.g., Sendgrid, Mailgun). The script will show the CNAME target in the stderr output, but you may not see a `p=` value directly. If you see a CNAME, you can manually query the target or use your email provider's tools to verify the setup.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `selector` | DKIM selector (first positional argument, required) |
| `domain` | Domain name (second positional argument, required) |
| `-h, --help` | Display help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (key extracted and printed) |
| 1 | DNS query returned empty response, or required arguments missing |

### Dependencies

- `dig` (part of BIND tools, typically pre-installed on most systems)
