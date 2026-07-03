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
    *nvm*)
        cat <<'NVMINSTALLER'
#!/bin/bash
[ -f "$TEST_DIR/nvm_install_fails" ] && exit 1
printf "nvm-installer\n" >> "$TEST_DIR/nvm_install.log"
# Record the PROFILE the script handed us. The real nvm installer reads $PROFILE
# to pick which startup file to append to; it must be set on the piped `bash`,
# so recording it here proves the script placed the prefix on the correct side
printf '%s\n' "$PROFILE" > "$TEST_DIR/nvm_profile.seen"
mkdir -p "$HOME/.nvm"
cat > "$HOME/.nvm/nvm.sh" <<'NVMSHSCRIPT'
nvm() {
    printf 'nvm %s\n' "$*" >> "$TEST_DIR/nvm.log"
    return 0
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

# Same as run_script but pins $SHELL so `--shell auto` detection is hermetic.
# $1 = the SHELL value (e.g. /bin/zsh); remaining args pass through to the script
run_script_shell() {
    local shell_val="$1"; shift
    local bash_path
    bash_path="$(command -v bash)"
    env TEST_DIR="$TEST_DIR" SHIM_DIR="$SHIM_DIR" HOME="$HOME" SHELL="$shell_val" \
        PATH="$SHIM_DIR:/usr/bin:/bin" \
        "$bash_path" "$UNDER_TEST" "$@" >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"
    printf '%s\n' "$?" > "$TEST_DIR/rc"
}

# Model nvm the way it really installs: a sourceable ~/.nvm/nvm.sh that DEFINES
# an `nvm` shell function. nvm is never a PATH binary, and its function isn't
# inherited by the script's child process -- so the script detects nvm by the
# presence of nvm.sh and sources it. The function uses `return` (not `exit`)
# because it runs sourced; an `exit` would kill the script's subshell mid-run
create_nvm_shim() {
    mkdir -p "$HOME/.nvm"
    cat > "$HOME/.nvm/nvm.sh" <<SHIM
nvm() {
    printf 'nvm' >> "$TEST_DIR/nvm.log"
    for a in "\$@"; do printf ' %s' "\$a" >> "$TEST_DIR/nvm.log"; done
    printf '\n' >> "$TEST_DIR/nvm.log"
    case "\$1" in
        install)
            if [ "\$2" = "--lts" ]; then
                [ -f "$TEST_DIR/nvm_install_fails" ] && return 1
                return 0
            fi
            ;;
        ls)
            # Report an LTS node is installed so Node-LTS check reports [ok]
            echo "v18.20.0 (lts/hydrogen)"
            ;;
    esac
    return 0
}
SHIM
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
get_nvm_installer_log() { cat "$TEST_DIR/nvm_install.log" 2>/dev/null; }
get_nvm_log() { cat "$TEST_DIR/nvm.log" 2>/dev/null; }
get_xcode_install_log() { cat "$TEST_DIR/xcode_install_called" 2>/dev/null; }
get_nvm_profile_seen() { cat "$TEST_DIR/nvm_profile.seen" 2>/dev/null; }

# rc-file accessors (files the script wires up under the test HOME)
get_bashrc()  { cat "$HOME/.bash_profile" 2>/dev/null; }
get_zshrc()   { cat "$HOME/.zshrc" 2>/dev/null; }
get_profile() { cat "$HOME/.profile" 2>/dev/null; }
# Count how many times a fixed string appears across a file (for dedup checks)
count_in_file() { grep -cF "$2" "$1" 2>/dev/null || echo 0; }

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
    assert_stdout_contains "help mentions --shell" "--shell"
    assert_stdout_contains "help mentions shell choices" "auto"
    assert_stdout_contains "help documents SHELL env" "SHELL"
}

test_help_short_flag() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "short flag has NAME" "NAME"
}

# --- check-only (default) mode ---

test_check_only_default_all_present() {
    create_nvm_shim
    create_node_shim
    run_script
    assert_rc "all present exits 0" 0
    assert_stdout_contains "xcode ok" "[ok]      Xcode Command Line Tools"
    assert_stdout_contains "nvm ok" "[ok]      nvm"
    assert_stdout_contains "node ok" "[ok]      Node LTS"
    # Check-only mode must not run the installer
    assert_not_contains "no nvm install" "$(get_nvm_log)" "install --lts"
    assert_eq "xcode-select --install not called" "$(get_xcode_install_log)" ""
}

test_check_only_default_all_missing() {
    # No nvm/node shims created; simulate missing Xcode CLT
    touch "$TEST_DIR/xcode_missing"
    run_script
    assert_rc "all missing exits 1" 1
    assert_stdout_contains "xcode missing" "[missing] Xcode Command Line Tools"
    assert_stdout_contains "nvm missing" "[missing] nvm"
    assert_stdout_contains "node missing" "[missing] Node LTS"
}

test_check_only_xcode_missing_others_present() {
    touch "$TEST_DIR/xcode_missing"
    create_nvm_shim
    create_node_shim
    run_script
    assert_rc "xcode missing exits 1" 1
    assert_stdout_contains "xcode missing" "[missing] Xcode Command Line Tools"
    assert_stdout_contains "nvm ok" "[ok]      nvm"
}

test_check_only_partial() {
    # xcode present (default shim), nvm and node not shimmed
    run_script
    assert_rc "partial exits 1" 1
    assert_stdout_contains "xcode ok" "[ok]      Xcode Command Line Tools"
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
    # Must not proceed to the nvm install step
    assert_stdout_not_contains "no nvm section" "--- START nvm ---"
}

test_install_xcode_present_proceeds() {
    create_nvm_shim
    run_script --install
    assert_rc "xcode present: install succeeds" 0
    assert_stdout_contains "xcode already" "Xcode Command Line Tools already installed"
    assert_stdout_contains "nvm section" "--- START nvm ---"
    assert_eq "xcode-select --install not called" "$(get_xcode_install_log)" ""
}

test_install_all_already_installed() {
    create_nvm_shim
    run_script --install
    assert_rc "install: all present exits 0" 0
    assert_stdout_contains "nvm already" "nvm is already installed"
    assert_contains "nvm install called" "$(get_nvm_log)" "nvm install --lts"
}

test_install_nvm_needs_install_success() {
    run_script --install
    assert_rc "nvm install succeeds" 0
    assert_stdout_contains "nvm installing" "nvm installed successfully"
    assert_contains "curl downloads nvm" "$(get_curl_log)" "nvm-sh/nvm"
    assert_contains "nvm installer ran" "$(get_nvm_installer_log)" "nvm-installer"
}

test_install_nvm_needs_install_fails() {
    touch "$TEST_DIR/nvm_install_fails"
    run_script --install
    assert_rc "nvm install fail exits 1" 1
    assert_stderr_contains "nvm fail msg" "nvm installation failed"
}

# nvm is detected by a sourceable ~/.nvm/nvm.sh (the real signal), never by a
# `command -v nvm` that a child process can't see. create_nvm_shim already lays
# down ~/.nvm/nvm.sh, so this is the "already installed" path
test_install_nvm_already_present_via_nvm_sh() {
    create_nvm_shim
    run_script --install
    assert_rc "nvm present: install succeeds" 0
    assert_stdout_contains "nvm already" "nvm is already installed"
    # Must NOT re-download when nvm.sh is already sourceable
    assert_not_contains "no nvm re-download" "$(get_curl_log)" "nvm-sh/nvm"
    assert_contains "nvm install --lts still run" "$(get_nvm_log)" "nvm install --lts"
}

# An empty ~/.nvm (no nvm.sh) is NOT "installed" -- the script installs fresh,
# since a sourceable nvm.sh is the only thing that counts
test_install_nvm_empty_dir_installs_fresh() {
    mkdir -p "$HOME/.nvm" # dir exists but has no nvm.sh
    run_script --install
    assert_rc "empty .nvm triggers fresh install" 0
    assert_stdout_contains "nvm installing" "nvm installed successfully"
    assert_contains "curl downloads nvm" "$(get_curl_log)" "nvm-sh/nvm"
    assert_contains "nvm installer ran" "$(get_nvm_installer_log)" "nvm-installer"
}

test_install_nvm_empty_dir_install_fails() {
    touch "$TEST_DIR/nvm_install_fails"
    mkdir -p "$HOME/.nvm"
    run_script --install
    assert_rc "empty .nvm + install fail exits 1" 1
    assert_stderr_contains "install fail msg" "nvm installation failed"
}

test_install_nvm_fresh_install_no_script_after() {
    # Custom curl whose installer succeeds but never creates nvm.sh
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
    assert_stderr_contains "script not found after install" "nvm script not found in"
}

# nvm.sh present but sourcing it does NOT define the `nvm` function -- a
# corrupt/partial install. The post-source verification must catch this
test_install_nvm_sh_present_but_no_function() {
    mkdir -p "$HOME/.nvm"
    # nvm.sh exists and is non-empty, but defines no nvm function
    printf '# broken nvm.sh: defines nothing\n:\n' > "$HOME/.nvm/nvm.sh"
    run_script --install
    assert_rc "broken nvm.sh exits 1" 1
    assert_stderr_contains "nvm not available msg" "nvm not available after sourcing"
}

test_install_node_install_success() {
    create_nvm_shim
    run_script --install
    assert_rc "node install succeeds" 0
    assert_stdout_contains "node installing" "Installing latest Long-Term Support (LTS) Node.js"
    assert_stdout_contains "node success" "Node.js installed successfully"
    assert_contains "nvm install lts" "$(get_nvm_log)" "nvm install --lts"
}

test_install_node_install_fails() {
    create_nvm_shim
    touch "$TEST_DIR/nvm_install_fails"
    run_script --install
    assert_rc "node install fail exits 1" 1
    assert_stderr_contains "node fail msg" "Node.js installation failed"
}

test_install_section_markers() {
    create_nvm_shim
    run_script --install
    assert_rc "markers present" 0
    assert_stdout_contains "xcode start" "--- START xcode ---"
    assert_stdout_contains "xcode finish" "--- FINISH xcode ---"
    assert_stdout_contains "nvm start" "--- START nvm ---"
    assert_stdout_contains "nvm finish" "--- FINISH nvm ---"
    assert_stdout_contains "node start" "--- START node/npm ---"
    assert_stdout_contains "node finish" "--- FINISH node/npm ---"
    assert_stdout_contains "shell-startup start" "--- START shell-startup ---"
    assert_stdout_contains "shell-startup finish" "--- FINISH shell-startup ---"
}

test_install_curl_gets_correct_flags() {
    run_script --install
    assert_rc "curl flags" 0
    assert_contains "curl uses -o-" "$(get_curl_log)" "-o-"
    assert_contains "curl includes url" "$(get_curl_log)" "https://raw.githubusercontent.com/nvm-sh/nvm"
}

# --- shell startup wiring ---

test_install_wires_nvm_into_rc() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install
    assert_rc "install succeeds" 0
    # bash (auto) targets ~/.bash_profile
    assert_contains "nvm block wired" "$(get_bashrc)" 'NVM_DIR/nvm.sh'
    assert_contains "nvm export wired" "$(get_bashrc)" 'export NVM_DIR="$HOME/.nvm"'
}

test_install_auto_bash_targets_bash_profile() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install
    assert_rc "install succeeds" 0
    assert_contains "wired into .bash_profile" "$(get_bashrc)" 'NVM_DIR/nvm.sh'
    assert_eq "did not touch .zshrc" "$(get_zshrc)" ""
}

test_install_auto_zsh_targets_zshrc() {
    create_nvm_shim
    run_script_shell "/bin/zsh" --install
    assert_rc "install succeeds" 0
    assert_contains "wired into .zshrc" "$(get_zshrc)" 'NVM_DIR/nvm.sh'
    assert_eq "did not touch .bash_profile" "$(get_bashrc)" ""
}

test_install_auto_unknown_shell_falls_back_to_profile() {
    create_nvm_shim
    run_script_shell "/usr/bin/fish" --install
    assert_rc "install succeeds" 0
    assert_contains "wired into .profile" "$(get_profile)" 'NVM_DIR/nvm.sh'
    assert_stderr_contains "warns about fallback" "fallback"
}

test_install_explicit_shell_bash() {
    create_nvm_shim
    # $SHELL is zsh, but --shell bash overrides detection
    run_script_shell "/bin/zsh" --install --shell bash
    assert_rc "install succeeds" 0
    assert_contains "explicit bash target" "$(get_bashrc)" 'NVM_DIR/nvm.sh'
    assert_eq "zsh untouched" "$(get_zshrc)" ""
}

test_install_shell_both_wires_two_files() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install --shell both
    assert_rc "install succeeds" 0
    assert_contains "bash_profile wired" "$(get_bashrc)" 'NVM_DIR/nvm.sh'
    assert_contains "zshrc wired" "$(get_zshrc)" 'NVM_DIR/nvm.sh'
}

test_install_rc_wiring_is_idempotent() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install
    assert_rc "first install succeeds" 0
    run_script_shell "/bin/bash" --install
    assert_rc "second install succeeds" 0
    # Re-running must not duplicate the setup lines
    assert_eq "nvm line appears once" "$(count_in_file "$HOME/.bash_profile" 'NVM_DIR/nvm.sh')" "1"
    # The component is named in its already-wired line, not just the file
    assert_stdout_contains "reports nvm already wired" "nvm already wired"
}

test_install_rc_wiring_labels_component() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install
    assert_rc "install succeeds" 0
    # The fresh-write path names the component in the wired-into line
    assert_stdout_contains "nvm wired line" "nvm wired into"
}

test_install_creates_rc_file_when_missing() {
    create_nvm_shim
    # Fresh HOME with no startup files at all (the fresh-Mac case)
    assert_eq "no .zshrc yet" "$(get_zshrc)" ""
    run_script_shell "/bin/zsh" --install
    assert_rc "install succeeds" 0
    assert_file_exists ".zshrc created" "$HOME/.zshrc"
    assert_contains "and wired" "$(get_zshrc)" 'NVM_DIR/nvm.sh'
}

test_install_wires_rc_even_when_all_present() {
    # nvm already installed, but the startup file has no setup lines.
    # A re-run must repair it rather than skip wiring
    create_nvm_shim
    assert_eq "no .bash_profile yet" "$(get_bashrc)" ""
    run_script_shell "/bin/bash" --install
    assert_rc "install succeeds" 0
    assert_stdout_contains "nvm already present" "nvm is already installed"
    assert_contains "still wired nvm" "$(get_bashrc)" 'NVM_DIR/nvm.sh'
}

test_install_shell_none_writes_nothing() {
    # --shell none is the opt-out for self-managed dotfiles: touch no files
    create_nvm_shim
    run_script_shell "/bin/bash" --install --shell none
    assert_rc "install succeeds" 0
    assert_eq "no .bash_profile written" "$(get_bashrc)" ""
    assert_eq "no .zshrc written" "$(get_zshrc)" ""
    assert_eq "no .profile written" "$(get_profile)" ""
    assert_stdout_contains "reports skipping" "Skipping shell startup wiring"
    # Prints the block so the user can add it themselves
    assert_stdout_contains "prints nvm line for manual use" 'NVM_DIR/nvm.sh'
    # Closing message must not falsely claim the tools are ready in new terminals
    assert_stdout_not_contains "no false ready claim" "ready in NEW terminal"
}

test_install_shell_none_opts_out_nvm_installer() {
    # Fresh nvm path: the script must pass PROFILE=/dev/null so nvm's own
    # installer also skips writing (its documented opt-out), not just us
    # no nvm shim -> fresh install path runs the installer
    run_script_shell "/bin/bash" --install --shell none
    assert_rc "install succeeds" 0
    assert_contains "nvm installer opted out" "$(get_nvm_profile_seen)" "/dev/null"
    assert_eq "still no rc file" "$(get_bashrc)" ""
}

test_shell_none_valid_in_check_mode() {
    # none must pass validation even though check mode never wires
    run_script --shell none
    # exits 0 or 1 by host state, but NOT 2 (validation error)
    local rc
    rc="$(get_rc)"
    assert_eq "none is a valid choice (not rc 2)" "$([ "$rc" = "2" ] && echo bad || echo ok)" "ok"
}

test_install_passes_profile_to_nvm_installer() {
    # Fresh nvm install path: the script must hand nvm's installer a PROFILE
    # pointing at the target startup file, on the correct (piped-bash) side
    run_script_shell "/bin/zsh" --install
    assert_rc "install succeeds" 0
    assert_contains "nvm installer saw PROFILE=.zshrc" "$(get_nvm_profile_seen)" "$HOME/.zshrc"
}

test_install_prints_new_terminal_and_reload_hint() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install
    assert_rc "install succeeds" 0
    assert_stdout_contains "mentions new terminal" "NEW terminal"
    assert_stdout_contains "offers reload command" 'exec "$SHELL" -l'
}

# --- --shell arg validation ---

test_shell_invalid_value_rejected() {
    run_script --install --shell bogus
    assert_rc "invalid --shell exits 2" 2
    assert_stderr_contains "invalid shell msg" "Invalid --shell"
}

test_shell_missing_value_rejected() {
    run_script --shell
    assert_rc "missing --shell value exits 2" 2
    assert_stderr_contains "missing value msg" "--shell requires a value"
}

test_shell_equals_form() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install --shell=zsh
    assert_rc "--shell=zsh parses" 0
    assert_contains "zsh wired via = form" "$(get_zshrc)" 'NVM_DIR/nvm.sh'
}

test_shell_short_flag_glued() {
    create_nvm_shim
    run_script_shell "/bin/bash" --install -szsh
    assert_rc "-szsh parses" 0
    assert_contains "zsh wired via glued short opt" "$(get_zshrc)" 'NVM_DIR/nvm.sh'
}

test_install_short_flag() {
    create_nvm_shim
    run_script_shell "/bin/bash" -i
    assert_rc "-i triggers install" 0
    # -i must enter install mode, not just check (section markers only print in install)
    assert_stdout_contains "install mode via -i" "--- START nvm ---"
}

test_install_short_flags_bundled() {
    create_nvm_shim
    # -is both expands to -i -s both -> install mode, wiring both shells
    run_script_shell "/bin/bash" -is both
    assert_rc "-is both parses" 0
    assert_contains "bash_profile wired via bundle" "$(get_bashrc)" 'NVM_DIR/nvm.sh'
    assert_contains "zshrc wired via bundle" "$(get_zshrc)" 'NVM_DIR/nvm.sh'
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
