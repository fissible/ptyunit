#!/usr/bin/env bash
# self-tests/unit/test-assert-new.sh — Tests for new assertion helpers

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_match"

    test_that "anchored regex passes"
    assert_match "^hello" "hello world"

    test_that "digit pattern passes"
    assert_match "[0-9]+" "abc123"

    test_that "failure outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_match '^xyz' 'hello'" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "failure shows pattern"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_match '^xyz' 'hello'" 2>&1)
    assert_contains "$out" "xyz"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_file_exists"

    test_that "existing file passes"
    _tmpf=$(mktemp)
    assert_file_exists "$_tmpf"
    rm -f "$_tmpf"

    test_that "missing file outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_file_exists '/no/such/file'" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "failure shows path"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_file_exists '/no/such/file'" 2>&1)
    assert_contains "$out" "/no/such/file"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_line"

    test_that "first line matches"
    _multi=$'alpha\nbeta\ngamma'
    assert_line "alpha" 1 "$_multi"

    test_that "middle line matches"
    assert_line "beta" 2 "$_multi"

    test_that "last line matches"
    assert_line "gamma" 3 "$_multi"

    test_that "wrong content outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_line 'wrong' 1 'actual'" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "out of bounds outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_line 'x' 5 'one'" 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "line 5"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "numeric comparisons"

    # Pass cases — parameterized
    _check_gt() { assert_gt "$1" "$2"; }
    _check_lt() { assert_lt "$1" "$2"; }
    _check_ge() { assert_ge "$1" "$2"; }
    _check_le() { assert_le "$1" "$2"; }

    test_each _check_gt << 'PARAMS'
10|5
1|0
100|99
PARAMS

    test_each _check_lt << 'PARAMS'
3|7
0|1
-1|0
PARAMS

    test_each _check_ge << 'PARAMS'
10|5
5|5
0|0
PARAMS

    test_each _check_le << 'PARAMS'
3|7
5|5
0|0
PARAMS

    # Fail cases — verified in subshells
    test_that "assert_gt: 5 > 10 fails"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_gt 5 10" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "assert_gt: equal values fail"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_gt 5 5" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "assert_lt: 7 < 3 fails"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_lt 7 3" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "assert_ge: 3 >= 7 fails"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_ge 3 7" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "assert_le: 10 <= 3 fails"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_le 10 3" 2>&1)
    assert_contains "$out" "FAIL"

end_describe

ptyunit_test_summary
