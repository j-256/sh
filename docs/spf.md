# spf

[View script](../spf)

Recursively resolve and inspect SPF DNS records. `spf` walks the full `include:` tree for a domain and answers four questions: is this IP authorized (`find`), what are all the authorized addresses (`flatten`), is the record healthy (`check`), and what does the full delegation tree look like (`tree`).

SPF authorization is often buried three or four levels of `include:` directives deep. A single TXT lookup rarely gives you the full picture -- `spf` follows every include recursively, counts DNS lookups against the RFC 7208 limit, and surfaces problems that would cause silent delivery failures in production.

## Quick start

Check whether a specific IP is authorized to send email for a domain:

```
$ spf find mailchimp.com 205.201.128.1
[INF][spf] mailchimp.com: v=spf1 ip4:205.201.128.0/20 ...
[INF][spf] _spf.google.com: v=spf1 ip4:74.125.0.0/16 ...
...
205.201.128.1 is listed/covered by mailchimp.com (qualifier: +)
  matched: ip4:205.201.128.0/20
```

Exit 0 means the IP is authorized; exit 4 means it was not found.

## Common examples

**Check if a sending IP is authorized (`find`):**

```
$ spf find github.com 192.30.252.1
[INF][spf] github.com: v=spf1 ip4:192.30.252.0/22 include:spf.protection.outlook.com ...
[INF][spf] spf.protection.outlook.com: v=spf1 ip4:40.92.0.0/15 ...
...
192.30.252.1 is listed/covered by github.com (qualifier: +)
  matched: ip4:192.30.252.0/22
```

`[INF]` lines (informational, to stderr) show each SPF record as it is fetched so you can trace the path. The last two stdout lines are the verdict.

**Dump all authorized IP ranges (`flatten`):**

```
$ spf flatten github.com
[INF][spf] github.com: v=spf1 ip4:192.30.252.0/22 include:spf.protection.outlook.com ...
[INF][spf] spf.protection.outlook.com: v=spf1 ip4:40.92.0.0/15 ...
...
[WRN][spf] cannot statically evaluate exists (1 occurrence(s))
37.188.97.188/32
40.92.0.0/15
40.107.0.0/16
50.31.32.0/19
...
```

One CIDR per line on stdout. `exists:` mechanisms that reference a query-IP macro (`%{i}`) cannot be statically resolved and are reported as a warning on stderr.

**Run an SPF health check (`check`):**

```
$ spf check github.com
[INF][spf] github.com: v=spf1 ip4:192.30.252.0/22 ...
...
DNS lookups: 10/10
Void lookups: 0/2
Published SPF records: 1
OK: no problems found
```

`check` counts DNS lookups, void lookups, and flags problems like `+all`, multiple `all` mechanisms in the checked record, or `ptr` usage. Exit 0 when clean; exit 4 when problems are found.

**Print the full delegation tree (`tree`):**

```
$ spf tree 'v=spf1 ip4:1.2.3.0/24 include:_spf.google.com ~all'
[INF][spf] <record>: v=spf1 ip4:1.2.3.0/24 include:_spf.google.com ~all
[INF][spf] _spf.google.com: v=spf1 ip4:74.125.0.0/16 ip4:209.85.128.0/17 ...
  ip4:1.2.3.0/24
  include:_spf.google.com
      ip4:74.125.0.0/16
      ip4:209.85.128.0/17
      ip6:2001:4860:4864::/56
      ip6:2404:6800:4864::/56
      ip6:2607:f8b0:4864::/56
      ip6:2800:3f0:4864::/56
      ip6:2a00:1450:4864::/56
      ip6:2c0f:fb50:4864::/56
      ~all
  ~all
```

Mechanisms are indented by depth (2 spaces at the root, +4 per include level). `include:` lines mark delegation boundaries; the child mechanisms are indented beneath them.

## Cross-resolver comparison

Use `-s` to query a specific DNS server. Running `flatten` against two resolvers and diffing the output reveals split-horizon or geo-aware SPF -- common with providers that serve different IP ranges to different resolvers:

```bash
spf flatten example.com -s 8.8.8.8  > /tmp/spf-google.txt
spf flatten example.com -s 1.1.1.1  > /tmp/spf-cf.txt
diff /tmp/spf-google.txt /tmp/spf-cf.txt
```

If the diff is non-empty, one or more included domains returns different IP ranges depending on resolver. A mail server using a different resolver than your test machine may authorize a different set of IPs -- this is the root cause of "works for me but fails for some recipients" SPF failures.

## Salesforce `exists:` macros

Salesforce uses `exists:%{i}._spf.mta.salesforce.com` instead of a static CIDR list. The mechanism is evaluated by doing an A lookup against a domain that encodes the query IP -- only registered Salesforce MTA IPs resolve.

`find` evaluates the macro: it expands `%{i}` to the query IP, performs the A lookup, and reports a match if the lookup resolves:

```
$ spf find _spf.salesforce.com 198.51.100.7
[INF][spf] _spf.salesforce.com: v=spf1 exists:%{i}._spf.mta.salesforce.com -all
198.51.100.7 is listed/covered by _spf.salesforce.com (qualifier: -)
  matched: exists:%{i}._spf.mta.salesforce.com
```

`flatten` cannot expand `exists:` without a query IP and emits a warning instead:

```
$ spf flatten _spf.salesforce.com
[INF][spf] _spf.salesforce.com: v=spf1 exists:%{i}._spf.mta.salesforce.com -all
[WRN][spf] cannot statically evaluate exists (1 occurrence(s))
```

No IP ranges are printed for the Salesforce mechanism because there are none to enumerate. Sender macros (`%{s}`, `%{l}`, `%{o}`, `%{h}`, `%{p}`) are likewise unevaluable in all modes and are noted but not matched.

## Raw-record input

Pass a literal SPF record string instead of a domain name to vet a record before publishing:

```
$ spf check 'v=spf1 ip4:192.0.2.0/24 ~all'
[INF][spf] <record>: v=spf1 ip4:192.0.2.0/24 ~all
DNS lookups: 0/10
Void lookups: 0/2
Record count: N/A (raw-record input)
OK: no problems found
```

`spf` detects a raw record by the leading `v=spf1 ` prefix. Pipe via `-` for stdin:

```
$ echo 'v=spf1 ip4:10.0.0.0/8 ~all' | spf flatten -
[INF][spf] <record>: v=spf1 ip4:10.0.0.0/8 ~all
10.0.0.0/8
```

If the record contains `%{d}` macros, anchor them with `-d`/`--domain`:

```bash
spf check 'v=spf1 exists:%{i}._spf.mta.example.com -all' -d example.com
```

## Flattening staleness

`flatten` captures the provider's current IP ranges at the moment you run it. If you publish the flattened result as a static TXT record, it will drift as the provider adds or renumbers servers -- your record will silently fail to authorize legitimate senders.

This is the SPF equivalent of hardcoding a CNAME target's IP instead of using the CNAME itself: correct today, broken on the day the provider renumbers. The safe deployment pattern is to `flatten` for auditing, use `check` to confirm the live record stays healthy, and let the provider's `include:` chain do the actual authorization in production. Also note a flattened record must fit within a single TXT resource record (510 bytes of SPF content after the tag).

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-s, --server ip` | DNS server to query (default: 8.8.8.8) |
| `-d, --domain dom` | Restrict output to a specific domain anchor (anchors `%{d}` in raw mode) |
| `--tcp` | Force TCP instead of UDP for dig queries |
| `-q, --quiet` | Suppress informational output |
| `-h, --help` | Show this help message |
| `--record` | (flatten only) Emit the result as a quoted TXT record string instead of one CIDR per line |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success: IP covered (`find`), output emitted (`flatten`), record clean (`check`), tree rendered (`tree`) |
| `1` | Runtime failure: no SPF record found, DNS error, or unexpected dig output |
| `2` | Usage error: missing argument, unknown flag, or bad flag value |
| `3` | `dig` is not installed |
| `4` | Negative predicate result: IP not found (`find`) or problems detected (`check`) |

Exit code `4` applies to `find` and `check` only. `flatten` and `tree` always exit `0` on success.

### Dependencies

- `dig` (required; part of BIND utilities, pre-installed on most systems)
- `python3` (required only for IPv6 CIDR matching; if absent, IPv6 comparisons fall back to literal match with a warning)

### Limitations

- `ptr` mechanisms and sender/HELO macros (`%{s}`, `%{l}`, `%{o}`, `%{h}`, `%{p}`) are not evaluated. They count toward the DNS lookup limit but are not matched and are noted on stderr.
- IPv6 CIDR matching requires `python3`. Without it, an IPv6 mechanism only matches if the query IP is byte-for-byte identical to the mechanism value (no prefix expansion).
