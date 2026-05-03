# cf-ips-subnets

[View script](../cf-ips-subnets)

Expand Cloudflare IPv4 ranges into /16 and /24 subnets. Fetches Cloudflare's published CIDR ranges and breaks them down into the largest compatible subnet size (either /16 or /24) that fits within the original range -- perfect for when your firewall or load balancer only accepts these standard prefix sizes.

Some network infrastructure (especially legacy systems) only allows you to specify /16 or /24 CIDR blocks for allowlisting. Cloudflare publishes their IP ranges in various sizes -- /20, /22, etc. -- which these systems reject. This tool bridges the gap by expanding each published range into a list of /16 or /24 subnets you can paste directly into your configuration.

## Quick start

```bash
$ cf-ips-subnets
173.245.48.0/24
173.245.49.0/24
173.245.50.0/24
173.245.51.0/24
173.245.52.0/24
173.245.53.0/24
173.245.54.0/24
173.245.55.0/24
173.245.56.0/24
173.245.57.0/24
173.245.58.0/24
173.245.59.0/24
173.245.60.0/24
173.245.61.0/24
173.245.62.0/24
173.245.63.0/24
103.21.244.0/24
103.21.245.0/24
103.21.246.0/24
103.21.247.0/24
...
```

## Common examples

**Pipe to a file for import into your firewall:**

```bash
$ cf-ips-subnets > cloudflare-subnets.txt
```

**Count how many /24 blocks you'll need:**

```bash
$ cf-ips-subnets | wc -l
     450
```

**Allowlist in iptables:**

```bash
$ cf-ips-subnets | while read subnet; do
  iptables -A INPUT -s "$subnet" -p tcp --dport 443 -j ACCEPT
done
```

## How it works

The script fetches Cloudflare's official IPv4 list from `https://www.cloudflare.com/ips-v4`, which returns ranges like `173.245.48.0/20` or `103.21.244.0/22`. For each range:

- If the prefix is larger than /16 (fewer addresses), it expands to /16 blocks
- If the prefix is /17 to /24, it expands to /24 blocks
- If the prefix is already /24, it's returned as-is (one subnet)
- Ranges larger than /24 (e.g., /25 to /32) are rejected with an error, since they can't be represented as /16 or /24 subnets

This logic ensures you get the fewest number of subnet entries while staying within /16 or /24 boundaries.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Display help |

### Dependencies

| Tool | Purpose | Notes |
|---|---|---|
| `curl` | Fetch Cloudflare IP list | System default is fine |
| `ipcalc` | Subnet calculation | Requires [github.com/kjokjo/ipcalc](https://github.com/kjokjo/ipcalc) |

The script checks for `ipcalc` at startup and exits with an error if it's not available.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime failure (empty fetch response, or CIDR range > /24 encountered) |
| 3 | Dependency error (`curl` or `ipcalc` not found) |

### Behavior

- The script always fetches the latest IP list from Cloudflare on each run -- no caching
- Output is printed to stdout, one subnet per line, in the order Cloudflare publishes them
- The first line of `ipcalc` output (the original CIDR range) is stripped out via `sed 's/Network: *// ; s/ *$// ; 1d'`
- IPv6 ranges are not handled (Cloudflare publishes them separately at `/ips-v6`)
