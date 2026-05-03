# spf-find-ip

[View script](../spf-find-ip)

Recursively search SPF records to find whether a specific IP address is authorized to send email for a domain. When you get an SPF soft-fail or are debugging email deliverability, this tells you whether the sending IP is actually covered by the domain's SPF chain.

SPF records authorize sending IPs via `include:` directives that chain to other domains' records. A single lookup rarely shows the full picture -- you might see `include:_spf.google.com`, which itself includes more domains. This script walks the entire tree and highlights where the IP appears.

## Quick start

```
$ spf-find-ip mailchimp.com 139.138.35.44
SPF record for mailchimp.com:
v=spf1 ip4:205.201.128.0/20 ip4:198.2.128.0/18 include:_spf.google.com include:_spf2.intuit.com ~all

SPF record for _spf.google.com:
v=spf1 ip4:74.125.0.0/16 ip4:209.85.128.0/17 ~all

SPF record for _spf2.intuit.com:
v=spf1 include:stspg-customer.com ip4:139.138.35.44 ip4:139.138.46.121 ~all

IP 139.138.35.44 is included by: _spf2.intuit.com
v=spf1 include:stspg-customer.com ip4:139.138.35.44 ip4:139.138.46.121 ~all
```

The script queries Google DNS (8.8.8.8) for each SPF record, follows all `include:` directives recursively, and stops when it finds the IP. The matching IP is highlighted in red in the final output.

## Common examples

**Check if your mail server IP is authorized:**

```
$ spf-find-ip example.com 198.51.100.42
SPF record for example.com:
v=spf1 include:_spf.mailprovider.com ~all

SPF record for _spf.mailprovider.com:
v=spf1 ip4:198.51.100.42 ip4:203.0.113.10 ~all

IP 198.51.100.42 is included by: _spf.mailprovider.com
v=spf1 ip4:198.51.100.42 ip4:203.0.113.10 ~all
```

**Debug why an IP isn't found:**

```
$ spf-find-ip example.com 192.0.2.50
SPF record for example.com:
v=spf1 include:_spf.mailprovider.com ~all

SPF record for _spf.mailprovider.com:
v=spf1 ip4:198.51.100.0/24 ~all

IP 192.0.2.50 not found in example.com's SPF records
```

The script outputs every SPF record it fetches, so you can see exactly which domains were checked and what ranges they authorize.

## How SPF includes work

An SPF record is a TXT DNS record that lists authorized sending IPs. The `include:` directive delegates part of that authorization to another domain's SPF record. For example:

```
v=spf1 include:_spf.google.com ~all
```

This says "IPs authorized by `_spf.google.com` are also authorized here." Mail servers recursively follow these includes when checking SPF, and this script does the same.

## Limitations

**IP ranges are not supported.** The script only matches exact IPs or IPs followed by `/32`. If your IP is `198.51.100.42` and the SPF record says `ip4:198.51.100.0/24`, the script will report "not found" even though the IP is actually covered by that range.

**Redirect directives are not followed.** If a domain uses `redirect=_spf.example.com` instead of `include:`, the script will not follow it. This is less common but used by some large providers (e.g., Gmail uses `redirect=_spf.google.com`).

**The 10-lookup limit is not enforced.** RFC 7208 limits SPF evaluation to 10 DNS lookups to prevent abuse. This script will keep going past 10 and may query more domains than a real mail server would.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Any lookup result (found, not found, or no SPF record -- distinguish via stdout) |
| `2` | Usage error (missing domain or ip) |
| `3` | Dependency error (`dig` missing) |

### Dependencies

- `dig` (DNS lookup tool, part of BIND utilities)

Script uses Google DNS (8.8.8.8) for all lookups to ensure consistent results regardless of local resolver configuration.
