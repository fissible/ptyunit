#!/usr/bin/env bash
# self-tests/unit/test-assert-coverage.sh — coverage for uncovered assertion paths

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_not_contains"

    test_that "absent substring passes"
    assert_not_contains "hello world" "xyz"

    test_that "present substring outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_not_contains 'hello world' 'world'" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "failure shows needle"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_not_contains 'hello world' 'world'" 2>&1)
    assert_contains "$out" "world"

    test_that "empty needle always matches — outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_not_contains 'hello' ''" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "empty haystack with non-empty needle passes"
    assert_not_contains "" "anything"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_count"

    test_that "zero occurrences matches expected 0"
    assert_count "hello world" "xyz" 0

    test_that "one occurrence matches expected 1"
    assert_count "hello world" "world" 1

    test_that "multiple occurrences match expected count"
    assert_count "aababab" "ab" 3

    test_that "wrong count outputs FAIL"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_count 'hello hello hello' 'hello' 2" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "failure shows expected count"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_count 'a b c' 'x' 1" 2>&1)
    assert_contains "$out" "1"

    test_that "failure shows actual count"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_count 'a b c' 'x' 1" 2>&1)
    assert_contains "$out" "0"

    test_that "overlapping matches: each advances past consumed needle"
    # "aa" in "aaaa" — each match advances: positions 0,1,2 → 3 matches
    assert_count "aaaa" "a" 4

    test_that "empty needle fails with error (not infinite loop)"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_count 'anything' '' 0" 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "non-empty"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "ptyunit_pass and ptyunit_fail"

    test_that "ptyunit_pass causes summary to exit 0"
    rc=0
    bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_pass; ptyunit_test_summary" >/dev/null 2>&1 || rc=$?
    assert_eq "0" "$rc"

    test_that "ptyunit_pass summary shows 1/1 passed"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_pass; ptyunit_test_summary" 2>&1)
    assert_contains "$out" "1/1"

    test_that "ptyunit_fail causes summary to exit 1"
    rc=0
    bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_fail 'boom'; ptyunit_test_summary" >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc"

    test_that "ptyunit_fail outputs message"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_fail 'something broke'" 2>&1)
    assert_contains "$out" "something broke"

    test_that "ptyunit_fail includes FAIL marker"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_fail 'boom'" 2>&1)
    assert_contains "$out" "FAIL"

    test_that "ptyunit_fail includes section name when set"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_test_begin 'my section'; ptyunit_fail 'oops'" 2>&1)
    assert_contains "$out" "my section"

    test_that "ptyunit_fail uses default message when none given"
    out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_fail" 2>&1)
    assert_contains "$out" "assertion failed"

end_describe

ptyunit_test_summary
