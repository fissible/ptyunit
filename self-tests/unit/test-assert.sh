#!/usr/bin/env bash
# self-tests/unit/test-assert.sh — Self-tests for assert.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── assert_eq: pass ───────────────────────────────────────────────────────────

ptyunit_test_begin "assert_eq: equal strings pass silently"
assert_eq "hello" "hello"

ptyunit_test_begin "assert_eq: equal strings with msg pass silently"
assert_eq "42" "42" "numbers match"

ptyunit_test_begin "assert_eq: empty strings are equal"
assert_eq "" ""

# ── assert_eq: fail output ────────────────────────────────────────────────────

ptyunit_test_begin "assert_eq: mismatch outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'b'" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_eq: mismatch shows expected value"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'hello' 'world'" 2>&1)
assert_contains "$out" "hello"

ptyunit_test_begin "assert_eq: mismatch shows actual value"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'hello' 'world'" 2>&1)
assert_contains "$out" "world"

ptyunit_test_begin "assert_eq: mismatch includes section name when set"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; ptyunit_test_begin 'my section'; assert_eq 'a' 'b'" 2>&1)
assert_contains "$out" "my section"

ptyunit_test_begin "assert_eq: mismatch includes custom msg when provided"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'b' 'custom msg'" 2>&1)
assert_contains "$out" "custom msg"

# ── assert_contains ───────────────────────────────────────────────────────────

ptyunit_test_begin "assert_contains: substring present passes silently"
assert_contains "hello world" "world"

ptyunit_test_begin "assert_contains: exact match passes"
assert_contains "hello" "hello"

ptyunit_test_begin "assert_contains: missing substring outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_contains 'hello' 'xyz'" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "assert_contains: failure shows needle"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_contains 'hello' 'xyz'" 2>&1)
assert_contains "$out" "xyz"

# ── assert_output ─────────────────────────────────────────────────────────────

_greet() { printf 'Hello, %s' "$1"; }
_noop()  { :; }

ptyunit_test_begin "assert_output: captures stdout and compares"
assert_output "Hello, world" _greet "world"

ptyunit_test_begin "assert_output: empty stdout matches empty expected"
assert_output "" _noop

ptyunit_test_begin "assert_output: mismatch outputs FAIL"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; _f() { printf 'actual'; }; assert_output 'expected' _f" 2>&1)
assert_contains "$out" "FAIL"

# ── ptyunit_test_summary ──────────────────────────────────────────────────────

ptyunit_test_begin "ptyunit_test_summary: exits 0 when all pass"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'a'; ptyunit_test_summary" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc"

ptyunit_test_begin "ptyunit_test_summary: exits 1 when some fail"
rc=0
bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'b'; ptyunit_test_summary" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc"

ptyunit_test_begin "ptyunit_test_summary: OK line on all pass"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'a'; ptyunit_test_summary" 2>&1)
assert_contains "$out" "OK"

ptyunit_test_begin "ptyunit_test_summary: FAIL line when some fail"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'b'; ptyunit_test_summary" 2>&1)
assert_contains "$out" "FAIL"

ptyunit_test_begin "ptyunit_test_summary: pass count in output"
out=$(bash -c "source '$PTYUNIT_DIR/assert.sh'; assert_eq 'a' 'a'; assert_eq 'b' 'b'; ptyunit_test_summary" 2>&1)
assert_contains "$out" "2/2"

ptyunit_test_summary
