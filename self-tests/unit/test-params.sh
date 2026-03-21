#!/usr/bin/env bash
# self-tests/unit/test-params.sh — Tests for test_each (parameterized tests)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── test_each runs callback for each row ─────────────────────────────────────

ptyunit_test_begin "test_each: basic parameterized test"
_add_log=""
_verify_add() {
    local a="$1" b="$2" expected="$3"
    _add_log+="($a+$b=$expected)"
    assert_eq "$expected" "$(( a + b ))"
}
test_each _verify_add << 'PARAMS'
1|2|3
4|5|9
0|0|0
PARAMS
assert_eq "(1+2=3)(4+5=9)(0+0=0)" "$_add_log" "all rows ran"

# ── test_each skips comment lines ────────────────────────────────────────────

ptyunit_test_begin "test_each: skips comments and blank lines"
_count=0
_counter() { (( _count++ )) || true; assert_not_null "$1"; }
test_each _counter << 'PARAMS'
a

# this is a comment
b
PARAMS
assert_eq "2" "$_count" "only non-blank non-comment rows ran"

# ── test_each creates named test sections (verified via failure output) ──────

ptyunit_test_begin "test_each: creates test_that sections with param names"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _fail() { assert_eq 'x' 'WRONG'; }
    test_each _fail << 'P'
a|b
P
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "_fail (a|b)"

# ── test_each handles multi-field rows ───────────────────────────────────────

ptyunit_test_begin "test_each: handles 4+ fields"
_verify_fields() {
    assert_eq "a" "$1"
    assert_eq "b" "$2"
    assert_eq "c" "$3"
    assert_eq "d" "$4"
}
test_each _verify_fields << 'PARAMS'
a|b|c|d
PARAMS

# ── test_each with assertion failure ─────────────────────────────────────────

ptyunit_test_begin "test_each: failures are reported per row"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _check() { assert_eq 'yes' \"\$1\"; }
    test_each _check << 'P'
yes
no
yes
P
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "FAIL"
assert_contains "$out" "2/3"

# ── test_each with single-field rows ─────────────────────────────────────────

ptyunit_test_begin "test_each: works with single-field rows"
_items=""
_collect() { _items+="$1,"; }
test_each _collect << 'PARAMS'
alpha
beta
gamma
PARAMS
assert_eq "alpha,beta,gamma," "$_items"

ptyunit_test_summary
