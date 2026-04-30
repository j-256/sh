# install-bash

Install the latest Bash from Homebrew and set it as your login shell.

macOS ships with Bash 3.2 from 2007, frozen in time because Apple can't include GPLv3 software in the base system. That means no modern array handling, no parameter transformations like `${var,,}`, no associative arrays -- none of the features that arrived in Bash 4 and beyond. If you need to run modern shell scripts (or just want better tab completion and readline behavior), you need a newer Bash.

This script does all the setup in one command: installs Homebrew if you don't have it, installs bash from brew, registers it as a valid shell in `/etc/shells`, and switches your account to use it. Every step checks if it's already done and skips itself accordingly, so it's safe to run multiple times. **macOS only** -- the script exits with an error on other platforms.

## Quick start

```bash
$ install-bash
[install-bash] Homebrew (brew) is already installed, skipping this step
[install-bash] Installed Bash via Homebrew (`brew install bash`)
[install-bash] Added "/usr/local/bin/bash" to /etc/shells
Password:
[install-bash] Shell for youruser set to /usr/local/bin/bash
[install-bash] Added Homebrew environment setup to ~/.bash_profile (`brew shellenv`)
```

When prompted for your password, that's `sudo` asking permission to modify `/etc/shells` (the system-level list of allowed shells). The `chsh` step at the end also prompts for your password but uses macOS authentication directly (not sudo).

After the script completes, restart Terminal or open a new tab to start using the new shell. You can verify which bash is running with:

```bash
$ echo $BASH_VERSION
5.2.37(1)-release
```

## What it does step by step

Each step is skipped if already complete:

1. **Install Homebrew** -- Downloads and runs the official Homebrew installer from `https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`. Skipped if `brew` is already available.

2. **Install bash** -- Runs `brew install bash`. The install path depends on your Homebrew prefix: `/usr/local/bin/bash` on Intel Macs, `/opt/homebrew/bin/bash` on Apple Silicon. The script resolves this dynamically via `brew --prefix` so every subsequent step targets the bash you just installed, regardless of architecture.

3. **Register the new shell** -- Adds the resolved bash path to `/etc/shells` (requires `sudo`). macOS won't let you use a shell via `chsh` unless it's in this file.

4. **Switch your account** -- Runs `chsh -s <resolved-path>` to set the new shell as your login shell. This prompts for your password.

5. **Configure environment** -- Appends `brew shellenv` output to `~/.bash_profile` so Homebrew's paths are set up automatically in new shells. Skipped if already present.

## Reverting

To switch back to the system Bash:

```bash
$ chsh -s /bin/bash
```

The Homebrew bash and `/etc/shells` entry stay in place, but your account will use the old shell for new sessions. If you want to remove Homebrew bash entirely:

```bash
$ brew uninstall bash
```

You'll need to manually remove the Homebrew bash line from `/etc/shells` if you want a fully clean revert. The exact path depends on your architecture: `/usr/local/bin/bash` on Intel, `/opt/homebrew/bin/bash` on Apple Silicon. Check with `brew --prefix` then edit `/etc/shells` via `sudo vi /etc/shells` or `sudo nano /etc/shells`.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `-h, --help` | Show help message |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Not running on macOS, Homebrew installation failed, `brew --prefix` returned empty, bash install failed, `/etc/shells` update failed, `chsh` failed, or `~/.bash_profile` update failed |

### Dependencies

- `curl` (for Homebrew installer download)
- `sudo` (for `/etc/shells` modification)
- `chsh` (system command for changing login shell)
- `uname` (for macOS detection)
