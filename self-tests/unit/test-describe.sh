#!/usr/bin/env bash
# self-tests/unit/test-describe.sh — Tests for describe/end_describe (nestable scope)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── describe prefixes test names (verified via FAIL output) ──────────────────

ptyunit_test_begin "describe: prefixes test name"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    describe 'math'
        test_that 'adds numbers'
        assert_eq 'a' 'WRONG'
    end_describe
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "math > adds numbers"

# ── describe nests multiple levels ───────────────────────────────────────────

ptyunit_test_begin "describe: nests multiple levels"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    describe 'outer'
        describe 'middle'
            describe 'inner'
                test_that 'deep test'
                assert_eq 'a' 'WRONG'
            end_describe
        end_describe
    end_describe
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "outer > middle > inner > deep test"

# ── end_describe pops one level ──────────────────────────────────────────────

ptyunit_test_begin "describe: end_describe pops correctly"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    describe 'group A'
        test_that 'in A'
        assert_eq 'a' 'WRONG_A'
    end_describe
    describe 'group B'
        test_that 'in B'
        assert_eq 'b' 'WRONG_B'
    end_describe
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "group A > in A"
assert_contains "$out" "group B > in B"
assert_not_contains "$out" "group A > group B"

# ── tests outside describe have no prefix ────────────────────────────────────

ptyunit_test_begin "describe: tests outside have no prefix"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    test_that 'no prefix'
    assert_eq 'x' 'WRONG1'
    describe 'grouped'
        test_that 'with prefix'
        assert_eq 'x' 'WRONG2'
    end_describe
    test_that 'after describe'
    assert_eq 'x' 'WRONG3'
    ptyunit_test_summary
" 2>&1)
# "no prefix" should appear without describe prefix
assert_contains "$out" "[no prefix]"
# "with prefix" should have the describe prefix
assert_contains "$out" "[grouped > with prefix]"
# "after describe" should NOT have the describe prefix
assert_contains "$out" "[after describe]"
assert_not_contains "$out" "grouped > after describe"

# ── describe works with assertions counting ──────────────────────────────────

ptyunit_test_begin "describe: assertions count correctly"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    describe 'suite'
        test_that 'one'
        assert_eq 'a' 'a'
        test_that 'two'
        assert_eq 'b' 'b'
        assert_eq 'c' 'c'
    end_describe
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "3/3"

# ── describe + test_each combo ───────────────────────────────────────────────

ptyunit_test_begin "describe: works with test_each"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    describe 'math'
        _check() { assert_eq \"\$2\" \"\$(( \$1 * 2 ))\"; }
        test_each _check << 'P'
1|2
3|6
5|10
P
    end_describe
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "3/3"

# Verify the describe prefix is applied to parameterized test names
out2=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    describe 'math'
        _fail() { assert_eq 'x' 'WRONG'; }
        test_each _fail << 'P'
val
P
    end_describe
    ptyunit_test_summary
" 2>&1)
assert_contains "$out2" "math > _fail"

ptyunit_test_summary
