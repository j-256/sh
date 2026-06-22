# spf

[View script](../spf)

Recursively resolve and inspect SPF DNS records. `spf` walks the full `include:` tree for a domain and answers the common inspection questions: is this IP authorized (`find`), what are all the authorized addresses (`flatten`), is the record healthy (`check`), what does the full delegation tree look like (`tree`), is a specific mechanism token present anywhere in the tree (`has`), and what does the raw resolver output look like for piping into other tools (`ir`).

SPF authorization is often buried three or four levels of `include:` directives deep. A single TXT lookup rarely gives you the full picture -- `spf` follows every include recursively, counts DNS lookups against the RFC 7208 limit, and surfaces problems that would cause silent delivery failures in production.

## Quick start

Check whether a specific IP is authorized to send email for a domain:

```
$ spf find mailchimp.com 205.201.128.1
[INF][spf] mailchimp.com: v=spf1 ip4:205.201.128.0/20 ...
[INF][spf] _spf.google.com: v=spf1 ip4:74.125.0.0/16 ...
...
205.201.128.1 is covered by ip4:205.201.128.0/20 in mailchimp.com (qualifier: +)
```

Exit 0 means the IP is authorized; exit 4 means it was not found.

## Common examples

**Check if a sending IP is authorized (`find`):**

```
$ spf find github.com 192.30.252.1
[INF][spf] github.com: v=spf1 ip4:192.30.252.0/22 include:spf.protection.outlook.com ...
[INF][spf] spf.protection.outlook.com: v=spf1 ip4:40.92.0.0/15 ...
...
192.30.252.1 is covered by ip4:192.30.252.0/22 in github.com (qualifier: +)
```

`[INF]` lines (informational, to stderr) show each SPF record as it is fetched so you can trace the path. The last stdout line is the verdict.

**Check whether a host is explicitly listed as an `a:` sender (`find a:<host>`):**

A common CI check: is your mail host still authorized by name (self-healing on renumber), or has it been flattened into an anonymous CIDR (fragile)?

```
$ spf find mailsenders.netsuite.com a:outboundips.netsuite.com
[INF][spf] mailsenders.netsuite.com: v=spf1 a:outboundips.netsuite.com -all
outboundips.netsuite.com matches a:outboundips.netsuite.com in mailsenders.netsuite.com (qualifier: +)
```

Exit 0 -- the host is present literally. If the host renumbers, the `a:` directive picks up the new address automatically.

Now imagine a record that was flattened and the host's IP landed in a static range instead:

```
$ spf find 'v=spf1 ip4:142.250.100.0/24 -all' a:smtp.gmail.com
[INF][spf] <record>: v=spf1 ip4:142.250.100.0/24 -all
a:smtp.gmail.com is NOT present literally, but its address 142.250.100.109 is covered by ip4:142.250.100.0/24 in <record> -- fragile: a flattened range does not self-heal if the host renumbers
```

Exit 5 -- the host resolves to an IP inside a CIDR, but the `a:` directive itself is missing. Email will flow today but break silently if the host renumbers.

```
$ spf find mailsenders.netsuite.com a:mail.example.com
[INF][spf] mailsenders.netsuite.com: v=spf1 a:outboundips.netsuite.com -all
a:mail.example.com not found in mailsenders.netsuite.com's SPF record
```

Exit 4 -- the directive is absent entirely.

In a CI script, branch on `$?`:

```bash
spf find "$domain" "a:$host" -q
case $? in
  0) echo "OK: a:$host present literally" ;;
  5) echo "WARN: a:$host covered by a CIDR range -- fragile" ;;
  4) echo "FAIL: a:$host not found" ;;
esac
```

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

## Escape hatch: raw resolver IR (`ir`)

Every `spf` subcommand is built on a single resolver engine that emits a frozen six-column tab-delimited IR. The `ir` verb exposes that stream directly so you can pipe it into `awk`, `grep`, or any other tool without going through a higher-level command.

```
$ spf ir google.com -q
0	google.com	+	include	_spf.google.com	1
1	_spf.google.com	+	ip4	74.125.0.0/16	0
1	_spf.google.com	+	ip4	209.85.128.0/17	0
1	_spf.google.com	+	ip6	2001:4860:4864::/56	0
1	_spf.google.com	+	ip6	2404:6800:4864::/56	0
1	_spf.google.com	+	ip6	2607:f8b0:4864::/56	0
1	_spf.google.com	+	ip6	2800:3f0:4864::/56	0
1	_spf.google.com	+	ip6	2a00:1450:4864::/56	0
1	_spf.google.com	+	ip6	2c0f:fb50:4864::/56	0
1	_spf.google.com	~	all		0
0	google.com	~	all		0
```

### Column layout (stable contract)

The six columns are separated by a single tab (`\t`). This layout is a stable contract -- the column positions will not change.

| Column | Name | Description |
|---|---|---|
| 1 | `depth` | Include nesting depth (0 = root record) |
| 2 | `source_domain` | Domain that owns this mechanism |
| 3 | `qualifier` | SPF qualifier (`+`, `-`, `~`, `?`) |
| 4 | `mechanism` | Mechanism keyword (`ip4`, `ip6`, `include`, `a`, `mx`, `all`, `redirect`, `exists`, `ptr`, `void`) |
| 5 | `value` | Mechanism value (CIDR, target domain, etc.; empty for bare `all` and `ptr`) |
| 6 | `lookup_cost` | DNS lookup cost this row contributes (1 for mechanisms that require a DNS lookup, 0 otherwise) |

Use `-F'\t'` in `awk` to split on tab. For example, to filter only `include` rows:

```bash
spf ir google.com -q | awk -F'\t' '$4=="include"'
```

```
0	google.com	+	include	_spf.google.com	1
```

Exit 0 when the record resolves; exit 1 when no SPF record is found.

## Token search (`has`)

`has` answers one question: is a specific mechanism token present anywhere in the recursively-expanded SPF tree, and if so, where? It is a pure lexical scan -- no host resolution, no IP comparison. The token must match exactly: mechanism type, separator, and value must all be identical.

```
$ spf has google.com include:_spf.google.com -q
PRESENT: include:_spf.google.com
  in google.com (depth 0, qualifier: +)
```

Exit 0. The output names the mechanism and value, then lists every record that contains it with the owning domain, include depth, and qualifier.

When the token is not in the tree at any depth, `has` reports the absence and exits 4:

```
$ spf has google.com include:nonexistent.example -q
ABSENT: include:nonexistent.example not found in google.com's SPF tree
```

Exit 4. No record in the recursively-expanded tree contains the exact token.

### Why `has` instead of `dig txt | grep`

Three things `grep` on a single DNS lookup cannot do:

1. **Recurses the include tree.** `dig TXT example.com` returns one record. An `include:` two levels deep is invisible to `grep`; `has` follows every delegation.

2. **Exact token match, not substring match.** `grep include:site.com` matches `include:site.com.attacker.example` -- a false positive that conceals a domain-takeover risk. `has include:site.com` requires the value to be exactly `site.com` with nothing following.

3. **Reports the qualifier.** A mechanism can appear with a `-` (fail) qualifier. `has` shows `qualifier: -` in the provenance line, so you can see at a glance whether the match authorizes or rejects.

### `has` vs `find` for `a:` directives

For IP-authorization questions involving a hostname, prefer `find a:<host>`. It resolves the host, checks the full CIDR coverage, and returns three states: present literally (exit 0), covered by a CIDR range but not named explicitly (exit 5, fragile), or absent (exit 4). `has a:<host>` only answers whether the literal `a:<host>` token appears in the tree -- it will not catch a flattened range that happens to cover the host's current address.

## Cross-resolver comparison

Use `-s` to query a specific DNS server. Running `flatten` against two resolvers and diffing the output reveals split-horizon or geo-aware SPF -- common with providers that serve different IP ranges to different resolvers:

```bash
spf flatten google.com -s 8.8.8.8  > /tmp/spf-google.txt
spf flatten google.com -s 1.1.1.1  > /tmp/spf-cf.txt
diff /tmp/spf-google.txt /tmp/spf-cf.txt
```

An empty diff is the normal, healthy result -- both resolvers see the same IP ranges. A non-empty diff flags resolver-dependent SPF: one or more included domains returns different IP ranges depending on the resolver used. A mail server querying through a different resolver than your test machine may authorize a different set of IPs -- this is the root cause of "works for me but fails for some recipients" SPF failures.

## Salesforce `exists:` macros

Salesforce uses `exists:%{i}._spf.mta.salesforce.com` instead of a static CIDR list. The mechanism is evaluated by doing an A lookup against a domain that encodes the query IP -- only registered Salesforce MTA IPs resolve.

`find` evaluates the macro: it expands `%{i}` to the query IP, performs the A lookup, and reports a match if the lookup resolves. The following uses a raw record with `exists:%{d}` anchored to `google.com` (so the A lookup hits `google.com`, which resolves -- a reliable demonstration of a positive match):

```
$ spf find 'v=spf1 exists:%{d} -all' 1.2.3.4 -d google.com -q
1.2.3.4 matches exists:%{d} in google.com (qualifier: +)
```

Note the qualifier is `+`: an `exists:` mechanism without an explicit qualifier sign defaults to pass, regardless of what the trailing `all` mechanism says.

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
| `-d, --domain dom` | Anchor `%{d}` macros when input is a raw record |
| `--tcp` | Force TCP instead of UDP for dig queries |
| `-q, --quiet` | Suppress informational output |
| `-h, --help` | Show the top-level help; `spf <verb> -h` (or `spf -h <verb>`) shows per-verb detail |
| `--record` | (flatten only) Emit the result as a quoted TXT record string instead of one CIDR per line |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success: IP covered (`find`), output emitted (`flatten`), record clean (`check`), tree rendered (`tree`), token found (`has`) |
| `1` | Runtime failure: no SPF record found, DNS error, or unexpected dig output |
| `2` | Usage error: missing argument, unknown flag, or bad flag value |
| `3` | `dig` is not installed |
| `4` | Negative predicate result: IP not found (`find`), problems detected (`check`), or token absent (`has`) |
| `5` | `find a:<host>`: host is absent as a literal directive but its resolved address is covered by a CIDR range (fragile) |

Exit code `5` applies to `find` only. Exit code `4` means: IP not found (`find`), problems detected (`check`), or token absent (`has`). `flatten` and `tree` always exit `0` on success.

### Dependencies

- `dig` (required; part of BIND utilities, pre-installed on most systems)
- `python3` (required only for IPv6 CIDR matching; if absent, IPv6 comparisons fall back to literal match with a warning)

### Limitations

- `ptr` mechanisms and sender/HELO macros (`%{s}`, `%{l}`, `%{o}`, `%{h}`, `%{p}`) are not evaluated. They count toward the DNS lookup limit but are not matched and are noted on stderr.
- IPv6 CIDR matching requires `python3`. Without it, an IPv6 mechanism only matches if the query IP is byte-for-byte identical to the mechanism value (no prefix expansion).
