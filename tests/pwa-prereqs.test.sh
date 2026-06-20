#!/bin/bash
# pwa-prereqs.test.sh - Tests for pwa-prereqs
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../pwa-prereqs"

# --- shims ---

write_shims() {
    # uname shim: default to Darwin (macOS). Tests can override by touching
    # "$TEST_DIR/uname_linux" to simulate a non-Darwin platform
    cat > "$SHIM_DIR/uname" <<'SHIM'
#!/bin/bash
[ -f "$TEST_DIR/uname_linux" ] && { echo "Linux"; exit 0; }
echo "Darwin"
SHIM
    chmod +x "$SHIM_DIR/uname"

    # xcode-select shim: default "present". Tests opt into "missing" by
    # touching "$TEST_DIR/xcode_missing"; "$TEST_DIR/xcode_install_called"
    # records when --install is invoked
    cat > "$SHIM_DIR/xcode-select" <<'SHIM'
#!/bin/bash
case "$1" in
    -p)
        if [ -f "$TEST_DIR/xcode_missing" ]; then
            echo "xcode-select: error: unable to get active developer directory" >&2
            exit 2
        fi
        echo "/Library/Developer/CommandLineTools"
        exit 0
        ;;
    --install)
        printf 'xcode-select --install\n' >> "$TEST_DIR/xcode_install_called"
        # The real thing pops a GUI dialog. Simulate either success or the
        # already-installed case depending on a flag
        [ -f "$TEST_DIR/xcode_install_fails" ] && { echo "xcode-select: error: command line tools are already installed" >&2; exit 1; }
        exit 0
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/xcode-select"

    # curl shim: log args, simulate download output (used in --install mode)
    cat > "$SHIM_DIR/curl" <<'SHIM'
#!/bin/bash
printf 'curl' >> "$TEST_DIR/curl.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/curl.log"; done
printf '\n' >> "$TEST_DIR/curl.log"
[ -f "$TEST_DIR/curl_fails" ] && exit 1
case "$*" in
    *Homebrew*)
        cat <<'BREWINSTALLER'
#!/bin/bash
[ -f "$TEST_DIR/brew_install_fails" ] && exit 1
printf "homebrew-installer\n" >> "$TEST_DIR/brew_install.log"
exit 0
BREWINSTALLER
        ;;
    *nvm*)
        cat <<'NVMINSTALLER'
#!/bin/bash
[ -f "$TEST_DIR/nvm_install_fails" ] && exit 1
printf "nvm-installer\n" >> "$TEST_DIR/nvm_install.log"
mkdir -p "$HOME/.nvm"
cat > "$HOME/.nvm/nvm.sh" <<'NVMSHSCRIPT'
nvm() {
    printf 'nvm %s\n' "$*" >> "$TEST_DIR/nvm.log"
    [ "$1" = "install" ] && [ "$2" = "--lts" ] && exit 0
    exit 0
}
NVMSHSCRIPT
exit 0
NVMINSTALLER
        ;;
    *)
        echo 'echo "CURL_SUCCESS"'
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/curl"

    # Set HOME to test directory for nvm sourcing tests
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"
}

# Override run_script to use isolated PATH (only shims, no system PATH)
run_script() {
    # We need bash in PATH for the script to work
    local bash_path
    bash_path="$(command -v bash)"
    env TEST_DIR="$TEST_DIR" SHIM_DIR="$SHIM_DIR" HOME="$HOME" \
        PATH="$SHIM_DIR:/usr/bin:/bin" \
        "$bash_path" "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Helper functions to create shims when needed
create_brew_shim() {
    cat > "$SHIM_DIR/brew" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    chmod +x "$SHIM_DIR/brew"
}

create_nvm_shim() {
    cat > "$SHIM_DIR/nvm" <<SHIM
#!/bin/bash
printf 'nvm' >> "$TEST_DIR/nvm.log"
for a in "\$@"; do printf ' %s' "\$a" >> "$TEST_DIR/nvm.log"; done
printf '\n' >> "$TEST_DIR/nvm.log"
case "\$1" in
    install)
        if [ "\$2" = "--lts" ]; then
            [ -f "$TEST_DIR/nvm_install_fails" ] && exit 1
            exit 0
        fi
        ;;
    ls)
        # Report an LTS node is installed so Node-LTS check reports [ok]
        echo "v18.20.0 (lts/hydrogen)"
        ;;
esac
exit 0
SHIM
    chmod +x "$SHIM_DIR/nvm"
}

create_node_shim() {
    cat > "$SHIM_DIR/node" <<'SHIM'
#!/bin/bash
echo "v18.20.0"
SHIM
    chmod +x "$SHIM_DIR/node"
}

# --- helpers ---

get_curl_log() { cat "$TEST_DIR/curl.log" 2>/dev/null; }
get_brew_log() { cat "$TEST_DIR/brew_install.log" 2>/dev/null; }
get_nvm_installer_log() { cat "$TEST_DIR/nvm_install.log" 2>/dev/null; }
get_nvm_log() { cat "$TEST_DIR/nvm.log" 2>/dev/null; }
get_xcode_install_log() { cat "$TEST_DIR/xcode_install_called" 2>/dev/null; }

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has pwa-prereqs" "pwa-prereqs"
    assert_stdout_contains "help has DEPENDENCIES" "DEPENDENCIES"
    assert_stdout_contains "help mentions curl" "curl"
    assert_stdout_contains "help mentions --install" "--install"
    assert_stdout_contains "help mentions Xcode CLT" "Xcode"
    assert_stdout_contains "help mentions macOS only" "macOS only"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "short flag has NAME" "NAME"
}

# --- check-only (default) mode ---

test_check_only_default_all_present() {
    create_brew_shim
    create_nvm_shim
    create_node_shim
    run_script
    assert_rc "all present exits 0" 0
    assert_stdout_contains "xcode ok" "[ok]      Xcode Command Line Tools"
    assert_stdout_contains "brew ok" "[ok]      Homebrew"
    assert_stdout_contains "nvm ok" "[ok]      nvm"
    assert_stdout_contains "node ok" "[ok]      Node LTS"
    # Check-only mode must not run the installer
    assert_not_contains "no install logs" "$(get_curl_log)" "Homebrew"
    assert_not_contains "no nvm install" "$(get_nvm_log)" "install --lts"
    assert_eq "xcode-select --install not called" "$(get_xcode_install_log)" ""
}

test_check_only_default_all_missing() {
    # No brew/nvm/node shims created; simulate missing Xcode CLT
    touch "$TEST_DIR/xcode_missing"
    run_script
    assert_rc "all missing exits 1" 1
    assert_stdout_contains "xcode missing" "[missing] Xcode Command Line Tools"
    assert_stdout_contains "brew missing" "[missing] Homebrew"
    assert_stdout_contains "nvm missing" "[missing] nvm"
    assert_stdout_contains "node missing" "[missing] Node LTS"
}

test_check_only_xcode_missing_others_present() {
    touch "$TEST_DIR/xcode_missing"
    create_brew_shim
    create_nvm_shim
    create_node_shim
    run_script
    assert_rc "xcode missing exits 1" 1
    assert_stdout_contains "xcode missing" "[missing] Xcode Command Line Tools"
    assert_stdout_contains "brew ok" "[ok]      Homebrew"
}

test_check_only_partial() {
    create_brew_shim
    # nvm and node not shimmed
    run_script
    assert_rc "partial exits 1" 1
    assert_stdout_contains "xcode ok" "[ok]      Xcode Command Line Tools"
    assert_stdout_contains "brew ok" "[ok]      Homebrew"
    assert_stdout_contains "nvm missing" "[missing] nvm"
    assert_stdout_contains "node missing" "[missing] Node LTS"
}

test_check_does_not_install() {
    # No shims: check mode must not touch curl or attempt installs
    run_script
    assert_rc "check-only missing exits 1" 1
    local curl_log
    curl_log="$(get_curl_log)"
    assert_eq "curl not called" "$curl_log" ""
    assert_eq "xcode-select --install not called" "$(get_xcode_install_log)" ""
}

# --- --install mode ---

test_install_xcode_missing_triggers_installer_and_exits() {
    touch "$TEST_DIR/xcode_missing"
    run_script --install
    assert_rc "missing Xcode CLT exits 1" 1
    assert_stdout_contains "xcode installing" "Installing Xcode Command Line Tools"
    assert_stdout_contains "gui hint" "GUI installer"
    assert_stdout_contains "rerun hint" "re-run"
    assert_contains "xcode-select --install called" "$(get_xcode_install_log)" "xcode-select --install"
    # Must not proceed to brew/nvm install steps
    assert_stdout_not_contains "no brew section" "--- START brew ---"
}

test_install_xcode_present_proceeds() {
    create_brew_shim
    create_nvm_shim
    run_script --install
    assert_rc "xcode present: install succeeds" 0
    assert_stdout_contains "xcode already" "Xcode Command Line Tools already installed"
    assert_stdout_contains "brew section" "--- START brew ---"
    assert_eq "xcode-select --install not called" "$(get_xcode_install_log)" ""
}

test_install_all_already_installed() {
    create_brew_shim
    create_nvm_shim
    run_script --install
    assert_rc "install: all present exits 0" 0
    assert_stdout_contains "brew already" "Homebrew is already installed"
    assert_stdout_contains "nvm already" "nvm is already installed"
    assert_not_contains "no brew install" "$(get_brew_log)" "homebrew-installer"
    assert_contains "nvm install called" "$(get_nvm_log)" "nvm install --lts"
}

test_install_brew_needs_install() {
    create_nvm_shim
    run_script --install
    assert_rc "brew install succeeds" 0
    assert_stdout_contains "installing brew" "Installing Homebrew"
    assert_stdout_contains "brew success" "Homebrew installed successfully"
    assert_contains "brew installer called" "$(get_brew_log)" "homebrew-installer"
}

test_install_brew_install_fails() {
    create_nvm_shim
    touch "$TEST_DIR/brew_install_fails"
    run_script --install
    assert_rc "brew fail exits 1" 1
    assert_stderr_contains "brew fail msg" "Homebrew installation failed"
}

test_install_nvm_needs_install_success() {
    create_brew_shim
    run_script --install
    assert_rc "nvm install succeeds" 0
    assert_stdout_contains "nvm installing" "nvm installed successfully"
    assert_contains "curl downloads nvm" "$(get_curl_log)" "nvm-sh/nvm"
    assert_contains "nvm installer ran" "$(get_nvm_installer_log)" "nvm-installer"
}

test_install_nvm_needs_install_fails() {
    create_brew_shim
    touch "$TEST_DIR/nvm_install_fails"
    run_script --install
    assert_rc "nvm install fail exits 1" 1
    assert_stderr_contains "nvm fail msg" "nvm installation failed"
}

test_install_nvm_dir_exists_but_no_command() {
    create_brew_shim
    mkdir -p "$HOME/.nvm"
    cat > "$HOME/.nvm/nvm.sh" <<NVMSH
#!/bin/bash
# Fake nvm.sh that creates the nvm command
nvm() {
    printf 'nvm %s\n' "\$*" >> "$TEST_DIR/nvm.log"
    [ "\$1" = "install" ] && [ "\$2" = "--lts" ] && exit 0
    exit 0
}
NVMSH
    run_script --install
    assert_rc "nvm source succeeds" 0
    assert_stdout_contains "nvm sourced" "nvm sourced successfully"
    assert_contains "nvm install called" "$(get_nvm_log)" "nvm install --lts"
}

test_install_nvm_dir_exists_no_script() {
    create_brew_shim
    mkdir -p "$HOME/.nvm"
    run_script --install
    assert_rc "nvm reinstall happens but node install fails" 1
    assert_stdout_contains "reinstalling" "Reinstalling nvm"
    assert_stderr_contains "node install fails" "Node.js installation failed"
    assert_contains "curl downloads nvm" "$(get_curl_log)" "nvm-sh/nvm"
    assert_contains "nvm installer ran" "$(get_nvm_installer_log)" "nvm-installer"
}

test_install_nvm_dir_exists_reinstall_fails() {
    create_brew_shim
    touch "$TEST_DIR/nvm_install_fails"
    mkdir -p "$HOME/.nvm"
    run_script --install
    assert_rc "nvm reinstall fail exits 1" 1
    assert_stderr_contains "reinstall fail msg" "nvm reinstallation failed"
}

test_install_nvm_fresh_install_no_script_after() {
    create_brew_shim
    # Create a custom curl that succeeds but doesn't create nvm.sh
    cat > "$SHIM_DIR/curl" <<'CURLSHIM'
#!/bin/bash
printf 'curl' >> "$TEST_DIR/curl.log"
for a in "$@"; do printf ' %s' "$a" >> "$TEST_DIR/curl.log"; done
printf '\n' >> "$TEST_DIR/curl.log"
case "$*" in
    *nvm*)
        cat <<'NVMINSTALLER'
#!/bin/bash
printf "nvm-installer\n" >> "$TEST_DIR/nvm_install.log"
mkdir -p "$HOME/.nvm"
exit 0
NVMINSTALLER
        ;;
esac
CURLSHIM
    chmod +x "$SHIM_DIR/curl"
    run_script --install
    assert_rc "nvm script check fails exits 1" 1
    assert_stderr_contains "script not found" "nvm script not found"
}

test_install_node_install_success() {
    create_brew_shim
    create_nvm_shim
    run_script --install
    assert_rc "node install succeeds" 0
    assert_stdout_contains "node installing" "Installing latest Long-Term Support (LTS) Node.js"
    assert_stdout_contains "node success" "Node.js installed successfully"
    assert_contains "nvm install lts" "$(get_nvm_log)" "nvm install --lts"
}

test_install_node_install_fails() {
    create_brew_shim
    create_nvm_shim
    touch "$TEST_DIR/nvm_install_fails"
    run_script --install
    assert_rc "node install fail exits 1" 1
    assert_stderr_contains "node fail msg" "Node.js installation failed"
}

test_install_section_markers() {
    create_brew_shim
    create_nvm_shim
    run_script --install
    assert_rc "markers present" 0
    assert_stdout_contains "xcode start" "--- START xcode ---"
    assert_stdout_contains "xcode finish" "--- FINISH xcode ---"
    assert_stdout_contains "brew start" "--- START brew ---"
    assert_stdout_contains "brew finish" "--- FINISH brew ---"
    assert_stdout_contains "nvm start" "--- START nvm ---"
    assert_stdout_contains "nvm finish" "--- FINISH nvm ---"
    assert_stdout_contains "node start" "--- START node/npm ---"
    assert_stdout_contains "node finish" "--- FINISH node/npm ---"
}

test_install_curl_gets_correct_flags() {
    create_brew_shim
    run_script --install
    assert_rc "curl flags" 0
    assert_contains "curl uses -o-" "$(get_curl_log)" "-o-"
    assert_contains "curl includes url" "$(get_curl_log)" "https://raw.githubusercontent.com/nvm-sh/nvm"
}

# --- platform check ---

test_non_darwin_platform_rejected() {
    touch "$TEST_DIR/uname_linux"
    run_script
    assert_rc "non-Darwin exits 1" 1
    assert_stderr_contains "macOS only message" "macOS only"
    assert_stderr_contains "platform mentioned" "Linux"
}

test_non_darwin_platform_rejected_install() {
    touch "$TEST_DIR/uname_linux"
    run_script --install
    assert_rc "non-Darwin --install exits 1" 1
    assert_stderr_contains "macOS only message" "macOS only"
}

# --- arg validation ---

test_unknown_option() {
    run_script --bogus
    assert_rc "unknown option exits 2" 2
    assert_stderr_contains "unknown error" "Unknown argument"
}

test_unexpected_positional() {
    run_script somearg
    assert_rc "positional exits 2" 2
    assert_stderr_contains "unexpected error" "Unknown argument"
}

# --- run ---

run_tests "$@"
