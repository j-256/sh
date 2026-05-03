# s

[View script](../s)

sfcc-ci wrapper with convenient shortcuts, enhanced output formatting, and human-readable token expiration for Salesforce B2C Commerce Cloud development.

If you work with SFCC sandboxes regularly, `s` gives you faster access to the commands you run most often. It wraps the official `sfcc-ci` tool, adds shorthand aliases for common operations (like `s sbx mybox` instead of `sfcc-ci sandbox:list -j | jq ...`), and surfaces key details (like auth token expiration in your local timezone) that would otherwise require piping through multiple tools.

## Quick start

**Authenticate and see when your token expires:**

```bash
$ s auth
successfully authenticated
Expires at 14:30 PDT (2026-04-21 21:30:00 UTC)
```

**Get sandbox details at a glance:**

```bash
$ s sbx dev-web-001
sbx:     realm-dev-web-001
state:   started
id:      abc123-def456-ghi789
app:     23.10
web:     23.10
size:    MEDIUM
host:    dev-web-001.sandbox.us01.dx.commercecloud.salesforce.com
bm:      https://dev-web-001.sandbox.us01.dx.commercecloud.salesforce.com/on/demandware.store/Sites-Site
code:    https://dev-web-001.sandbox.us01.dx.commercecloud.salesforce.com:443/on/demandware.servlet/webdav/Sites/Cartridges/version_123
```

**Start a sandbox and wait for it to finish:**

```bash
$ s start dev-web-001
starting sandbox realm-dev-web-001...done
```

## Common examples

**List all sandboxes (hostname, state, id, creator):**

```bash
$ s list
dev-web-001.sandbox.us01.dx.commercecloud.salesforce.com  started  abc123  user@example.com
stg-web-002.sandbox.us01.dx.commercecloud.salesforce.com  stopped  def456  user@example.com
```

**Restart a sandbox synchronously:**

```bash
$ s restart dev-web-001
stopping sandbox realm-dev-web-001...done
starting sandbox realm-dev-web-001...done
```

**Check when your access token expires:**

```bash
$ s token:exp
2026-04-21 21:30:00 UTC (expires)
2026-04-21 18:15:42 UTC (current)
```

**Decode your JWT payload:**

```bash
$ s token
{
  "sub": "user@example.com",
  "iss": "https://account.demandware.com",
  "exp": 1745269800,
  "iat": 1745266200,
  ...
}
```

**List sandboxes with a TTL set (scheduled for auto-deletion):**

```bash
$ s eol
realm-dev-web-003  2026-04-25T00:00:00Z  started  xyz789  user@example.com
```

**View environment variables relevant to sfcc-ci:**

```bash
$ s env
SFCC_LOGIN_URL='https://account.demandware.com'
SFCC_OAUTH_CLIENT_ID='aaaabbbb-cccc-dddd-eeee-ffff00001111'
SFCC_OAUTH_CLIENT_SECRET='********'
SFCC_SANDBOX_API_HOST=''
DEBUG=''
...
```

## Instance name convenience

All sandbox commands accept underscores or hyphens in instance names:

```bash
s sbx dev_web_001    # works
s sbx dev-web-001    # also works
```

## Falling through to sfcc-ci

Any command that `s` doesn't recognize is passed directly to `sfcc-ci`:

```bash
s code:list
s sandbox:create --help
s client:auth --renew
```

Use `sbx:` as shorthand for `sandbox:`:

```bash
s sbx:list          # same as sandbox:list
s sbx:create        # same as sandbox:create
```

---

## Reference

### All options

`s` is command-driven, not flag-driven. Commands are passed as the first argument.

| Command | Description |
|---|---|
| `a`, `auth` | Authenticate with client credentials (uses `dw.json` or env vars); prints token expiration in local timezone |
| `sbx`, `sandbox`, `box` | Get human-readable details for a single sandbox (hostname, state, id, versions, size, BM/code URLs) |
| `sbx:json`, `sandbox:json`, `box:json` | Get raw JSON object for a single sandbox |
| `list`, `sandboxes`, `boxes`, `sbx:list`, `sandbox:list`, `box:list` | List all sandboxes (hostname, state, id, creator) |
| `list:json`, `sandboxes:json`, `boxes:json`, `sbx:list:json`, `sandbox:list:json`, `box:list:json` | List all sandboxes as JSON |
| `eol` | List sandboxes with a TTL set (scheduled for auto-deletion) |
| `token`, `jwt` | Decode and print JWT payload (base64-decoded body of access token) |
| `token:exp`, `token:expiry`, `token:expiration`, `jwt:exp`, `jwt:expiry`, `jwt:expiration` | Show token expiration time and current time (both UTC) |
| `start <instance>` | Start a sandbox synchronously (waits for completion) |
| `stop <instance>` | Stop a sandbox synchronously (waits for completion) |
| `restart`, `reboot` | Restart a sandbox (stop, then start, both synchronous) |
| `env`, `environment` | Print all SFCC environment variables and their current values |
| _(anything else)_ | Pass through to `sfcc-ci` (e.g. `s code:deploy archive.zip` → `sfcc-ci code:deploy archive.zip`) |

### Environment variables

`s` relies on the same environment variables as `sfcc-ci`. These are recognized by both tools:

| Variable | Description |
|---|---|
| `SFCC_LOGIN_URL` | Login URL for authentication (default: https://account.demandware.com) |
| `SFCC_OAUTH_LOCAL_PORT` | Local port for OAuth authentication flow |
| `SFCC_OAUTH_CLIENT_ID` | Client ID for authentication |
| `SFCC_OAUTH_CLIENT_SECRET` | Client secret for authentication |
| `SFCC_OAUTH_USER_NAME` | Username for authentication |
| `SFCC_OAUTH_USER_PASSWORD` | User password for authentication |
| `SFCC_SANDBOX_API_HOST` | Alternative sandbox API host |
| `SFCC_SANDBOX_API_POLLING_TIMEOUT` | Timeout for sandbox polling in minutes |
| `SFCC_SCAPI_SHORTCODE` | Salesforce Commerce (Headless) API shortcode |
| `SFCC_SCAPI_TENANTID` | Salesforce Commerce (Headless) API tenant ID |
| `DEBUG` | Enable verbose output |

See `sfcc-ci --help` for full details.

### Exit codes

Pass-through from `sfcc-ci` (or `jq`, for subcommands that parse JSON). `start`/`stop`/`restart` invoke sfcc-ci with `FORCE_COLOR=0` so chalk skips terminal coloring entirely, which removes the need for a `| cat` pipeline to reset color.

### Dependencies

- `sfcc-ci` (required) - Install with `npm install -g sfcc-ci`
- `jq` (required for most commands) - JSON processing
- `column` (standard utility on BSD/macOS; on Linux install via `util-linux`)
