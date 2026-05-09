# baseconv

[View script](../baseconv)

Convert a number between numeral bases -- binary, octal, decimal, hexadecimal -- with positional `from to number` arguments.

A thin wrapper over `bc` that does the bookkeeping `bc` won't: case-folding hex digits, validating that the input is well-formed for the source base, and accepting friendly base names (`hex`, `dec`) and abbreviations (`h`, `d`, `x`) instead of forcing you to remember which numeric base goes where in `obase`/`ibase`. Aliased to a single letter it becomes the fastest way to do one-off conversions from the shell.

## Quick start

```
$ baseconv hex dec ff
255
```

## Common examples

**Decimal to hex:**

```
$ baseconv dec hex 255
FF
```

**Binary to hex (byte-wide):**

```
$ baseconv bin hex 11111111
FF
```

**Hex to binary (multi-byte):**

```
$ baseconv hex bin deadbeef
11011110101011011011111011101111
```

**Numeric base names work too:**

```
$ baseconv 16 2 ff
11111111
```

**Single-letter abbreviations for max brevity:**

```
$ baseconv h d ff
255
```

## Base aliases

Each base accepts its name, a single-letter abbreviation, and its numeric value:

| Base | Aliases |
|---|---|
| Binary | `bin`, `b`, `2` |
| Octal | `oct`, `o`, `8` |
| Decimal | `dec`, `d`, `10` |
| Hexadecimal | `hex`, `h`, `x`, `16` |

`x` is included for hex because `h` is already overloaded as the help flag in many tools and because `0x` is the standard hex prefix.

Base names and hex digits are case-insensitive. Hex output is uppercased.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Show help |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (missing arg, invalid base, invalid digit for base) |
| 3 | Dependency error (bc missing) |

### Dependencies

- `bc` (for the actual base conversion)
