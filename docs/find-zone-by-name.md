# find-zone-by-name

[View script](../find-zone-by-name)

Search for a Salesforce Commerce Cloud CDN zone by name substring. Pages through the SCAPI zones/info endpoint until it finds a zone whose name contains your search term, then returns the full zone JSON object.

Useful when you remember part of a zone name but not the full hostname, or when you need to look up the zone ID for a staging environment that follows a naming pattern. The script handles pagination automatically -- you just provide the substring and let it search.

## Quick start

```
$ find-zone-by-name -s kv7kzm78 -r abcd -i stg -n example -j eyJ...
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "stg-abcd-example-com.cc-ecdn.net",
  "status": "active",
  "type": "secondary_dns"
}
```

## Common examples

**Search for a zone by substring** (finds any zone whose name contains "staging"):

```bash
find-zone-by-name -s kv7kzm78 -r abcd -i stg -n staging -j eyJ...
```

**Use environment variables instead of flags:**

```bash
export J_JWT=eyJ...
export J_SHORTCODE=kv7kzm78
export J_REALM=abcd
export J_INSTANCE=stg
export J_TARGET=example

find-zone-by-name
```

**Search for production zones:**

```bash
find-zone-by-name -s kv7kzm78 -r abcd -i prd -n example -j eyJ...
```

## Output format

When a matching zone is found, the full JSON object from the SCAPI response is printed to stdout. The object typically includes:

- `id` -- the zone UUID
- `name` -- the zone hostname
- `status` -- zone status (e.g., "active")
- `type` -- zone type (e.g., "secondary_dns")

The script returns immediately after finding the first match. If no zone is found after paginating through all results, an error message is printed to stderr.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-j, --jwt, --token` | JWT bearer token for SCAPI authentication |
| `-s, --shortcode` | SCAPI shortcode (8-character lowercase alphanumeric) |
| `-r, --realm` | Realm ID (4-character lowercase alphabetic) |
| `-i, --instance` | Instance identifier (e.g., `prd`, `stg`, `dev`, `s01`-`s99`, `001`-`999`) |
| `-n, --name, -t, --target` | Zone name substring to search for (case-sensitive, partial match) |
| `-h, --help` | Show help message |

All options except `-h`/`--help` are required unless the corresponding environment variable is set.

### Environment variables

| Variable | Description |
|---|---|
| `J_JWT` | JWT bearer token (alternative to `-j`/`--jwt`) |
| `J_SHORTCODE` | SCAPI shortcode (alternative to `-s`/`--shortcode`) |
| `J_REALM` | Realm ID (alternative to `-r`/`--realm`) |
| `J_INSTANCE` | Instance identifier (alternative to `-i`/`--instance`) |
| `J_TARGET` | Zone name substring (alternative to `-n`/`--name`) |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Zone found and returned |
| `1` | Missing required parameter, invalid option, no matching zone found, or API request failed |

### Dependencies

- `curl` (for SCAPI requests)
- `jq` (for JSON parsing and filtering)
