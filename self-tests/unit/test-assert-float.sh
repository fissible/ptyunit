#!/usr/bin/env bash
# self-tests/unit/test-assert-float.sh — float comparison assertions (#52)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# Run a snippet in a fresh ptyunit process and return its combined output.
_in_subshell() {
    bash -c "source '$PTYUNIT_DIR/assert.sh'; $1; ptyunit_test_summary" 2>&1
}

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_float_eq"

    test_that "passes within default tolerance"
    assert_float_eq "$(awk 'BEGIN{printf "%.17g", 0.1+0.2}')" 0.3

    test_that "accepts an explicit tolerance"
    assert_float_eq 1.05 1.0 0.1

    test_that "accepts scientific notation and negative numbers"
    assert_float_eq 1e-3 0.001
    assert_float_eq -2.5 -2.50

    test_that "fails outside tolerance with a readable message"
    out=$(_in_subshell 'assert_float_eq 1.0 1.5 0.1')
    assert_contains "$out" "FAIL"
    assert_contains "$out" "1.0"
    assert_contains "$out" "1.5"

    test_that "rejects non-numeric input as a FAIL, not a silent pass"
    out=$(_in_subshell 'assert_float_eq abc 1.0')
    assert_contains "$out" "FAIL"
    assert_contains "$out" "not a number"

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_float_gt / lt / ge / le"

    test_that "compare as floats, not integers"
    assert_float_gt 2.5 2.4
    assert_float_lt 2.4 2.5
    assert_float_ge 2.5 2.5
    assert_float_le 2.5 2.5

    test_that "gt fails when not greater"
    out=$(_in_subshell 'assert_float_gt 1.0 2.0')
    assert_contains "$out" "FAIL"

    test_that "le fails when greater"
    out=$(_in_subshell 'assert_float_le 2.1 2.0')
    assert_contains "$out" "FAIL"

ptyunit_test_summary
