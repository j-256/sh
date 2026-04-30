# inflate

Adjust historical USD amounts for inflation -- paste in a dollar amount and year, get back what that money is worth today.

You're reading a 1985 article about a $50,000 salary, or a 1970s book that mentions $25 concert tickets. What does that actually mean in modern dollars? `inflate` fetches CPI data from the US Bureau of Labor Statistics and tells you the equivalent buying power in the most recent month available (typically 1-2 months behind current date).

## Quick start

```
$ inflate 100 1970
$100.00: Jan 1970 -> Mar 2026
873.58
```

The adjusted amount goes to stdout (so you can pipe it or use it in scripts), and the summary line goes to stderr.

## Common examples

**Adjust a specific month and year:**

```
$ inflate 50000 1985 6
$50000.00: Jun 1985 -> Mar 2026
153444.70
```

**Get just the number** (suppress the summary line):

```
$ inflate 25 1950 2>/dev/null
351.29
```

**Use the result in a calculation:**

```
$ amount=$(inflate 1000 1980 2>/dev/null)
$ echo "Double that is: $((amount * 2))"
Double that is: 7026.14
```

**December 2000 dollars:**

```
$ inflate 250 2000 12
$250.00: Dec 2000 -> Mar 2026
466.06
```

## How it works

`inflate` fetches the BLS inflation calculator page at `https://data.bls.gov/cgi-bin/cpicalc.pl`, extracts the most recent month available from the page's dropdown menu (typically 1-2 months behind the current date), then submits your amount/year/month to get the adjusted value. The calculator uses the Consumer Price Index (CPI-U) data maintained by the Bureau of Labor Statistics.

Month defaults to January (1) if not specified. The BLS calculator supports data back to 1913.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `amount` | Dollar amount to adjust (e.g. 150, 1234.56) |
| `year` | Historical year (e.g. 1970) |
| `month` | Month as integer 1-12 (default: 1 / January) |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Missing required argument (amount or year), or BLS calculator returned no result |

### Dependencies

- `curl` - to fetch CPI data from the BLS website

### Warnings

If the BLS website structure changes or the calculator is unavailable, the script will fail with "Failed to convert..." and exit code 1. The script fetches data on every invocation -- there's no local cache.
