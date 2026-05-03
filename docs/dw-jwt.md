# dw-jwt

[View script](../dw-jwt)

Generate an RS256-signed JWT for authenticating to Salesforce B2C Commerce (Demandware) APIs via OAuth2 client credentials.

This script creates a JWT assertion signed with your private key, which you then exchange for an access token using the Account Manager OAuth2 endpoint. The token is valid for 30 minutes and includes the standard claims required by the SFCC `client_credentials` grant with `private_key_jwt` client authentication.

## Quick start

```bash
$ dw-jwt your-client-id ./private-key.pem
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ5b3VyLWNsaWVudC1pZCIsInN1YiI6InlvdXItY2xpZW50LWlkIiwiZXhwIjoxNzQ1MzQzMDAwLCJhdWQiOiJodHRwczovL2FjY291bnQuZGVtYW5kd2FyZS5jb206NDQzL2R3c3NvL29hdXRoMi9hY2Nlc3NfdG9rZW4iLCJpYXQiOjE3NDUzNDEyMDB9.signature_here...
```

The JWT is printed to stdout, ready to use as the `client_assertion` in your token request.

## Common examples

**Exchange the JWT for an access token:**

```bash
jwt=$(dw-jwt your-client-id ./private-key.pem)

curl -X POST "https://account.demandware.com/dwsso/oauth2/access_token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=$jwt"
```

The response contains an `access_token` field you can use in `Authorization: Bearer ...` headers.

**Pipe directly into jq to extract the token:**

```bash
dw-jwt your-client-id ./private-key.pem | xargs -I {} curl -X POST \
    "https://account.demandware.com/dwsso/oauth2/access_token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion={}" | jq -r .access_token
```

## JWT claims

The generated JWT includes these claims:

- `iss` (issuer): your client ID
- `sub` (subject): your client ID (same as issuer)
- `aud` (audience): `https://account.demandware.com:443/dwsso/oauth2/access_token`
- `exp` (expiration): current time + 30 minutes
- `iat` (issued at): current time

The token is signed with RS256 (RSA signature with SHA-256) using your private key.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `client_id` | SFCC API client ID (used as iss and sub claims) |
| `private_key_file` | Path to the RSA private key in PEM format |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Signing failed (openssl error) |
| 2 | Usage / argument error |
| 3 | Dependency error (`openssl` missing) |
| 4 | Private key file not found or unreadable |

### Dependencies

- `openssl` -- for base64 encoding and RSA signing

### Notes

- The private key must be in PEM format (starts with `-----BEGIN RSA PRIVATE KEY-----` or `-----BEGIN PRIVATE KEY-----`).
- The JWT is valid for exactly 30 minutes from generation time.
- If `openssl` fails (e.g., invalid key file, wrong format, permissions), the script exits with a non-zero status and may print openssl error messages to stderr.
