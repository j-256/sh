# pwa-prereqs

[View script](../pwa-prereqs)

Check or install the prerequisites for Salesforce PWA Kit development on macOS. PWA Kit is the React-based storefront framework for Salesforce Commerce Cloud (SFCC). It needs Node.js + npm, which come from nvm, whose installer in turn needs the Xcode Command Line Tools on a Mac.

Default mode is a read-only check that reports whether Xcode CLT, nvm, and an LTS Node are installed. Add `--install` to actually install anything that's missing.

The install step also wires the `nvm` setup lines into your shell startup file so node survives closing the terminal. This is the part people usually get wrong by hand: nvm's installer only edits a startup file that already exists, so on a fresh Mac node works in the install window but is gone in the next one. `pwa-prereqs` writes the lines itself, idempotently, creating the startup file if it doesn't exist.

## Quick start

Check what's already installed:

```
$ pwa-prereqs
[ok]      Xcode Command Line Tools
[missing] nvm
[missing] Node LTS
```

Exits 0 if everything is present, 1 if any component is missing.

Install the missing pieces:

```
$ pwa-prereqs --install
--- START xcode ---
Xcode Command Line Tools already installed.
--- FINISH xcode ---
--- START nvm ---
Installing nvm...
nvm installed successfully.
--- FINISH nvm ---
--- START node/npm ---
Installing latest Long-Term Support (LTS) Node.js...
Now using node v24.15.0 (npm v11.12.1)
Node.js installed successfully.
--- FINISH node/npm ---
--- START shell-startup ---
Wiring shell startup: /Users/you/.zshrc
  nvm wired into /Users/you/.zshrc
--- FINISH shell-startup ---

All set. node and npm are ready in NEW terminal windows.
To use them in THIS window right now, reload your shell:
    exec "$SHELL" -l
or just close this terminal and open a new one.
```

Newly installed tools aren't on `PATH` in the shell that ran the install -- a program can't change its parent shell's environment. Once the startup file is wired (which `--install` does for you), any **new** terminal has `nvm` and `node` ready. To use them in the **current** window without opening a new one, run `exec "$SHELL" -l` to reload the shell in place.

## What it checks/installs

In order:

1. **Xcode Command Line Tools** – Apple's compiler/toolchain bundle (ships `git`, `clang`, etc.). nvm's installer refuses to run on a Mac without it, and native npm modules (node-gyp) need it to compile.
2. **nvm** – Node Version Manager (detected by a sourceable `~/.nvm/nvm.sh`)
3. **Node.js LTS** – latest Long-Term Support version via `nvm install --lts`

Each step in install mode is bracketed with `--- START <tool> ---` and `--- FINISH <tool> ---` headers.

Homebrew is deliberately **not** installed. It's a common way to get nvm (`brew install nvm`), but this script uses nvm's official `curl | bash` installer, which needs only curl (always present on macOS) and git-via-CLT. Nothing in the PWA Kit path (nvm → node → npm) consumes Homebrew, so installing it would add an unused component, an extra `sudo` prompt, and another thing that can fail before you reach node.

## Xcode Command Line Tools install flow

If `--install` finds Xcode CLT missing, the script calls `xcode-select --install`. That triggers Apple's GUI installer dialog ("A software update is available for your computer"). The script then exits with code 1 and prints a hint to re-run `pwa-prereqs --install` once you've completed the dialog.

This is a quirk of `xcode-select --install` – it's inherently interactive and returns immediately while the install continues asynchronously. There's no reliable way to block on it from a shell script. The two-phase flow (trigger installer → exit → user completes → re-run) is the simplest correct shape.

## Shell startup wiring

For `nvm` and `node` to work in future terminals, nvm's setup lines have to live in a shell startup file that new sessions read. `--install` writes the standard three-line `nvm` block for you (`export NVM_DIR=...` plus the two `nvm.sh` / `bash_completion` source lines).

Writes are idempotent: the block is guarded by a fixed-string match, so re-running `--install` never duplicates entries. If the target file doesn't exist, it's created. The wiring runs even when nothing needed installing, so a re-run repairs a startup file that's missing the lines.

Wiring is on by default for `--install`. To install nvm without touching any startup file, pass `--shell none` (see below) – the script prints the lines for you to add yourself instead.

### Which file gets written

`--shell` chooses the target. The default, `auto`, reads `$SHELL`:

| `--shell` | Target file | Notes |
|---|---|---|
| `auto` (default) | depends on `$SHELL` | zsh → `~/.zshrc`, bash → `~/.bash_profile`, anything else → `~/.profile` |
| `zsh` | `~/.zshrc` | read by every interactive zsh, login or not |
| `bash` | `~/.bash_profile` | the file a macOS login shell (what Terminal.app opens) reads |
| `both` | `~/.bash_profile` and `~/.zshrc` | wire up both, so the tools work whichever shell launches |
| `none` | *(nothing)* | touch no files; print the lines instead, for people who manage their own dotfiles |

`both` is the safe choice if you're not sure which shell you use, or if you switch between them. `none` is the opt-out: the script installs the tools but leaves every startup file alone, printing the exact lines it would have added so you can place them yourself. With `none`, nvm's own installer is also opted out (via `PROFILE=/dev/null`), so nothing writes to your shell config behind your back.

## How nvm is detected

`nvm` isn't a program on your `PATH` – it's a shell function that `~/.nvm/nvm.sh` defines when your shell starts. Shell functions aren't inherited by child processes, so a script like this one (run as `curl ... | bash` or `./pwa-prereqs`) can never see `nvm` via `command -v`. Checking for it that way would always report "missing" even on a machine where nvm works fine.

So the script uses the real signal: a sourceable `~/.nvm/nvm.sh`. If that file exists, nvm is installed; otherwise it's installed fresh. Either way the script then sources `~/.nvm/nvm.sh` into its own process so `nvm install --lts` can run immediately, and verifies the `nvm` function actually appeared before continuing.

## Error handling

In install mode, the script exits immediately if any step fails: a failed nvm download, an `~/.nvm/nvm.sh` that's still missing after the nvm installer ran, or an `nvm.sh` that sources without defining the `nvm` function.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-i, --install` | Install missing components (default is check-only) |
| `-s, --shell <which>` | Shell startup file(s) to wire up: `auto` (default), `bash`, `zsh`, `both`, or `none` |
| `-h, --help` | Show help message |

### Environment variables

| Variable | Effect |
|---|---|
| `SHELL` | Consulted by `--shell auto` to pick the target startup file. Overridden by an explicit `--shell bash\|zsh\|both\|none` |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All prerequisites present (check) or installed (install) |
| `1` | Missing prerequisites (check) or installation failed (install) |
| `2` | Usage / argument error |

### Dependencies

- `uname` (for the macOS platform check)
- `xcode-select` (preinstalled on macOS; used to detect and trigger Xcode CLT installation)
- `curl` (for `--install`, used to download the nvm installer)

### Caveats

- **macOS only.** The Xcode CLT install flow is macOS-native; the script refuses to run on other platforms.
- When Xcode CLT is missing, `--install` triggers Apple's GUI installer and exits. Re-run the command after the dialog completes.
- Newly installed tools aren't available in the shell that ran `--install`; open a new terminal or run `exec "$SHELL" -l` to pick them up.
