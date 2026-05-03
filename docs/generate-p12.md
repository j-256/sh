# generate-p12

[View script](../generate-p12)

Generate a PKCS#12 (.p12) client certificate for Salesforce B2C Commerce staging sandbox code uploads that require mutual TLS authentication.

When you need to upload code to an SFCC staging instance with MFA enabled, Business Manager won't accept username/password alone — you need a client certificate. This script takes a CA cert bundle (provided by Salesforce or your admin) and generates a .p12 file you can import into your system keychain and configure in UX Studio or your WebDAV client.

It's an interactive wrapper around openssl that handles the three-step dance: generate a CSR and private key, sign it with the CA, and bundle everything into a password-protected .p12 file.

## Quick start

Run from the directory where you unzipped the CA cert bundle (the files ending in `_01.crt`, `_01.key`, `_01.txt`, and `.srl`):

```bash
$ generate-p12
BM Hostname: cert.staging.example-realm.demandware.net

Using these files in /path/to/cert-bundle:
  cert.staging.example.realm.demandware.net_01.crt
  cert.staging.example.realm.demandware.net_01.key
  cert.staging.example.realm.demandware.net_01.txt
  cert.staging.example.realm.demandware.net.srl
  jklein-cert.staging.example.realm.demandware.net.req
  jklein-cert.staging.example.realm.demandware.net.key
  jklein-cert.staging.example.realm.demandware.net.pem
  jklein-cert.staging.example.realm.demandware.net.p12

Years until expiration: 1

[... openssl prompts for CSR fields (Country, State, Common Name, etc.) ...]

Created CSR:
/path/to/cert-bundle/jklein-cert.staging.example.realm.demandware.net.req
Created private key:
/path/to/cert-bundle/jklein-cert.staging.example.realm.demandware.net.key

Created X.509 intermediate certificate:
/path/to/cert-bundle/jklein-cert.staging.example.realm.demandware.net.pem

NOTE: This encrypts the client certificate itself, so that it cannot be used without this password.
secure prompt: no text will appear as you type
Enter Export Password:
Verifying - Enter Export Password:

Created PKCS12 client certificate:
/path/to/cert-bundle/jklein-cert.staging.example.realm.demandware.net.p12

Finished successfully. Full path to p12:
/path/to/cert-bundle/jklein-cert.staging.example.realm.demandware.net.p12
```

## Common examples

**Run from a different directory:**

```bash
generate-p12 /path/to/cert-bundle
```

**Flexible hostname formats** — provide the hostname however you like; the script normalizes it:

```bash
# These all produce the same cert:
cert.staging.example.realm.demandware.net
example.realm.demandware.net
example.realm
example-realm
example_realm
```

The script strips any existing instance type prefix (`production.`, `development.`, `staging.`), converts hyphens and underscores to dots, prepends `cert.staging.`, and appends `.demandware.net`.

## What gets generated

The script creates four new files in the cert bundle directory, all prefixed with `$USER-<hostname>`:

| File | Description |
|---|---|
| `.req` | Certificate Signing Request (CSR) |
| `.key` | Your private key (unencrypted PEM format) |
| `.pem` | CA-signed X.509 certificate |
| `.p12` | PKCS#12 bundle (your private key + signed cert + CA cert, encrypted with your chosen password) |

The `.p12` file is what you'll import and use. The others are intermediate artifacts kept for reference.

## Suffix auto-detection

CA cert bundles often contain multiple generations of certificates with numeric suffixes: `_01`, `_02`, `_03`, etc. The script automatically finds the **highest-numbered suffix** that has all three required files (`.crt`, `.key`, `.txt`).

If you have:

```
cert.staging.example.realm.demandware.net_01.crt
cert.staging.example.realm.demandware.net_01.key
cert.staging.example.realm.demandware.net_01.txt
cert.staging.example.realm.demandware.net_02.crt
cert.staging.example.realm.demandware.net_02.key
cert.staging.example.realm.demandware.net_02.txt
cert.staging.example.realm.demandware.net.srl
```

It will use `_02` (the latest complete bundle).

## Prerequisites

You need a CA cert bundle provided by Salesforce or your sandbox admin. It should contain:

- `<hostname>_XX.crt` — CA certificate
- `<hostname>_XX.key` — CA private key
- `<hostname>_XX.txt` — CA password file
- `<hostname>.srl` — CA serial number file (no numeric suffix)

These are typically provided as a `.zip` you unzip into a dedicated directory.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `[cert_bundle_directory]` | Path to the directory containing the CA cert bundle. Defaults to current directory |
| `-h, --help` | Show help message |

### What you'll be prompted for

1. **BM Hostname** — the Business Manager hostname for your staging instance (any format works; see "Common examples" above)
2. **Years until expiration** — how long the certificate should be valid (must be a positive integer)
3. **CSR fields** — openssl will prompt for Country, State/Province, Locality (City), Organization, Organizational Unit, Common Name, and Email. These go into the certificate metadata
4. **Export password** — encrypts the final .p12 file (you'll need this password when importing the certificate)

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Runtime failure (bundle files missing, openssl step failed) |
| `2` | Usage error (directory arg is not accessible) |
| `3` | Dependency error (`openssl` missing) |

### Dependencies

- `openssl` (required)

### Warnings

**The export password is critical** — it encrypts the .p12 file. If you lose it, you'll need to regenerate the certificate. Choose something you can remember or store in a password manager.

**Keep the .p12 and .key files secure** — they're authentication credentials. Don't commit them to git or share them publicly.

**Check your cert bundle suffix** — if the script reports "No complete cert bundle found", make sure all three files (`_XX.crt`, `_XX.key`, `_XX.txt`) exist for at least one suffix, plus the `.srl` file with no suffix.
