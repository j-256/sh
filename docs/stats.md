# stats

Calculate count, total, average, range, and outliers from a list of integers. Feed it numbers from a pipe and get a statistical summary -- useful for quick analysis of response times, file sizes, or any numeric column from a log.

Outliers are detected using the 1.5 * IQR (Interquartile Range) method, the same approach used in box plots. This catches values that fall far outside the typical distribution without being overly sensitive to minor variations.

## Quick start

```
$ printf '100\n120\n110\n115\n105\n125\n90\n95\n130\n200\n' | stats
Count: 10
Total: 1190
Average: 119
Range: 110 (90 to 200)
Outliers: 200
          1 of 10 (10.0%)
```

## Common examples

**Analyze response times from a log:**

```
$ grep 'response_time' access.log | awk '{print $7}' | stats
Count: 847
Total: 84223
Average: 99
Range: 1847 (12 to 1859)
Outliers: 1847 1859
          2 of 847 (0.2%)
```

**Break down a dataset with space-separated values:**

```
$ echo "50 60 70 80 90" | stats
Count: 5
Total: 350
Average: 70
Range: 40 (50 to 90)
Outliers: 
          0 of 5 (0.0%)
```

Whitespace-separated input is normalized before processing: newlines, spaces, and tabs are all treated as separators.

**Show the dataset before statistics:**

```
$ printf '100\n120\n110\n115\n105\n125\n90\n95\n130\n200\n' | stats -n
100, 120, 110, 115, 105, 125, 90, 95, 130, 200
Count: 10
Total: 1190
Average: 119
Range: 110 (90 to 200)
Outliers: 200
          1 of 10 (10.0%)
```

**Check a large sequence:**

```
$ seq 1 100 | stats
Count: 100
Total: 5050
Average: 50
Range: 99 (1 to 100)
Outliers:
```

## How outlier detection works

The script uses the Interquartile Range (IQR) method to identify outliers:

1. Sort the dataset
2. Calculate Q1 (25th percentile) and Q3 (75th percentile)
3. Compute IQR = Q3 - Q1
4. Define outlier bounds: lower = Q1 - 1.5 * IQR, upper = Q3 + 1.5 * IQR
5. Any value below the lower bound or above the upper bound is flagged as an outlier

This is the same approach used in box-and-whisker plots. The 1.5 multiplier is a standard threshold that balances sensitivity (catching real anomalies) with specificity (avoiding false positives from normal variation).

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-n` | Print the dataset (comma-separated) before statistics |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | Usage error (non-integer input detected) |
| `3` | Dependency error (`bc` missing) |

### Dependencies

- `bc` (for floating-point calculations in outlier detection and percentage)
