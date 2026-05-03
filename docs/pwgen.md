# pwgen

[View script](../pwgen)

Generate random passwords or strings with configurable length, charset, and character exclusions.

Especially useful for sites with restrictive password requirements -- "must be exactly 12 characters, lowercase and numbers only, no special characters" becomes `pwgen -c '[:lower:][:digit:]' 12`.

Unlike the popular Linux `pwgen` utility (Tollef Fog Heen's tool from the 2000s), this is a simpler, customizable generator focused on charset flexibility rather than pronounceability.

## Quick start

```
$ pwgen
eOC3OCKtXbLGQ=}q?GC)p&8MqhO&e|2/
```

Default: 32 characters from alphanumeric + punctuation (equivalent to `[:alnum:][:punct:]`).

## Common examples

**Generate a 12-character password:**

```
$ pwgen 12
il6ZtXx2%/NC
```

**Numeric PIN (8 digits):**

```
$ pwgen -c '[:digit:]' 8
50743836
```

**Lowercase letters and numbers only** (common restriction):

```
$ pwgen -c '[:lower:][:digit:]' -l 10
j27n9o641w
```

**Exclude ambiguous characters** (0/O, 1/l, I) for readability:

```
$ pwgen -e '0O1lI' 16
v'k8p=39('~{cEfL
```

**Exclude special characters that break certain parsers:**

```
$ pwgen -l 16 -e '!@#$%^&*()'
lW?mj";.xO]ZPA5w
```

**Uppercase only** (rare but occasionally required):

```
$ pwgen -c '[:upper:]' 6
FZSAQS
```

## Charsets

Charsets are composed of literal characters, ranges, POSIX classes, and/or bracket expressions.

### POSIX classes

| Expression | Expands to |
|---|---|
| `[:digit:]` | `0123456789` |
| `[:upper:]` | `ABCDEFGHIJKLMNOPQRSTUVWXYZ` |
| `[:lower:]` | `abcdefghijklmnopqrstuvwxyz` |
| `[:alpha:]` | `[:upper:][:lower:]` |
| `[:alnum:]` | `[:alpha:][:digit:]` |
| `[:punct:]` | `` !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~ `` |

Mix and match: `[:lower:][:digit:]_-` gives you lowercase, digits, underscore, and hyphen.

### Character ranges

Hyphenated ranges like `a-z` or `0-9` expand in place at the top level or inside bracket expressions:

```bash
pwgen -c 'a-z0-9' 10         # lowercase + digits
pwgen -c 'A-Fa-f0-9' 16      # hex characters
```

### Bracket expressions

Group characters, ranges, and POSIX classes together with `[...]`:

```bash
pwgen -c '[0-9ab]' 12                # digits plus a and b
pwgen -c '[[:lower:][:digit:]]' 12   # same as [:lower:][:digit:]
pwgen -c '[A-Za-z0-9_]' 12           # identifier-safe chars
```

Unclosed brackets produce a clear error (exit 6).

**Default charset:** `[:alnum:][:punct:]` (all printable ASCII except space).

## Excluding characters

The `-e` / `--exclude` flag removes characters from the final charset. Useful for sites that disallow certain symbols or to avoid ambiguous characters:

```bash
# Avoid shell-sensitive characters
pwgen -e '\$`"' 20

# Classic ambiguous set
pwgen -e '0O1lI' 16
```

Exclusion applies after charset expansion, so `pwgen -c '[:alnum:]' -e '0O1lI'` works as expected.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-l, --length LENGTH` | Generate LENGTH characters (default: 32) |
| `-c, --charset CHARSET` | Define charset (default: `[:alnum:][:punct:]`) |
| `-e, --exclude CHARSET` | Exclude characters from the charset (default: none) |
| `-h, --help` | Display help |

Positional argument: If a single number is provided without flags, it's treated as the length (e.g. `pwgen 16`).

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error (unknown flag, missing value) |
| 5 | Charset is empty after exclusions |
| 6 | Invalid charset (unclosed bracket, unrecognized POSIX class) |

### Dependencies

- `/dev/random` -- entropy source
