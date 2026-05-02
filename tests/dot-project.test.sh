#!/bin/bash
# dot-project.test.sh - Tests for dot-project
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../dot-project"

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has SYNOPSIS" "SYNOPSIS"
    assert_stdout_contains "help has DESCRIPTION" "DESCRIPTION"
}

test_help_short_flag() {
    run_script -h
    assert_rc "-h exits 0" 0
    assert_stdout_contains "-h shows help" "NAME"
}

test_current_directory_no_subdirs() {
    mkdir -p "$TEST_DIR/empty"
    cd "$TEST_DIR/empty" || exit 1
    run_script
    assert_rc "no subdirs exits 0" 0
    assert_eq "no output" "$(get_stdout)" ""
}

test_current_directory_one_subdir() {
    mkdir -p "$TEST_DIR/cart_test/cartridge_a"
    cd "$TEST_DIR/cart_test" || exit 1
    run_script
    assert_rc "one subdir exits 0" 0
    assert_stdout_contains "success message" "Generated ./cartridge_a/.project"
    [ -f "$TEST_DIR/cart_test/cartridge_a/.project" ] || _fail "file not created"
    assert_contains "cartridge name" "$(cat "$TEST_DIR/cart_test/cartridge_a/.project")" "<name>cartridge_a</name>"
}

test_explicit_directory() {
    mkdir -p "$TEST_DIR/code_version/cartridge_b"
    run_script "$TEST_DIR/code_version"
    assert_rc "explicit dir exits 0" 0
    assert_stdout_contains "generated" "Generated $TEST_DIR/code_version/cartridge_b/.project"
    [ -f "$TEST_DIR/code_version/cartridge_b/.project" ] || _fail "file not created in explicit dir"
}

test_trailing_slash_stripped() {
    mkdir -p "$TEST_DIR/code_version/cartridge_c"
    run_script "$TEST_DIR/code_version/"
    assert_rc "trailing slash exits 0" 0
    assert_stdout_contains "handles trailing slash" "Generated $TEST_DIR/code_version/cartridge_c/.project"
}

test_multiple_subdirs() {
    mkdir -p "$TEST_DIR/cv/cart1"
    mkdir -p "$TEST_DIR/cv/cart2"
    mkdir -p "$TEST_DIR/cv/cart3"
    run_script "$TEST_DIR/cv"
    assert_rc "multiple subdirs exits 0" 0
    assert_stdout_contains "cart1 generated" "Generated $TEST_DIR/cv/cart1/.project"
    assert_stdout_contains "cart2 generated" "Generated $TEST_DIR/cv/cart2/.project"
    assert_stdout_contains "cart3 generated" "Generated $TEST_DIR/cv/cart3/.project"
    [ -f "$TEST_DIR/cv/cart1/.project" ] || _fail "cart1 .project not created"
    [ -f "$TEST_DIR/cv/cart2/.project" ] || _fail "cart2 .project not created"
    [ -f "$TEST_DIR/cv/cart3/.project" ] || _fail "cart3 .project not created"
}

test_ignores_files() {
    mkdir -p "$TEST_DIR/cv/cartridge_d"
    touch "$TEST_DIR/cv/somefile.txt"
    run_script "$TEST_DIR/cv"
    assert_rc "ignores files exits 0" 0
    assert_stdout_contains "cartridge processed" "Generated $TEST_DIR/cv/cartridge_d/.project"
    assert_stdout_not_contains "no mention of file" "somefile.txt"
    [ ! -f "$TEST_DIR/cv/somefile.txt/.project" ] || _fail "should not create .project for file"
}

test_xml_structure() {
    mkdir -p "$TEST_DIR/my_cartridge"
    run_script "$TEST_DIR"
    assert_rc "xml test exits 0" 0
    local content
    content="$(cat "$TEST_DIR/my_cartridge/.project")"
    assert_contains "xml declaration" "$content" '<?xml version="1.0" encoding="UTF-8"?>'
    assert_contains "project description" "$content" "<projectDescription>"
    assert_contains "project name" "$content" "<name>my_cartridge</name>"
    assert_contains "build command" "$content" "<name>com.demandware.studio.core.beehiveElementBuilder</name>"
    assert_contains "nature" "$content" "<nature>com.demandware.studio.core.beehiveNature</nature>"
}

test_special_chars_in_dirname() {
    mkdir -p "$TEST_DIR/cart-with-dash_and_underscore"
    run_script "$TEST_DIR"
    assert_rc "special chars exits 0" 0
    assert_stdout_contains "handles special chars" "Generated $TEST_DIR/cart-with-dash_and_underscore/.project"
    local content
    content="$(cat "$TEST_DIR/cart-with-dash_and_underscore/.project")"
    assert_contains "name matches dir" "$content" "<name>cart-with-dash_and_underscore</name>"
}

test_readonly_directory_fails() {
    mkdir -p "$TEST_DIR/cv_readonly/readonly_cart"
    chmod 555 "$TEST_DIR/cv_readonly/readonly_cart"
    run_script "$TEST_DIR/cv_readonly"
    assert_rc "readonly exits 0 despite error" 0
    assert_err_contains "error message" "[ERR][dot-project] Failed to create $TEST_DIR/cv_readonly/readonly_cart/.project"
    chmod 755 "$TEST_DIR/cv_readonly/readonly_cart" # cleanup for temp dir removal
}

test_overwrites_existing() {
    mkdir -p "$TEST_DIR/existing_cart"
    echo "old content" > "$TEST_DIR/existing_cart/.project"
    run_script "$TEST_DIR"
    assert_rc "overwrite exits 0" 0
    assert_stdout_contains "overwrites" "Generated $TEST_DIR/existing_cart/.project"
    local content
    content="$(cat "$TEST_DIR/existing_cart/.project")"
    assert_not_contains "old content replaced" "$content" "old content"
    assert_contains "new content" "$content" "<name>existing_cart</name>"
}

test_nonexistent_directory() {
    run_script "$TEST_DIR/does_not_exist"
    assert_rc "nonexistent dir exits 0" 0
    assert_eq "no output for nonexistent" "$(get_stdout)" ""
}

test_dot_directory_skipped() {
    mkdir -p "$TEST_DIR/cv2/.hidden"
    mkdir -p "$TEST_DIR/cv2/visible"
    run_script "$TEST_DIR/cv2"
    assert_rc "dot dir exits 0" 0
    assert_stdout_not_contains "hidden skipped" ".hidden"
    assert_stdout_contains "visible processed" "visible/.project"
    [ ! -f "$TEST_DIR/cv2/.hidden/.project" ] || _fail "should not create .project in hidden dir"
    [ -f "$TEST_DIR/cv2/visible/.project" ] || _fail "should create .project in visible dir"
}

test_nested_subdirs_not_processed() {
    mkdir -p "$TEST_DIR/cv/cart/nested"
    run_script "$TEST_DIR/cv"
    assert_rc "nested exits 0" 0
    assert_stdout_contains "top level processed" "Generated $TEST_DIR/cv/cart/.project"
    [ -f "$TEST_DIR/cv/cart/.project" ] || _fail "top level .project not created"
    [ ! -f "$TEST_DIR/cv/cart/nested/.project" ] || _fail "nested .project should not be created"
}

# --- run ---

run_tests "$@"
