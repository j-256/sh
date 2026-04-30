# client-credentials

Fetch an OAuth2 access token using the `client_credentials` grant. Built for Salesforce Commerce Cloud endpoints (Account Manager and SLAS), but the pattern is standard OAuth2 -- point it at any token URL that speaks `client_credentials`.

The token prints to stdout and is also exported into environment variables (`J_ACCESS_TOKEN`, `J_ACCESS_TOKEN_EXPIRES_AT`, and refresh tokens for SLAS), so you can source the script and use the values in subsequent commands without parsing stdout yourself.

## Quick start

**Get an Account Manager (AM) token:**

```
$ client-credentials -c aaaaaa-bbbb-cccc-dddd-eeeeeeee -s your_client_secret
eyJraW...truncated
```

**Get a SLAS token** (includes refresh token):

```
$ client-credentials -e slas -c aaaaaa-bbbb-cccc-dddd-eeeeeeee -s your_client_secret -C zzxy -o f_ecom_zzzz_prd
eyJraW...truncated
```

**Source the script to populate environment variables:**

```bash
. client-credentials -c aaaaaa-bbbb-cccc-dddd-eeeeeeee -s your_client_secret
curl -H "Authorization: Bearer $J_ACCESS_TOKEN" https://account.demandware.com/dw/rest/v1/...
```

## Common examples

**Use environment variables for credentials:**

```bash
export J_CLIENT_ID="aaaaaa-bbbb-cccc-dddd-eeeeeeee"
export J_CLIENT_SECRET="your_client_secret"
export J_SCOPES="mail"

client-credentials
```

**Check what environment variables are set after running:**

```
$ . client-credentials -c <CLIENT_ID> -s <CLIENT_SECRET>
$ client-credentials -E output
Output Environment Variables:
J_ACCESS_TOKEN: `eyJraW...`
J_ACCESS_TOKEN_EXPIRES_AT: `1745425200`
J_REFRESH_TOKEN: ``
J_REFRESH_TOKEN_EXPIRES_AT: ``
```

**Request a token with specific scopes:**

```
$ client-credentials -c <CLIENT_ID> -s <CLIENT_SECRET> -S "sfcc.shopper-customers sfcc.orders"
```

**Use AM token in a curl request:**

```bash
TOKEN=$(client-credentials -c $J_CLIENT_ID -s $J_CLIENT_SECRET)
curl -H "Authorization: Bearer $TOKEN" https://account.demandware.com/dw/rest/v1/...
```

## Endpoints

Two endpoint types are supported via the `-e` / `--endpoint` flag:

### AM (Account Manager)

The default. Targets Salesforce Commerce Cloud Account Manager at:

```
https://account.demandware.com/dwsso/oauth2/access_token
```

No additional parameters required beyond client ID and secret.

### SLAS (Shopper Login and API Access)

Requires shortcode (`-C`) and organization ID (`-o`). Targets:

```
https://{shortcode}.api.commercecloud.salesforce.com/shopper/auth/v1/organizations/{org_id}/oauth2/token
```

SLAS responses include a refresh token; AM responses do not.

## Environment variable workflow

`client-credentials` reads input from environment variables (prefixed with `J_`) and writes tokens back to environment variables. This lets you configure credentials once and source the script as needed:

**Input variables** (overridden by flags):
- `J_ENDPOINT` — `am` or `slas` (default: `am`)
- `J_CLIENT_ID` — Client ID
- `J_CLIENT_SECRET` — Client secret
- `J_SCOPES` — Space-separated scopes (optional)
- `J_SHORTCODE` — Shortcode (required for SLAS)
- `J_ORG_ID` — Organization ID (required for SLAS)

**Output variables** (exported after successful request):
- `J_ACCESS_TOKEN` — The access token
- `J_ACCESS_TOKEN_EXPIRES_AT` — Unix timestamp when the token expires
- `J_REFRESH_TOKEN` — Refresh token (SLAS only)
- `J_REFRESH_TOKEN_EXPIRES_AT` — Unix timestamp when the refresh token expires (SLAS only)

Use `-E` / `--env` to inspect variable state:

```
$ client-credentials -E input      # show input variables
$ client-credentials -E output     # show output variables
$ client-credentials -E            # show both (default)
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-e, --endpoint TYPE` | Endpoint type: `am` (default) or `slas` |
| `-c, --client-id ID` | Client ID (overrides `J_CLIENT_ID`) |
| `-s, --client-secret SECRET` | Client secret (overrides `J_CLIENT_SECRET`) |
| `-S, --scopes SCOPES` | Space-separated scopes (overrides `J_SCOPES`) |
| `-C, --shortcode CODE` | Shortcode (required for SLAS; overrides `J_SHORTCODE`) |
| `-o, --org-id ID` | Organization ID (required for SLAS; overrides `J_ORG_ID`) |
| `-E, --env [SCOPE]` | Print environment variables (`input`, `output`, or both) and exit |
| `-h, --help` | Display help |

### Environment variables

See "Environment variable workflow" above.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid endpoint type, missing required parameter, or request failure |

### Dependencies

- `curl` — for HTTP requests
- `jq` — for parsing JSON responses
- `base64` — for Basic auth header encoding
- `date` — for calculating expiration timestamps
