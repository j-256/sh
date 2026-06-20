#!/bin/bash
# gen-catalog.test.sh - Tests for gen-catalog
# shellcheck source-path=SCRIPTDIR disable=SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

UNDER_TEST="$SCRIPT_DIR/../gen-catalog"

# --- helpers ---

# No external commands are called by gen-catalog (pure bash), so no shims needed

# --- test cases ---

test_help_output() {
    run_script --help
    assert_rc "help exits 0" 0
    assert_stdout_contains "help has NAME" "NAME"
    assert_stdout_contains "help has gen-catalog" "gen-catalog"
}

test_help_short() {
    run_script -h
    assert_rc "help -h exits 0" 0
    assert_stdout_contains "help -h has NAME" "NAME"
}

test_missing_all_args() {
    run_script
    assert_rc "no args exits 2" 2
    assert_stderr_contains "usage message" "Must provide BASE_COUNT and VARIANTS_PER_BASE"
}

test_missing_variants_per_base() {
    run_script 5
    assert_rc "missing second arg exits 2" 2
    assert_stderr_contains "usage message" "Must provide BASE_COUNT and VARIANTS_PER_BASE"
}

test_base_count_non_numeric() {
    run_script "abc" 2
    assert_rc "non-numeric base_count exits 2" 2
    assert_stderr_contains "base_count must be integer" "BASE_COUNT must be a positive integer"
}

test_variants_per_base_non_numeric() {
    run_script 2 "xyz"
    assert_rc "non-numeric variants_per_base exits 2" 2
    assert_stderr_contains "variants_per_base must be integer" "VARIANTS_PER_BASE must be a positive integer"
}

test_base_count_zero() {
    run_script 0 2
    assert_rc "zero base_count exits 2" 2
    assert_stderr_contains "must be greater than zero" "must be greater than zero"
}

test_variants_per_base_zero() {
    run_script 2 0
    assert_rc "zero variants_per_base exits 2" 2
    assert_stderr_contains "must be greater than zero" "must be greater than zero"
}

test_base_count_negative() {
    run_script -5 2
    assert_rc "negative base_count exits 2" 2
    assert_stderr_contains "base_count must be integer" "BASE_COUNT must be a positive integer"
}

test_happy_path_1x1() {
    run_script 1 1
    assert_rc "1x1 exits 0" 0
    assert_stdout_contains "xml declaration" '<?xml version="1.0" encoding="UTF-8"?>'
    assert_stdout_contains "catalog element" '<catalog xmlns="http://www.demandware.com/xml/impex/catalog/2006-10-31"'
    assert_stdout_contains "default catalog-id" 'catalog-id="test-catalog"'
    assert_stdout_contains "header element" '<header/>'
    assert_stdout_contains "base product" 'product-id="BASE1"'
    assert_stdout_contains "base display-name" '<display-name xml:lang="en">BASE1</display-name>'
    assert_stdout_contains "variant product" 'product-id="BASE1-VAR-001"'
    assert_stdout_contains "variant default" 'variant product-id="BASE1-VAR-001" default="true"'
    assert_stdout_contains "variant display-name" '<display-name xml:lang="en">BASE1 Variant 001</display-name>'
    assert_stdout_contains "closing tag" '</catalog>'
}

test_default_catalog_id() {
    run_script 1 1
    assert_rc "default catalog_id exits 0" 0
    assert_stdout_contains "default is test-catalog" 'catalog-id="test-catalog"'
}

test_custom_catalog_id() {
    run_script 1 1 my-custom-catalog
    assert_rc "custom catalog_id exits 0" 0
    assert_stdout_contains "custom catalog-id" 'catalog-id="my-custom-catalog"'
    assert_stdout_not_contains "not default" 'catalog-id="test-catalog"'
}

test_multiple_bases() {
    run_script 3 1
    assert_rc "3 bases exits 0" 0
    assert_stdout_contains "base1" 'product-id="BASE1"'
    assert_stdout_contains "base2" 'product-id="BASE2"'
    assert_stdout_contains "base3" 'product-id="BASE3"'
}

test_multiple_variants() {
    run_script 1 3
    assert_rc "3 variants exits 0" 0
    assert_stdout_contains "variant 001" 'product-id="BASE1-VAR-001"'
    assert_stdout_contains "variant 002" 'product-id="BASE1-VAR-002"'
    assert_stdout_contains "variant 003" 'product-id="BASE1-VAR-003"'
    assert_stdout_contains "first is default" 'variant product-id="BASE1-VAR-001" default="true"'
}

test_second_variant_not_default() {
    run_script 1 2
    assert_rc "2 variants exits 0" 0
    local out
    out="$(get_stdout)"
    assert_contains "VAR-001 is default" "$out" 'variant product-id="BASE1-VAR-001" default="true"'
    assert_not_contains "VAR-002 not default" "$out" 'variant product-id="BASE1-VAR-002" default="true"'
    assert_contains "VAR-002 has no default attr" "$out" 'variant product-id="BASE1-VAR-002"/>'
}

test_variant_numbering_padded() {
    run_script 1 12
    assert_rc "12 variants exits 0" 0
    assert_stdout_contains "variant 001 padded" 'BASE1-VAR-001'
    assert_stdout_contains "variant 010 padded" 'BASE1-VAR-010'
    assert_stdout_contains "variant 012 padded" 'BASE1-VAR-012'
}

test_base_then_variants_order() {
    run_script 2 2
    assert_rc "order check exits 0" 0
    local out
    out="$(get_stdout)"
    # Check that BASE1 and its variants appear before BASE2
    local base1_pos
    local base1_var_pos
    local base2_pos
    base1_pos="$(echo "$out" | grep -n 'product-id="BASE1"' | head -n1 | cut -d: -f1)"
    base1_var_pos="$(echo "$out" | grep -n 'product-id="BASE1-VAR-001"' | tail -n1 | cut -d: -f1)"
    base2_pos="$(echo "$out" | grep -n 'product-id="BASE2"' | head -n1 | cut -d: -f1)"

    [ "$base1_pos" -lt "$base1_var_pos" ] && _ok "BASE1 before its variants"
    [ "$base1_var_pos" -lt "$base2_pos" ] && _ok "BASE1 variants before BASE2"
}

test_variations_structure() {
    run_script 1 1
    assert_rc "structure check exits 0" 0
    assert_stdout_contains "variations element" '<variations>'
    assert_stdout_contains "variants element" '<variants>'
    assert_stdout_contains "variant self-closing" '<variant product-id="BASE1-VAR-001" default="true"/>'
}

test_large_catalog() {
    run_script 10 5
    assert_rc "10x5 exits 0" 0
    assert_stdout_contains "base10 exists" 'product-id="BASE10"'
    assert_stdout_contains "base10-var-005 exists" 'product-id="BASE10-VAR-005"'
}

test_clean_exit_no_stderr() {
    # Regression: previously a duplicate __unset caused "trap failed" on stderr
    run_script 2 2
    assert_rc "success exits 0" 0
    assert_eq "no stderr noise on clean exit" "$(get_stderr)" ""
    assert_stderr_not_contains "no trap error" "trap failed"
    assert_stderr_not_contains "no command not found" "command not found"
}

# --- run ---

run_tests "$@"
