#!/usr/bin/env bash
# self-tests/unit/test-skip-test.sh — Tests for per-test skip (ptyunit_skip_test)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── ptyunit_skip_test: outputs SKIP with section name ────────────────────────

ptyunit_test_begin "skip_test: outputs SKIP with section name"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'my section'
    ptyunit_skip_test
" 2>&1)
assert_contains "$out" "SKIP"
assert_contains "$out" "my section"

# ── ptyunit_skip_test: outputs reason when provided ──────────────────────────

ptyunit_test_begin "skip_test: outputs reason"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'section'
    ptyunit_skip_test 'not ready yet'
" 2>&1)
assert_contains "$out" "not ready yet"

# ── Assertions after skip_test are silently skipped ──────────────────────────

ptyunit_test_begin "skip_test: subsequent assertions are skipped"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'section'
    ptyunit_skip_test 'reason'
    assert_eq 'a' 'b' 'should not appear'
    ptyunit_test_summary
" 2>&1)
# The assert_eq should be silently skipped — no FAIL output
assert_not_contains "$out" "should not appear"
assert_contains "$out" "0/0"

# ── Next test_that resets the skip flag ──────────────────────────────────────

ptyunit_test_begin "skip_test: next test_that resets skip"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'first'
    ptyunit_skip_test 'skip this'
    assert_eq 'a' 'b' 'THIS_SHOULD_NOT_APPEAR'
    ptyunit_test_begin 'second'
    assert_eq 'x' 'x' 'not skipped'
    ptyunit_test_summary
" 2>&1)
assert_not_contains "$out" "THIS_SHOULD_NOT_APPEAR"
assert_contains "$out" "1/1"

# ── Skip count in summary ───────────────────────────────────────────────────

ptyunit_test_begin "skip_test: skip count in summary"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'one'
    ptyunit_skip_test
    ptyunit_test_begin 'two'
    ptyunit_skip_test
    ptyunit_test_begin 'three'
    assert_eq 'a' 'a'
    ptyunit_test_summary
" 2>&1)
assert_contains "$out" "2 skipped"

# ── File exits 0 when only skipped + passing ─────────────────────────────────

ptyunit_test_begin "skip_test: file exits 0 with skip + pass"
rc=0
bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'skip me'
    ptyunit_skip_test
    ptyunit_test_begin 'pass me'
    assert_eq 'a' 'a'
    ptyunit_test_summary
" > /dev/null 2>&1 || rc=$?
assert_eq "0" "$rc"

# ── File exits 1 when non-skipped test fails ─────────────────────────────────

ptyunit_test_begin "skip_test: file exits 1 when non-skipped test fails"
rc=0
bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'skip me'
    ptyunit_skip_test
    ptyunit_test_begin 'fail me'
    assert_eq 'a' 'b'
    ptyunit_test_summary
" > /dev/null 2>&1 || rc=$?
assert_eq "1" "$rc"

# ── Double skip_test does not double-count ───────────────────────────────────

ptyunit_test_begin "skip_test: calling twice only counts one skip"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'one'
    ptyunit_skip_test 'first'
    ptyunit_skip_test 'second'
    ptyunit_test_begin 'two'
    assert_eq 'a' 'a'
    ptyunit_test_summary
" 2>&1)
# Should show 1 skipped, not 2
assert_contains "$out" "1 skipped"
assert_not_contains "$out" "2 skipped"

ptyunit_test_summary
