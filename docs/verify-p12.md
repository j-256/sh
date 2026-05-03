# verify-p12

[View script](../verify-p12)

Quick smoke-test for Salesforce B2C Commerce WebDAV `/Cartridges` access. Sends a GET request to list cartridges and prints the HTTP status line plus directory links — if you see `200 OK` and a list of URLs, your auth works and your WebDAV endpoint is reachable.

Supports both Bearer token auth (default) and Basic auth (via `--basic`). Optional `.p12` mTLS mode lets you validate client certificate authentication at the same time, turning the test into a full "can I deploy code to this instance?" check. Useful after generating a fresh cert with `generate-p12`, or when troubleshooting certificate errors before attempting actual `dav` uploads.

If you need more than a cartridge listing — like verifying a specific code version path or seeing detailed directory structure — use `propfind-p12` instead.

## Quick start

```
$ verify-p12 dev01-web-example.demandware.net eyJhbGc...
GET https://dev01-web-example.demandware.net/on/demandware.servlet/webdav/Sites/Cartridges
HTTP/1.1 200 OK
/webdav/Sites/Cartridges/
/webdav/Sites/Cartridges/version1/
/webdav/Sites/Cartridges/active/
```

First line shows the URL being tested, then the HTTP status, then links to cartridge directories. If you see `200 OK` and directory links, your token is valid and the WebDAV endpoint is accessible.

## Common examples

**Basic auth** — for legacy username/password SFCC setups:

```bash
verify-p12 --basic dev01-web-example.demandware.net "jane.doe:s3cret!"
```

The credential is a single `user:pass` string (with a literal colon). The script base64-encodes it via `openssl` and sets the `Authorization: Basic` header. Colons inside the password are fine — only the first colon separates user from pass on the server side.

**Test with mTLS certificate** — validates both the token and the `.p12` client cert:

```bash
verify-p12 staging-na01-example.demandware.net "$BEARER_TOKEN" cert-password
```

Looks for `$USER-staging-na01-example.demandware.net.p12` in the current directory and uses it for mTLS. If the handshake succeeds and you get a `200`, your certificate is ready for production use.

**Basic auth with mTLS certificate:**

```bash
verify-p12 --basic staging-na01-example.demandware.net "jane.doe:s3cret" cert-password
```

**Specify a custom certificate path:**

```bash
verify-p12 prod05-web-example.demandware.net "$TOKEN" password123 /secure/certs/my-cert.p12
```

**Quick pre-deployment check** — verify token + cert before running a code deploy script:

```bash
if verify-p12 "$HOSTNAME" "$TOKEN" "$CERT_PASS"; then
    echo "WebDAV access confirmed, starting deploy..."
else
    echo "Can't reach WebDAV, aborting"
    exit 1
fi
```

**Debug 401 errors** — if your deploy scripts are getting "unauthorized," run this to isolate whether the problem is the token or something else:

```bash
verify-p12 dev-xxxx-example.demandware.net "$TOKEN"
# Returns 401? Token is expired or invalid.
# Returns 200? Token is fine; problem is elsewhere (wrong path, cert issue, etc.)
```

## Bearer auth vs Basic auth

SFCC WebDAV supports both Bearer token auth and Basic auth. Bearer is the modern path — tokens typically come from SCAPI Account Manager API or an OAuth client-credentials flow. Basic is the legacy path for username/password.

Pass `--basic` to switch modes. Output is identical between the two — only the `Authorization` header differs. Bearer is the default because it's what most SFCC workflows use today.

## mTLS certificate validation

When you provide a `p12_password`, the script adds mTLS client certificate authentication to the request. The `.p12` file must exist in your current directory (default name: `$USER-hostname.p12`, e.g. `jane-dev01-web-example.demandware.net.p12`).

The script uses curl's `-k` flag to skip CA verification, meaning it will succeed even if the server's certificate is self-signed or you haven't provided the SFCC CA cert. This is intentional — the goal is to validate that your *client* certificate works, not to verify the server's certificate chain.

If you need full CA validation (server cert + client cert), use `propfind-p12` instead, which requires both the `.p12` and the CA cert file.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `--basic` | Use Basic auth instead of Bearer |
| `hostname` | Instance hostname (e.g. `dev01-web-example.demandware.net`) |
| `token` | Bearer token for authorization (default auth mode) |
| `user:pass` | Username and password for Basic auth (with `--basic`) |
| `p12_password` | (optional) Password for the `.p12` client certificate |
| `p12_file` | (optional) Path to `.p12` file (default: `$USER-hostname.p12`) |
| `-h, --help` | Display help |

The first two positional arguments (hostname and credential) are required. The third and fourth are optional — if you omit `p12_password`, the script tests auth only, without mTLS.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Request succeeded (curl returned success); check output for HTTP status line |
| 1 | Argument / usage error |
| Non-zero | curl error (network issue, SSL failure, missing file, etc.) |

A *successful* curl invocation (exit 0) doesn't guarantee `200 OK` — you might get `401 Unauthorized` or `403 Forbidden` in the output. Check the HTTP status line to confirm access.

Common curl exit codes:
- `35` — SSL/TLS handshake failure (certificate problem, protocol mismatch)
- `51` — Server certificate verification failed (shouldn't happen due to `-k`, but possible if curl is misconfigured)
- `58` — Client certificate problem (`.p12` can't be read, wrong password, or file doesn't exist)
- `60` — CA certificate problem (shouldn't happen with `-k`)

### Dependencies

- `curl` — must support `.p12` certificates (compiled with OpenSSL or LibreSSL)
- `openssl` — only required with `--basic`, used to base64-encode `user:pass`

### Output format

The script prints three things:

1. **Request line** (stderr) — `GET https://hostname/...`
2. **HTTP status line** (stdout) — `HTTP/1.1 200 OK` or similar
3. **Cartridge directory links** (stdout) — WebDAV paths like `/webdav/Sites/Cartridges/version1/`

If you see the status line but no directory links, the request succeeded but the response body didn't contain the expected `<a href="...">` tags. This might mean the WebDAV endpoint returned an error page, or the HTML structure changed.

### Warnings

- This script tests the *root* cartridges directory (`/webdav/Sites/Cartridges`), not a specific code version. If you need to test a particular version path (e.g. `/Cartridges/version1/app_storefront_base/`), use `propfind-p12` instead.
- Bearer tokens expire. If you get a `401` after this worked previously, regenerate your token.
- The `-k` flag disables server certificate verification, so this script won't catch CA cert problems. If you need to validate the entire mTLS chain including the server's CA, use `propfind-p12`.
- The `.p12` file must be readable and password-protected. If curl reports "bad password" but you know the password is correct, the file might be corrupted or in the wrong format.
