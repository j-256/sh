# pwa-prereqs

[View script](../pwa-prereqs)

Check or install the prerequisites for Salesforce PWA Kit development on macOS. PWA Kit is the React-based storefront framework for Salesforce Commerce Cloud (SFCC). It needs Node.js + npm, which in turn need nvm + Homebrew + Xcode Command Line Tools.

Default mode is a read-only check that reports whether Xcode CLT, Homebrew, nvm, and an LTS Node are installed. Add `--install` to actually install anything that's missing.

## Quick start

Check what's already installed:

```
$ pwa-prereqs
[ok]      Xcode Command Line Tools
[ok]      Homebrew
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
--- START brew ---
Homebrew is already installed.
--- FINISH brew ---
--- START nvm ---
Installing nvm...
nvm installed successfully.
--- FINISH nvm ---
--- START node/npm ---
Installing latest Long-Term Support (LTS) Node.js...
Now using node v24.15.0 (npm v11.12.1)
Node.js installed successfully.
--- FINISH node/npm ---
```

After `--install` completes, the new tools won't be on `PATH` in your current shell. The Homebrew and nvm installers append setup snippets to your shell's rc files, which only take effect in new sessions -- open a new terminal tab to use `brew`, `nvm`, and `node`.

## What it checks/installs

In order:

1. **Xcode Command Line Tools** — Apple's compiler/toolchain bundle (ships `git`, `clang`, etc.). Homebrew's installer refuses to run without it.
2. **Homebrew** — macOS package manager (`brew` command)
3. **nvm** — Node Version Manager (`nvm` command or sourceable `~/.nvm/nvm.sh`)
4. **Node.js LTS** — latest Long-Term Support version via `nvm install --lts`

Each step in install mode is bracketed with `--- START <tool> ---` and `--- FINISH <tool> ---` headers.

## Xcode Command Line Tools install flow

If `--install` finds Xcode CLT missing, the script calls `xcode-select --install`. That triggers Apple's GUI installer dialog ("A software update is available for your computer"). The script then exits with code 1 and prints a hint to re-run `pwa-prereqs --install` once you've completed the dialog.

This is a quirk of `xcode-select --install` — it's inherently interactive and returns immediately while the install continues asynchronously. There's no reliable way to block on it from a shell script. The two-phase flow (trigger installer → exit → user completes → re-run) is the simplest correct shape.

## Error handling

In install mode, the script exits immediately if any installation fails. If nvm is partially installed (directory exists but command not found), the script attempts to source `~/.nvm/nvm.sh` first. If that fails, it reinstalls nvm.

After installing nvm, the script sources it into the current session so that the Node.js installation can proceed immediately.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `--install` | Install missing components (default is check-only) |
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All prerequisites present (check) or installed (install) |
| `1` | Missing prerequisites (check) or installation failed (install) |
| `2` | Usage / argument error |

### Dependencies

- `uname` (for the macOS platform check)
- `xcode-select` (preinstalled on macOS; used to detect and trigger Xcode CLT installation)
- `curl` (for `--install`, used to download Homebrew and nvm installers)

### Caveats

- **macOS only.** The Homebrew and Xcode installers are macOS-native; the script refuses to run on other platforms.
- `--install` may prompt for `sudo` during Homebrew installation.
- When Xcode CLT is missing, `--install` triggers Apple's GUI installer and exits. Re-run the command after the dialog completes.
