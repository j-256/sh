# convert-size

Convert file sizes between SI (1000-based) and binary (1024-based) unit systems.

macOS and most Unix systems report file sizes in SI units (GB = 1,000,000,000 bytes), while Windows and binary-centric tooling uses binary units (GiB = 1,073,741,824 bytes). This script translates between the two when you need to compare sizes across systems or match what a specific OS will show.

## Quick start

```
$ convert-size -t binary 500G
465.66G
```

That's 500 GB (SI) converted to binary GiB -- what Windows would report for the same byte count.

## Common examples

**Convert a macOS reported size to what Windows shows:**

```
$ convert-size -t win 256G
238.42G
```

**Convert a Windows size to SI (macOS/Linux):**

```
$ convert-size -t si 64G
68.72G
```

**Convert a DVD size (4.7GB advertised) to binary:**

```
$ convert-size -t binary 4700M
4483.03M
```

**Convert a Blu-ray capacity (25GiB) to SI:**

```
$ convert-size -t si 25G
26.84G
```

**Force a unit when the input is a bare number:**

```
$ convert-size -t binary -u G 1000
931.32G
```

Without `-u G`, the script would treat `1000` as bytes.

## How it works

1. Parse the size and unit (B, K, M, G, T) from the input.
2. Convert to bytes using the source system (inferred from context: SI if converting to binary, binary if converting to SI).
3. Divide by the target unit's multiplier in the target system.
4. Output the converted size with the same unit letter appended.

The script automatically infers the source system based on the target: if you're converting `-t binary`, it assumes the input is SI. If you're converting `-t si`, it assumes the input is binary.

## Aliases

Target systems support multiple aliases:

- **SI:** `mac`, `macos`, `si`, `unix`, `nix`
- **Binary:** `win`, `windows`, `bin`, `binary`

Use whichever makes the most sense for your context.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-t, --to SYSTEM` | Target number system (required). See aliases above. |
| `-u, --unit UNIT` | Override the unit suffix on the input (B, K, M, G, T). Defaults to parsing suffix from input, or `B` if none. |
| `-h, --help` | Show help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Usage error (missing required flag, invalid unit, invalid size, duplicate flags) |

### Constraints

- Input size must be a **positive integer** (no decimals). For fractional sizes, scale up to the next unit (e.g., use `4700M` instead of `4.7G`).
- Units are case-insensitive in input and forced to uppercase in output.
- Trailing zeros after the decimal point are trimmed in output (e.g., `4.50G` becomes `4.5G`).

### Dependencies

- `bc` (for arbitrary-precision arithmetic)
