# client-credentials

[View script](../client-credentials)

Fetch an OAuth2 access token using the `client_credentials` grant. Built for Salesforce Commerce Cloud endpoints (Account Manager and SLAS), but the pattern is standard OAuth2 -- point it at any token URL that speaks `client_credentials`.

The token prints to stdout. Capture it with command substitution (`TOKEN=$(client-credentials ...)`) and use it in subsequent commands.

## Quick start

**Get an Account Manager (AM) token:**

```
$ client-credentials -c aaaaaa-bbbb-cccc-dddd-eeeeeeee -s your_client_secret
eyJraW...truncated
```

**Get a SLAS token** (includes refresh token in the JSON response, but only the access token prints):

```
$ client-credentials -e slas -c aaaaaa-bbbb-cccc-dddd-eeeeeeee -s your_client_secret -C zzxy -o f_ecom_zzzz_prd
eyJraW...truncated
```

## Common examples

**Use environment variables for credentials:**

```bash
export J_CLIENT_ID="aaaaaa-bbbb-cccc-dddd-eeeeeeee"
export J_CLIENT_SECRET="your_client_secret"
export J_SCOPES="mail"

client-credentials
```

**Capture the token in a variable:**

```bash
TOKEN=$(client-credentials -c "$J_CLIENT_ID" -s "$J_CLIENT_SECRET")
curl -H "Authorization: Bearer $TOKEN" https://account.demandware.com/dw/rest/v1/...
```

**Request a token with specific scopes:**

```
$ client-credentials -c <CLIENT_ID> -s <CLIENT_SECRET> -S "sfcc.shopper-customers sfcc.orders"
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

## Environment variables

`client-credentials` reads input from environment variables prefixed with `J_`, so you can configure credentials once and run the script as needed without repeating the flags:

- `J_ENDPOINT` — `am` or `slas` (default: `am`)
- `J_CLIENT_ID` — Client ID
- `J_CLIENT_SECRET` — Client secret
- `J_SCOPES` — Space-separated scopes (optional)
- `J_SHORTCODE` — Shortcode (required for SLAS)
- `J_ORG_ID` — Organization ID (required for SLAS)

Each is overridden by the matching flag (`-c` for `J_CLIENT_ID`, etc.).

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
| `-h, --help` | Display help |

### Environment variables

See "Environment variables" above.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime failure (token request failed) |
| 2 | Usage error (unknown flag, invalid endpoint, missing required parameter) |

### Dependencies

- `curl` — for HTTP requests
- `jq` — for parsing JSON responses
- `base64` – for Basic auth header encoding
