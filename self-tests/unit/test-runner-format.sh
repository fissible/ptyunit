#!/usr/bin/env bash
# self-tests/unit/test-runner-format.sh — Tests for --format tap and --format junit

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

_make_suite() { local d; d=$(mktemp -d); mkdir -p "$d/tests/unit"; printf '%s' "$d"; }

# ── Shared fixture ───────────────────────────────────────────────────────────

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

# ═════════════════════════════════════════════════════════════════════════════
describe "TAP format"

    test_that "includes TAP version header"
    _out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --format tap 2>&1)
    assert_contains "$_out" "TAP version 13"

    test_that "includes plan line"
    assert_contains "$_out" "1.."

    test_that "shows 'not ok' for failing test"
    assert_contains "$_out" "not ok"

    test_that "shows SKIP directive"
    assert_contains "$_out" "# SKIP"

    test_that "no pretty header in output"
    assert_not_contains "$_out" "ptyunit test runner"

    test_that "exits 1 on failure"
    _rc=0
    cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --format tap > /dev/null 2>&1 || _rc=$?
    assert_eq "1" "$_rc"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "JUnit format"

    test_that "includes XML header"
    _out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --format junit 2>&1)
    assert_contains "$_out" "<?xml"

    test_that "includes testsuites element"
    assert_contains "$_out" "<testsuites>"
    assert_contains "$_out" "</testsuites>"

    test_that "includes testsuite element"
    assert_contains "$_out" "<testsuite"

    test_that "includes testcase elements"
    assert_contains "$_out" "<testcase"

    test_that "shows failure for failing test"
    assert_contains "$_out" "<failure"

    test_that "shows skipped for skipped test"
    assert_contains "$_out" "<skipped"

    test_that "no pretty header"
    assert_not_contains "$_out" "ptyunit test runner"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
test_that "--format unknown exits 2"
_out=$(bash "$PTYUNIT_DIR/run.sh" --format unknown 2>&1)
_rc=$?
assert_eq "2" "$_rc"
assert_contains "$_out" "Error"

rm -rf "$_d"

ptyunit_test_summary
