#!/bin/bash
# install-bash.test.sh - Tests for install-bash
# shellcheck source-path=SCRIPTDIR disable=SC2329,SC2016

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../install-bash"

# --- shims ---

write_shims() {
    # Default brew prefix for tests (simulates Intel Homebrew). Tests can
    # override BREW_PREFIX before calling run_script to simulate Apple Silicon.
    : "${BREW_PREFIX:=$TEST_DIR/brew-prefix}"
    export BREW_PREFIX
    mkdir -p "$BREW_PREFIX/bin"

    # Fake home directory with .bash_profile
    mkdir -p "$TEST_DIR/home"
    export HOME="$TEST_DIR/home"
    : > "$HOME/.bash_profile"

    # Fake /etc/shells
    mkdir -p "$TEST_DIR/etc"
    printf '/bin/bash\n/bin/zsh\n' > "$TEST_DIR/etc/shells"

    # uname shim: default to Darwin; tests can touch "$TEST_DIR/uname_linux" to flip
    cat > "$SHIM_DIR/uname" <<'SHIM'
#!/bin/bash
if [ -f "$TEST_DIR/uname_linux" ]; then
    printf 'Linux\n'
else
    printf 'Darwin\n'
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/uname"

    # brew shim source: handles `install`, `--prefix`, and `shellenv`.
    # Kept outside SHIM_DIR so that `command -v brew` only finds it when we
    # explicitly symlink it into SHIM_DIR or $BREW_PREFIX/bin (reachable via
    # the `brew shellenv` expansion after install).
    mkdir -p "$TEST_DIR/brew-shim"
    cat > "$TEST_DIR/brew-shim/brew" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/brew.log"
printf 'brew' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
if [ "$1" = "install" ] && [ "$2" = "bash" ]; then
    if [ -f "$TEST_DIR/brew_install_fails" ]; then
        exit 1
    fi
    # After a successful install, wire up brew at the resolved prefix so
    # `"$brew_prefix/bin/brew" shellenv` works later in the script.
    ln -sf "$TEST_DIR/brew-shim/brew" "$BREW_PREFIX/bin/brew"
    exit 0
fi
if [ "$1" = "--prefix" ] && [ $# -eq 1 ]; then
    if [ -f "$TEST_DIR/brew_prefix_empty" ]; then
        exit 0
    fi
    printf '%s\n' "$BREW_PREFIX"
    exit 0
fi
if [ "$1" = "shellenv" ]; then
    # Mimic `brew shellenv` output (real content doesn't matter, just the marker)
    printf 'eval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX"
    exit 0
fi
exit 0
SHIM
    chmod +x "$TEST_DIR/brew-shim/brew"

    # Note: whether brew is considered "already installed" is decided in
    # run_script, based on the `brew_installed` flag that tests set via touch.

    # curl shim: simulates the Homebrew install script download.
    # On success, installs the brew shim at the resolved prefix AND on PATH
    # (via SHIM_DIR) so the script's subsequent `command -v brew` finds it,
    # matching real-world post-install state where Homebrew puts brew at
    # /usr/local/bin (Intel) or /opt/homebrew/bin (Apple Silicon).
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/curl.log"
printf 'curl' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
if [ -f "$TEST_DIR/curl_fails" ]; then
    echo "curl: failed" >&2
    printf 'exit 1\n'
    exit 1
fi
# Side effects of a "successful" install -- mirror what real Homebrew does
mkdir -p "$BREW_PREFIX/bin"
ln -sf "$TEST_DIR/brew-shim/brew" "$BREW_PREFIX/bin/brew"
ln -sf "$TEST_DIR/brew-shim/brew" "$SHIM_DIR/brew"
printf 'echo "Homebrew install script simulated"\n'
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # grep shim: rewrite /etc/shells to the fake file
    cat > "$SHIM_DIR/grep" <<'SHIM'
#!/bin/bash
args=()
for arg in "$@"; do
    if [ "$arg" = "/etc/shells" ]; then
        args+=("$TEST_DIR/etc/shells")
    else
        args+=("$arg")
    fi
done
exec /usr/bin/grep "${args[@]}"
SHIM
    chmod +x "$SHIM_DIR/grep"

    # sudo shim: log the invocation and execute the underlying tee against the
    # fake /etc/shells, so the script's writes land in the test file.
    cat > "$SHIM_DIR/sudo" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/sudo.log"
printf 'sudo' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
if [ -f "$TEST_DIR/sudo_fails" ]; then
    exit 1
fi
if [ "$1" = "tee" ]; then
    shift
    args=()
    for arg in "$@"; do
        if [ "$arg" = "/etc/shells" ]; then
            args+=("$TEST_DIR/etc/shells")
        else
            args+=("$arg")
        fi
    done
    exec tee "${args[@]}"
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/sudo"

    # tee shim: pass through to the real binary
    cat > "$SHIM_DIR/tee" <<'SHIM'
#!/bin/bash
exec /usr/bin/tee "$@"
SHIM
    chmod +x "$SHIM_DIR/tee"

    # chsh shim: record the requested shell
    cat > "$SHIM_DIR/chsh" <<'SHIM'
#!/bin/bash
log="$TEST_DIR/chsh.log"
printf 'chsh' >> "$log"
for a in "$@"; do printf ' %s' "$a" >> "$log"; done
printf '\n' >> "$log"
if [ -f "$TEST_DIR/chsh_fails" ]; then
    exit 1
fi
exit 0
SHIM
    chmod +x "$SHIM_DIR/chsh"
}

# --- helpers ---

get_brew_log() { cat "$TEST_DIR/brew.log" 2>/dev/null; }
get_curl_log() { cat "$TEST_DIR/curl.log" 2>/dev/null; }
get_sudo_log() { cat "$TEST_DIR/sudo.log" 2>/dev/null; }
get_chsh_log() { cat "$TEST_DIR/chsh.log" 2>/dev/null; }
get_shells_file() { cat "$TEST_DIR/etc/shells" 2>/dev/null; }
get_bash_profile() { cat "$TEST_DIR/home/.bash_profile" 2>/dev/null; }

# Expected bash path for assertions (reflects what the script resolves via brew --prefix)
expected_bash_path() { printf '%s/bin/bash' "$BREW_PREFIX"; }

# --- override run_script ---

# The script reads /etc/shells directly. Since shims for grep/sudo handle
# the /etc/shells rewrite, no sed patching is needed.
# PATH is restricted to SHIM_DIR + standard system utility dirs so that a real
# Homebrew install on the test host (e.g. /usr/local/bin/brew or
# /opt/homebrew/bin/brew) isn't picked up by `command -v brew`.
# If the test has set the `brew_installed` flag (via `touch`), wire brew onto
# PATH and into $BREW_PREFIX/bin just before running -- simulating a host
# that already has Homebrew.
run_script() {
    if [ -f "$TEST_DIR/brew_installed" ]; then
        ln -sf "$TEST_DIR/brew-shim/brew" "$SHIM_DIR/brew"
        ln -sf "$TEST_DIR/brew-shim/brew" "$BREW_PREFIX/bin/brew"
    fi
    env TEST_DIR="$TEST_DIR" PATH="$SHIM_DIR:/usr/bin:/bin" HOME="$HOME" \
        SHIM_DIR="$SHIM_DIR" USER="${USER:-tester}" BREW_PREFIX="$BREW_PREFIX" \
        /bin/bash "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
    assert_stdout_contains "help has PRECONDITIONS" "PRECONDITIONS"
    assert_stdout_contains "help mentions macOS only" "macOS only"
    assert_stdout_contains "help mentions sudo" "sudo access"
    assert_stdout_contains "help mentions chsh permanence" "permanently"
    assert_stdout_contains "help has OPTIONS" "OPTIONS"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
}

test_help_short_flag() {
    run_script -h
    assert_rc "h flag exits 0" 0
    assert_stdout_contains "h flag shows help" "NAME"
}

test_non_darwin_rejected() {
    touch "$TEST_DIR/uname_linux"
    run_script
    assert_rc "non-Darwin exits 2" 2
    assert_err_contains "non-Darwin error message" "macOS only"
    assert_err_contains "non-Darwin shows detected OS" "detected: Linux"
}

test_full_install_no_brew() {
    run_script
    assert_rc "full install succeeds" 0
    assert_contains "curl called for homebrew" "$(get_curl_log)" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    assert_contains "brew install bash" "$(get_brew_log)" "install bash"
    assert_contains "brew --prefix called" "$(get_brew_log)" "--prefix"
    assert_contains "shells updated with resolved path" "$(get_shells_file)" "$(expected_bash_path)"
    assert_contains "chsh called with resolved path" "$(get_chsh_log)" "chsh -s $(expected_bash_path)"
    assert_contains "bash_profile updated" "$(get_bash_profile)" "brew shellenv"
}

test_brew_already_installed() {
    touch "$TEST_DIR/brew_installed"
    run_script
    assert_rc "brew installed succeeds" 0
    assert_stdout_contains "skip brew install" "Homebrew (brew) is already installed"
    assert_not_contains "curl not called" "$(get_curl_log)" "https://raw.githubusercontent.com"
}

test_apple_silicon_prefix() {
    # Simulate Apple Silicon by setting BREW_PREFIX to a /opt/homebrew-style path
    export BREW_PREFIX="$TEST_DIR/opt/homebrew"
    mkdir -p "$BREW_PREFIX/bin"
    touch "$TEST_DIR/brew_installed"
    ln -sf "$TEST_DIR/brew-shim/brew" "$SHIM_DIR/brew"
    ln -sf "$TEST_DIR/brew-shim/brew" "$BREW_PREFIX/bin/brew"
    run_script
    assert_rc "apple silicon succeeds" 0
    assert_contains "shells has arm path" "$(get_shells_file)" "$BREW_PREFIX/bin/bash"
    assert_contains "chsh with arm path" "$(get_chsh_log)" "chsh -s $BREW_PREFIX/bin/bash"
    assert_stdout_contains "arm path in output" "$BREW_PREFIX/bin/bash"
}

test_intel_prefix() {
    # Simulate Intel by setting BREW_PREFIX to a /usr/local-style path
    export BREW_PREFIX="$TEST_DIR/usr/local"
    mkdir -p "$BREW_PREFIX/bin"
    touch "$TEST_DIR/brew_installed"
    ln -sf "$TEST_DIR/brew-shim/brew" "$SHIM_DIR/brew"
    ln -sf "$TEST_DIR/brew-shim/brew" "$BREW_PREFIX/bin/brew"
    run_script
    assert_rc "intel succeeds" 0
    assert_contains "shells has intel path" "$(get_shells_file)" "$BREW_PREFIX/bin/bash"
    assert_contains "chsh with intel path" "$(get_chsh_log)" "chsh -s $BREW_PREFIX/bin/bash"
    assert_stdout_contains "intel path in output" "$BREW_PREFIX/bin/bash"
}

test_brew_prefix_empty_fails() {
    touch "$TEST_DIR/brew_installed"
    touch "$TEST_DIR/brew_prefix_empty"
    run_script
    assert_rc "empty prefix fails" 1
    assert_err_contains "prefix error" "Failed to resolve Homebrew prefix"
}

test_homebrew_install_fails() {
    touch "$TEST_DIR/curl_fails"
    run_script
    assert_rc "homebrew install fails" 1
    assert_err_contains "error message" "ERROR: Homebrew installation failed"
}

test_brew_install_bash_fails() {
    touch "$TEST_DIR/brew_installed"
    touch "$TEST_DIR/brew_install_fails"
    run_script
    assert_rc "brew install bash fails" 1
    assert_err_contains "error message" "ERROR: Failed to install Bash via Homebrew"
}

test_shells_already_updated() {
    touch "$TEST_DIR/brew_installed"
    # Pre-add the resolved bash path so the script should skip the sudo step
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    run_script
    assert_rc "shells present succeeds" 0
    assert_stdout_contains "skip shells" "already added to /etc/shells"
    assert_stdout_contains "skip shells msg" "skipping this step"
    assert_not_contains "sudo not called" "$(get_sudo_log)" "sudo"
}

test_sudo_tee_fails() {
    touch "$TEST_DIR/brew_installed"
    touch "$TEST_DIR/sudo_fails"
    run_script
    assert_rc "sudo fails" 1
    assert_err_contains "sudo error" "ERROR: Failed to add"
    assert_err_contains "sudo cmd shown" "sudo tee -a"
}

test_chsh_fails() {
    touch "$TEST_DIR/brew_installed"
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    touch "$TEST_DIR/chsh_fails"
    run_script
    assert_rc "chsh fails" 1
    assert_err_contains "chsh error" "ERROR: Failed to change user's shell"
}

test_bash_profile_append() {
    touch "$TEST_DIR/brew_installed"
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    printf '# existing content\n' > "$TEST_DIR/home/.bash_profile"
    run_script
    assert_rc "append succeeds" 0
    assert_contains "old content preserved" "$(get_bash_profile)" "# existing content"
    assert_contains "shellenv added" "$(get_bash_profile)" "brew shellenv"
    assert_stdout_contains "message shown" "Added Homebrew environment setup to ~/.bash_profile"
}

test_bash_profile_already_present() {
    touch "$TEST_DIR/brew_installed"
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    printf 'eval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" > "$TEST_DIR/home/.bash_profile"
    run_script
    assert_rc "already present succeeds" 0
    assert_stdout_contains "skip shellenv" "Homebrew environment setup"
    assert_stdout_contains "skip shellenv msg" "already present in ~/.bash_profile"
}

test_bash_profile_append_fails() {
    touch "$TEST_DIR/brew_installed"
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    chmod 000 "$TEST_DIR/home/.bash_profile"
    run_script
    assert_rc "append fails" 1
    assert_err_contains "append error" "ERROR: Failed to add"
    assert_err_contains "shellenv mentioned" "brew shellenv"
    chmod 644 "$TEST_DIR/home/.bash_profile"
}

test_all_steps_skipped() {
    touch "$TEST_DIR/brew_installed"
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    printf 'eval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" > "$TEST_DIR/home/.bash_profile"
    run_script
    assert_rc "all skipped succeeds" 0
    assert_stdout_contains "brew skip" "already installed"
    assert_stdout_contains "shells skip" "already added to /etc/shells"
    assert_stdout_contains "shellenv skip" "already present in ~/.bash_profile"
}

test_sourcing_returns_correctly() {
    touch "$TEST_DIR/brew_installed"
    printf '/bin/bash\n%s\n' "$(expected_bash_path)" > "$TEST_DIR/etc/shells"
    printf 'eval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" > "$TEST_DIR/home/.bash_profile"

    cat > "$TEST_DIR/test_source.sh" <<'SRC'
#!/bin/bash
source "$UNDER_TEST" --help
exit $?
SRC
    chmod +x "$TEST_DIR/test_source.sh"

    env TEST_DIR="$TEST_DIR" UNDER_TEST="$UNDER_TEST" PATH="$SHIM_DIR:/usr/bin:/bin" \
        HOME="$TEST_DIR/home" BREW_PREFIX="$BREW_PREFIX" \
        /bin/bash "$TEST_DIR/test_source.sh" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"

    assert_rc "source returns 0" 0
}

# --- run ---

run_tests "$@"
