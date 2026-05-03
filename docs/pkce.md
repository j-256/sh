# pkce

[View script](../pkce)

Generate a PKCE (Proof Key for Code Exchange) code verifier and its corresponding SHA256 challenge for OAuth2 authorization flows.

PKCE is an extension to OAuth2's authorization-code flow that prevents interception attacks. It's required by many OAuth2 providers for native apps and single-page applications, and increasingly recommended for all client types. Per RFC 7636, the client generates a random code verifier, computes a challenge from it, sends the challenge when requesting an authorization code, then sends the verifier when exchanging the code for tokens -- proving the same client is making both requests.

This script generates both values ready to use. By default they're tab-separated (easy to extract with `cut` or `awk`), or newline-separated for `read` assignments.

## Quick start

```
$ pkce
EvRjZ8x_Y3-pQk2Nw7Lm... (128 chars)	3FxU9A2b... (43 chars)
```

The first value is the verifier (128 base64url characters), the second is the challenge (43 base64url characters, derived via SHA256).

## Common examples

**Split into separate variables using tab delimiter:**

```bash
codes="$(pkce)"
verifier="$(echo "$codes" | cut -f1)"
challenge="$(echo "$codes" | cut -f2)"
```

**Assign directly with process substitution:**

```bash
{ read -r verifier; read -r challenge; } < <(pkce -n)
```

**Use in an OAuth2 authorization request** (construct the authorization URL with the challenge, store the verifier for the token exchange):

```bash
{ read -r verifier; read -r challenge; } < <(pkce -n)

# Authorization request (user visits this URL)
auth_url="https://auth.example.com/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&code_challenge=$challenge&code_challenge_method=S256"

# Later, exchange the authorization code for tokens (send the verifier)
curl -X POST https://auth.example.com/token \
  -d "grant_type=authorization_code" \
  -d "code=$AUTH_CODE" \
  -d "client_id=$CLIENT_ID" \
  -d "redirect_uri=$REDIRECT_URI" \
  -d "code_verifier=$verifier"
```

**Use with jq to build JSON payload:**

```bash
codes="$(pkce)"
verifier="$(echo "$codes" | cut -f1)"
challenge="$(echo "$codes" | cut -f2)"

jq -n --arg v "$verifier" --arg c "$challenge" \
  '{code_verifier: $v, code_challenge: $c, code_challenge_method: "S256"}'
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-n, --newline` | Separate verifier and challenge with a newline instead of a tab |
| `-h, --help` | Show help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 3 | Dependency error (`openssl` missing) |

### Dependencies

- `openssl` (for random byte generation and SHA256 hashing)

### Technical details

- Verifier: 96 random bytes encoded as base64url (128 characters, unpadded)
- Challenge: SHA256 hash of the verifier, encoded as base64url (43 characters, unpadded)
- Challenge method: S256 (the only method supported by this script; use "S256" in your authorization request)

RFC 7636 allows verifiers from 43 to 128 characters. This script always generates 128-character verifiers (maximum entropy).

Base64url encoding replaces `+` with `-`, `/` with `_`, and removes `=` padding -- making the values safe for URLs and JSON without escaping.
