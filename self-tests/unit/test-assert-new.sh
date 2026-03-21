#!/usr/bin/env bash
# self-tests/unit/test-assert-new.sh — Tests for new assertion helpers

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── assert_match ─────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_match: anchored regex passes"
assert_match "^hello" "hello world"

ptyunit_test_begin "assert_match: digit pattern passes"
assert_match "[0-9]+" "abc123"

ptyunit_test_begin "assert_match: failure outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_match '^xyz' 'hello'" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_match: failure shows pattern"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_match '^xyz' 'hello'" 2>&1)
assert_contains "$out" "xyz"

# ── assert_file_exists ───────────────────────────────────────────────────────

ptyunit_test_begin "assert_file_exists: existing file passes"
_tmpf=$(mktemp)
assert_file_exists "$_tmpf"
rm -f "$_tmpf"

ptyunit_test_begin "assert_file_exists: missing file outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_file_exists '/no/such/file'" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_file_exists: failure shows path"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_file_exists '/no/such/file'" 2>&1)
assert_contains "$out" "/no/such/file"

# ── assert_line ──────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_line: first line matches"
_multi=$'alpha\nbeta\ngamma'
assert_line "alpha" 1 "$_multi"

ptyunit_test_begin "assert_line: middle line matches"
assert_line "beta" 2 "$_multi"

ptyunit_test_begin "assert_line: last line matches"
assert_line "gamma" 3 "$_multi"

ptyunit_test_begin "assert_line: wrong content outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_line 'wrong' 1 'actual'" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_line: out of bounds outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_line 'x' 5 'one'" 2>&1)
assert_contains "$out" "FAIL"
assert_contains "$out" "line 5"

# ── assert_gt ────────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_gt: 10 > 5 passes"
assert_gt 10 5

ptyunit_test_begin "assert_gt: 5 > 10 fails"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_gt 5 10" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_gt: equal values fail"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_gt 5 5" 2>&1)
assert_contains "$out" "FAIL"

# ── assert_lt ────────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_lt: 3 < 7 passes"
assert_lt 3 7

ptyunit_test_begin "assert_lt: 7 < 3 fails"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_lt 7 3" 2>&1)
assert_contains "$out" "FAIL"

# ── assert_ge ────────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_ge: 10 >= 5 passes"
assert_ge 10 5

ptyunit_test_begin "assert_ge: 5 >= 5 passes (equal)"
assert_ge 5 5

ptyunit_test_begin "assert_ge: 3 >= 7 fails"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_ge 3 7" 2>&1)
assert_contains "$out" "FAIL"

# ── assert_le ────────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_le: 3 <= 7 passes"
assert_le 3 7

ptyunit_test_begin "assert_le: 5 <= 5 passes (equal)"
assert_le 5 5

ptyunit_test_begin "assert_le: 10 <= 3 fails"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_le 10 3" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_summary
