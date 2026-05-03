# cf-ddns

Update a Cloudflare DNS A record to match this machine's current outbound IP address -- a lightweight dynamic DNS solution for home servers, dev machines, or any host behind a changing IP.

Designed to run periodically from the target host (via cron or systemd timer). Fetches the machine's public IP from ipify.org, compares it to the domain's current DNS resolution via Google DNS, and updates Cloudflare only when they differ.

## Quick start

```bash
$ cf-ddns YOUR_API_TOKEN home.example.com
[INF][cf-ddns] Device's IP: 203.0.113.42
[INF][cf-ddns] Domain's IP: 198.51.100.8 (home.example.com)
[INF][cf-ddns] IP addresses do not match, updating DNS
[INF][cf-ddns] Deleting A record for 198.51.100.8 (abc123...)
[INF][cf-ddns] Creating A record for 203.0.113.42
```

The script deletes all existing A records for the domain before creating a new one pointing to the current IP. TTL is hardcoded to 60 seconds for fast propagation.

**Create a Cloudflare API token:**

1. Go to the [Cloudflare dashboard](https://dash.cloudflare.com/profile/api-tokens) > API Tokens
2. Create token with permissions: **Zone.Zone** (read) and **Zone.DNS** (edit)
3. Scope to the specific zone if desired

## Common examples

**Run from cron every 5 minutes:**

```bash
# crontab entry
*/5 * * * * /path/to/cf-ddns YOUR_API_TOKEN home.example.com 2>&1 | logger -t cf-ddns
```

**Enable debug output** to see full curl logs and API call details:

```bash
$ DDNS_DEBUG=1 cf-ddns YOUR_API_TOKEN home.example.com
[DBG][cf-ddns] curl output logged to: /tmp/curl.12345.log
[DBG][cf-ddns] GET /zones
[INF][cf-ddns] Device's IP: 203.0.113.42
...
```

**Pipe from the web** (since this is published at toolio.sh):

```bash
curl -s toolio.sh/cf-ddns | bash -s -- YOUR_API_TOKEN home.example.com
```

## How it works

1. Fetch the machine's outbound IP via `curl https://api.ipify.org`
2. Query the domain's current A record via `dig @8.8.8.8 +tcp +short $domain` (Google DNS, TCP mode to avoid UDP blocks)
3. Compare IPs -- if they match, exit early with success
4. If they differ:
   - Call Cloudflare API to find the zone ID for the domain
   - List all A records in that zone
   - **Delete every A record** (this is why the script uses DELETE + POST instead of PUT)
   - Create a new A record with the current IP and 60-second TTL

The delete-all-then-create approach ensures a clean state even if multiple A records exist (leftover from manual edits, migrations, etc.).

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Show help message with synopsis, description, dependencies, and API token requirements |

### Arguments

| Argument | Description |
|---|---|
| `api_token` | Cloudflare API token (required permissions: Zone.Zone, Zone.DNS) |
| `domain` | Fully qualified domain name to update (e.g. `home.example.com`) |

### Environment variables

| Variable | Description |
|---|---|
| `DDNS_DEBUG` | Set to any value to enable verbose curl and debug output. Logs API calls and curl traces to stderr. |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (IP already matched or DNS updated successfully) |
| 1 | Runtime failure (IP fetch failed, zone not found, API error) |
| 2 | Usage error (missing API token or domain) |
| 3 | Dependency error (`curl`, `jq`, or `dig` missing) |

### Dependencies

- `curl` -- API calls to Cloudflare and ipify.org
- `jq` -- JSON parsing for API responses
- `dig` -- DNS lookup via Google DNS (uses TCP mode with `+tcp` flag)

### Warnings

- **Deletes all A records** for the domain before creating the new one. If you have multiple A records for load balancing or failover, this script will remove them.
- **No retry logic** -- if the API call fails, the script exits with an error. Suitable for cron where the next run will retry.
- **Assumes IPv4** -- only updates A records, not AAAA (IPv6). The ipify.org endpoint returns IPv4 by default.
- **Requires Zone.Zone and Zone.DNS permissions** -- the token must be scoped to at least read zones and edit DNS records.

### Behavior

- **TTL:** Hardcoded to 60 seconds (`A_RECORD_TTL=60`) for fast propagation during IP changes.
- **API version:** Uses Cloudflare API v4 (`https://api.cloudflare.com/client/v4`).
- **Logging:** Colored output via raw ANSI escapes, guarded by TTY check and `NO_COLOR`. All diagnostic levels (`[INF]`, `[WRN]`, `[ERR]`, `[DBG]`) write to stderr in the shape `[LVL][cf-ddns] message`.
- **Curl logs:** When `DDNS_DEBUG` is set, full curl stderr/stdout is logged to `/tmp/curl.$$.log` (where `$$` is the process ID).
- **TCP DNS queries:** Uses `dig +tcp` to avoid issues on networks that block UDP DNS traffic.
