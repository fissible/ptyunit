#!/usr/bin/env bash
# self-tests/unit/test-runner-format.sh — Tests for --format tap and --format junit

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

_make_suite() { local d; d=$(mktemp -d); mkdir -p "$d/tests/unit"; printf '%s' "$d"; }

# ── Create shared fixture ────────────────────────────────────────────────────

_d=$(_make_suite)

cat > "$_d/tests/unit/test-pass.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a"
ptyunit_test_summary
FIXTURE

cat > "$_d/tests/unit/test-fail.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "x" "y"
ptyunit_test_summary
FIXTURE

cat > "$_d/tests/unit/test-skip.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
ptyunit_skip "test reason"
FIXTURE

# ── TAP format ───────────────────────────────────────────────────────────────

ptyunit_test_begin "--format tap: includes TAP version header"
_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --format tap 2>&1)
assert_contains "$_out" "TAP version 13"

ptyunit_test_begin "--format tap: includes plan line"
assert_contains "$_out" "1.."

ptyunit_test_begin "--format tap: shows 'not ok' for failing test"
assert_contains "$_out" "not ok"

ptyunit_test_begin "--format tap: shows SKIP directive"
assert_contains "$_out" "# SKIP"

ptyunit_test_begin "--format tap: no pretty header in output"
assert_not_contains "$_out" "ptyunit test runner"

ptyunit_test_begin "--format tap: exits 1 on failure"
_rc=0
cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --format tap > /dev/null 2>&1 || _rc=$?
assert_eq "1" "$_rc"

# ── JUnit format ─────────────────────────────────────────────────────────────

ptyunit_test_begin "--format junit: includes XML header"
_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --format junit 2>&1)
assert_contains "$_out" "<?xml"

ptyunit_test_begin "--format junit: includes testsuites element"
assert_contains "$_out" "<testsuites>"
assert_contains "$_out" "</testsuites>"

ptyunit_test_begin "--format junit: includes testsuite element"
assert_contains "$_out" "<testsuite"

ptyunit_test_begin "--format junit: includes testcase elements"
assert_contains "$_out" "<testcase"

ptyunit_test_begin "--format junit: shows failure for failing test"
assert_contains "$_out" "<failure"

ptyunit_test_begin "--format junit: shows skipped for skipped test"
assert_contains "$_out" "<skipped"

ptyunit_test_begin "--format junit: no pretty header"
assert_not_contains "$_out" "ptyunit test runner"

# ── Teardown ─────────────────────────────────────────────────────────────────

rm -rf "$_d"

ptyunit_test_summary
