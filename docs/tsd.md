# tsd

[View script](../tsd)

Convert a number to something you can actually read -- paste in a Unix timestamp and get a datetime, or paste in a duration and get hours/minutes/seconds.

The name is short for "timestamp or duration." Give it a number, it figures out which one you meant. Timestamps come back as UTC and local time; durations come back broken into days, hours, minutes, seconds, and sub-second units down to nanoseconds.

## Quick start

```
$ tsd 1609477200
2021-01-01T05:00:00Z
2021-01-01 00:00:00 EST (GMT-5)

$ tsd 1800
30m
```

## Common examples

**Check how long something took (milliseconds from a log):**

```
$ tsd 135180 -m
2m 15s 180ms
```

**Break down a duration with mixed units:**

```
$ tsd 7238
2h 0m 38s
```

**Parse a millisecond-precision timestamp (13 digits):**

```
$ tsd 1609477200123
2021-01-01T05:00:00.123Z
2021-01-01 00:00:00.123 EST (GMT-5)
```

**Force a number to be treated as a duration** (useful if it happens to be 10 digits and would otherwise be detected as a timestamp):

```
$ tsd 1609477200 --duration
18628d
```

**Explain 1800 milliseconds:**

```
$ tsd 1800 -m
1s 800ms
```

## How detection works

tsd decides whether the input is a timestamp or a duration based on its digit count:

| Unit | Timestamp length | Example |
|---|---|---|
| seconds | 10 digits | `1609477200` |
| milliseconds | 13 digits | `1609477200123` |
| microseconds | 16 digits | `1609477200123456` |
| nanoseconds | 19 digits | `1609477200123456789` |

If the digit count matches exactly, it's a timestamp. Otherwise, it's a duration.

The unit is also inferred from digit count when you don't specify one -- 11 digits is assumed to be milliseconds, 14 digits microseconds, and so on. You can always override with `-s`, `-m`, `-u`, or `-n`.

Use `-d` / `--duration` to force duration interpretation regardless of digit count.

## Duration formatting

Zeroes in the middle are preserved so you can see the full breakdown:

```
$ tsd 172805
2d 0h 0m 5s

$ tsd 86405
1d 0h 0m 5s
```

Trailing zero units are omitted -- `tsd 172800` gives `2d`, not `2d 0h 0m 0s`:

```
$ tsd 172800
2d

$ tsd 7200
2h
```

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-s, --sec, --seconds` | Set unit to seconds (default) |
| `-m, --milli, --milliseconds` | Set unit to milliseconds |
| `-u, --micro, --microseconds` | Set unit to microseconds |
| `-n, --nano, --nanoseconds` | Set unit to nanoseconds |
| `-d, --duration` | Override timestamp detection, treating input as a duration |
| `-h, --help` | Display help |

Options can appear before or after the input number.

### Environment variables

| Variable | Description |
|---|---|
| `TSD_LOCALTIME` | Override the local timezone source (default: `/etc/localtime`) |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (missing input, unknown option, multiple units, multiple positionals) |

### Dependencies

None -- uses only standard Unix utilities (macOS or GNU `date`).
