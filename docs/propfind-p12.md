# propfind-p12

[View script](../propfind-p12)

Smoke-test an mTLS-protected Salesforce B2C Commerce WebDAV endpoint using a `.p12` client certificate and Bearer token. Sends a PROPFIND request (WebDAV's equivalent of `ls`) to list cartridges in a specified code version, validating that your certificate, CA chain, and token all work together before you try to deploy code.

Useful after generating a fresh `.p12` with `generate-p12`, or when troubleshooting "certificate required" errors from SFCC staging WebDAV mounts. If the PROPFIND succeeds and you see XML back, the entire mTLS chain is working. If it fails, you know your cert isn't ready for actual `dav` operations yet.

## Quick start

```
$ propfind-p12 -t eyJhbGc... dev01-web-example.demandware.net version1 cert-password
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/on/demandware.servlet/webdav/Sites/Cartridges/version1/</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>version1</D:displayname>
        <D:resourcetype><D:collection/></D:resourcetype>
      </D:propstat>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/on/demandware.servlet/webdav/Sites/Cartridges/version1/app_storefront_base/</D:href>
    ...
  </D:response>
</D:multistatus>
```

You'll see XML listing cartridges at the root of your code version if the certificate and token are valid.

## Common examples

**Test a certificate you just generated:**

```bash
# Generate the .p12
generate-p12 dev01-web-example.demandware.net cert-password

# Validate it works against WebDAV
propfind-p12 -t "$BEARER_TOKEN" dev01-web-example.demandware.net version1 cert-password
```

**Debug why WebDAV uploads are failing** – if PROPFIND returns XML instead of certificate errors, the problem is elsewhere (permissions, token expiry, wrong path):

```bash
propfind-p12 -t "$TOKEN" staging-na01-example.demandware.net active cert-password
```

**Use the `SFCC_TOKEN` env var** instead of passing `-t` every time:

```bash
export SFCC_TOKEN="$TOKEN"
propfind-p12 staging-na01-example.demandware.net active cert-password
```

**Verify a new CA cert** — if your SFCC instance's CA certificate rotated and you downloaded `hostname_01.crt`, PROPFIND will immediately tell you if curl trusts it:

```bash
propfind-p12 -t "$TOKEN" prod05-web-example.demandware.net current cert-password
# Fails with SSL error if CA cert is wrong or expired
```

## File expectations

The script expects two certificate files in your current directory, named using the hostname you provide:

1. **`$USER-hostname.p12`** — Your client certificate (e.g. `jane-dev01-web-example.demandware.net.p12`)
2. **`hostname_01.crt`** — The CA certificate for SFCC's staging environment (e.g. `dev01-web-example.demandware.net_01.crt`)

If these don't exist, curl will fail with a "no such file" error. You can generate the `.p12` with `generate-p12`, and the CA cert is typically downloaded from SFCC Account Manager or provided by your SFCC administrator.

## When to use this vs verify-p12

- **`verify-p12`** — Quick smoke-test against the WebDAV `/Cartridges` root using Bearer or Basic auth, with optional mTLS. Skips server CA verification (`-k`), so it won't catch CA-chain problems.
- **`propfind-p12`** — Tests the full mTLS chain: client cert + server CA + Bearer token against a specific code version. Uses `--cacert` and requires a matching CA cert file.

If `verify-p12` passes but `propfind-p12` fails, the CA cert is likely the issue (or the code version path doesn't exist). If both fail, fix the client certificate or token first.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `hostname` | Instance hostname (e.g. `dev01-web-example.demandware.net`) |
| `code_version` | Code version path segment (e.g. `version1`, `active`, `staging`) |
| `p12_password` | Password for the `.p12` certificate |
| `-t, --token TOKEN` | Bearer token for authorization (or set `$SFCC_TOKEN`) |
| `-h, --help` | Show help |

The three positional arguments (`hostname`, `code_version`, `p12_password`) are required. The Bearer token is required too, supplied via `-t/--token` or the `$SFCC_TOKEN` environment variable.

### Environment variables

| Variable | Description |
|---|---|
| `SFCC_TOKEN` | Fallback source for the Bearer token when `-t/--token` is not given |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | PROPFIND succeeded; mTLS and auth are working |
| 2 | Usage / argument error (missing required argument) |
| 4 | Required `.p12` or CA cert file not found |
| * | curl exit code (SSL handshake failure, auth failure, network error, etc.) |

For any non-zero code other than 2 and 4, the script returns curl's exit code directly. Common values:

- `35` — SSL/TLS handshake failure (wrong CA cert, expired cert, or SFCC rejecting the client cert)
- `51` — Server certificate verification failed (CA cert is wrong or missing)
- `58` — Client certificate problem (`.p12` can't be read, wrong password, or file doesn't exist)
- `60` — CA certificate problem (can't verify server's cert with provided CA)

### Dependencies

- `curl` — must be compiled with OpenSSL or LibreSSL for `.p12` support

### Caveats

- The script constructs the WebDAV URL as `https://hostname/on/demandware.servlet/webdav/Sites/Cartridges/code_version`. This is standard for SFCC staging instances but won't work if your setup uses a non-standard path.
- Bearer tokens expire. If you get a 401 after a successful SSL handshake, regenerate your token via Account Manager or SCAPI.
- The PROPFIND request uses `Depth: 1`, listing the directory and its immediate children (one level deep). You'll see all cartridges at the root of your code version, but not nested subdirectories.
