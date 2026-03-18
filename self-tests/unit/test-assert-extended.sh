#!/usr/bin/env bash
# self-tests/unit/test-assert-extended.sh — tests for richer assertion helpers

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── assert_not_eq ─────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_not_eq: different strings pass silently"
assert_not_eq "a" "b"

ptyunit_test_begin "assert_not_eq: equal strings output FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_not_eq 'x' 'x'" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_not_eq: failure output shows the duplicated value"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_not_eq 'same' 'same'" 2>&1)
assert_contains "$out" "same"

# ── assert_true ───────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_true: passing command counts as pass"
assert_true true

ptyunit_test_begin "assert_true: failing command outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_true false" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_true: works with multi-arg commands"
assert_true test "1" -eq "1"

# ── assert_false ──────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_false: failing command counts as pass"
assert_false false

ptyunit_test_begin "assert_false: passing command outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_false true" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_false: works with multi-arg commands"
assert_false test "1" -eq "2"

# ── assert_null ───────────────────────────────────────────────────────────────

ptyunit_test_begin "assert_null: empty string passes"
assert_null ""

ptyunit_test_begin "assert_null: non-empty string outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_null 'something'" 2>&1)
assert_contains "$out" "FAIL"

# ── assert_not_null ───────────────────────────────────────────────────────────

ptyunit_test_begin "assert_not_null: non-empty string passes"
assert_not_null "something"

ptyunit_test_begin "assert_not_null: empty string outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_not_null ''" 2>&1)
assert_contains "$out" "FAIL"

# ── ptyunit_skip ──────────────────────────────────────────────────────────────

ptyunit_test_begin "ptyunit_skip: exits 3"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_skip 'test reason'" > /dev/null 2>&1 || rc=$?
assert_eq "3" "$rc" "ptyunit_skip: exits with code 3"

ptyunit_test_begin "ptyunit_skip: outputs SKIP with reason"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_skip 'my reason'" 2>&1)
assert_contains "$out" "SKIP"      "ptyunit_skip: output contains SKIP"
assert_contains "$out" "my reason" "ptyunit_skip: output contains reason"

ptyunit_test_begin "ptyunit_skip: works without a reason"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_skip" > /dev/null 2>&1 || rc=$?
assert_eq "3" "$rc" "ptyunit_skip: exits 3 with no reason"

# ── ptyunit_require_bash ──────────────────────────────────────────────────────

ptyunit_test_begin "require_bash: continues silently when version is met"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_require_bash 1 0; exit 0" || rc=$?
assert_eq "0" "$rc" "require_bash: exits 0 when version met"

ptyunit_test_begin "require_bash: exits 3 when major version not met"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_require_bash 999 0" > /dev/null 2>&1 || rc=$?
assert_eq "3" "$rc" "require_bash: exits 3 when major not met"

ptyunit_test_begin "require_bash: exits 3 when minor version not met"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_require_bash ${BASH_VERSINFO[0]} 9999" > /dev/null 2>&1 || rc=$?
assert_eq "3" "$rc" "require_bash: exits 3 when minor not met"

ptyunit_test_begin "require_bash: output includes required and running versions"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_require_bash 999 0" 2>&1)
assert_contains "$out" "999"                        "require_bash: output shows required version"
assert_contains "$out" "${BASH_VERSINFO[0]}"        "require_bash: output shows running version"

ptyunit_test_begin "require_bash: major-only form works"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_require_bash 999" > /dev/null 2>&1 || rc=$?
assert_eq "3" "$rc" "require_bash: major-only form exits 3"

ptyunit_test_summary
