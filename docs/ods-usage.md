# ods-usage

Calculate On-Demand Sandbox (ODS) credits used from a Salesforce B2C Commerce ODS API response.

Salesforce B2C Commerce's On-Demand Sandbox feature bills by credit consumption - sandboxes accrue credits per minute based on whether they're running (1x/2x/4x multiplier depending on instance size) or stopped (0.3x). The ODS API returns raw minute counts; this script crunches them into human-readable breakdowns by sandbox count, uptime/downtime per profile, and total credits used.

Feed it a JSON response from the `getRealmUsage` endpoint (either as an argument or from your clipboard) and it calculates the credit math for you. Particularly useful for tracking burn rate across a billing period or explaining where credits went.

## Quick start

```
$ ods-usage '{"data":{"createdSandboxes":9,"activeSandboxes":8,"deletedSandboxes":0,"minutesDown":194006,"minutesUp":1389,"minutesUpByProfile":[{"profile":"medium","minutes":1050},{"profile":"large","minutes":289},{"profile":"xlarge","minutes":50}]}}'
Sandbox Counts
created: 9
active:  8
deleted: 0
Uptime & Downtime
min up:   1389
> medium: 1050
>  large: 289
> xlarge: 50
min down: 194006
Credits Used
up:    1828
down:  58201
total: 60029
```

## Common examples

**Feed JSON from a saved API response:**

```bash
ods-usage "$(cat ods-report-2026-04.json)"
```

**Pull JSON from clipboard** (macOS via `pbpaste`):

```bash
ods-usage
```

**Pipe directly from curl:**

```bash
curl -s "https://admin.dx.commercecloud.salesforce.com/api/v1/realms/xxxx/usage?from=2026-04-01&to=2026-04-30&detailedReport=false" \
  -H "Authorization: Bearer $TOKEN" | jq -c . | xargs -0 ods-usage
```

## Input format

The script expects JSON matching the structure returned by the SFCC ODS API's `getRealmUsage` endpoint. Required fields under `.data`:

- `createdSandboxes` - total sandboxes created during the period
- `activeSandboxes` - currently active sandboxes
- `deletedSandboxes` - sandboxes deleted during the period
- `minutesDown` - total minutes sandboxes were stopped
- `minutesUp` - total minutes sandboxes were running (all profiles)
- `minutesUpByProfile` - array of objects with `profile` (string: `"medium"`, `"large"`, `"xlarge"`) and `minutes` (number)

Example minimal input:

```json
{
  "data": {
    "createdSandboxes": 5,
    "activeSandboxes": 4,
    "deletedSandboxes": 0,
    "minutesDown": 100000,
    "minutesUp": 1200,
    "minutesUpByProfile": [
      {"profile": "medium", "minutes": 1200}
    ]
  }
}
```

## Output format

Three sections:

1. **Sandbox Counts** - created/active/deleted tallies for the reporting period
2. **Uptime & Downtime** - total minutes up, breakdown by profile (medium/large/xlarge), and total minutes down
3. **Credits Used** - credits consumed while up, while down, and the grand total

Credit multipliers per minute:
- **Medium** (up): 1.0x
- **Large** (up): 2.0x
- **Xlarge** (up): 4.0x
- **Stopped** (down): 0.3x (applies to all profiles)

Headers are underlined when stdout is a terminal (via `tput smul`/`rmul`).

---

## Reference

### All options

The script does not accept flags. It takes a single optional argument:

- **Argument 1** (optional): JSON string from the ODS API. If omitted, pulls from clipboard via `pbpaste`.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (invalid JSON, missing required fields, no input) |
| 3 | Dependency error (jq missing; pbpaste missing in clipboard mode) |

### Dependencies

- `jq` - required for JSON parsing
- `pbpaste` (macOS) - required only if invoking without arguments (clipboard mode)
- `tput` (optional) - used for underlined headers; falls back gracefully if unavailable

### Caveats

- Clipboard mode (`pbpaste`) is macOS-only. On other platforms, always pass JSON as an argument.
- The script assumes credit multipliers are hardcoded in source (medium=1, large=2, xlarge=4, stopped=0.3). If Salesforce changes the pricing model, the script needs updating.
