#!/usr/bin/env bash
# self-tests/unit/test-runner.sh — tests for run.sh core behavior

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

# ── Fixtures ──────────────────────────────────────────────────────────────────
# Two unit test files: test-a (2 pass), test-b (1 pass + 1 fail)
_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/tests/unit"

cat > "$_tmpdir/tests/unit/test-a.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "1" "1" "a1"
assert_eq "2" "2" "a2"
ptyunit_test_summary
FIXTURE

cat > "$_tmpdir/tests/unit/test-b.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "x" "x" "b-pass"
assert_eq "x" "y" "b-fail"
ptyunit_test_summary
FIXTURE

# ── Default run (no flags) ────────────────────────────────────────────────────
ptyunit_test_begin "default: correct aggregate counts"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
_rc=$?
assert_contains "$_out" "3/4" "default: 3/4 assertions passed"
assert_eq "1" "$_rc"         "default: exits 1 on any failure"

# ── --jobs N is recognized ────────────────────────────────────────────────────
ptyunit_test_begin "--jobs N: recognized without error"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit --jobs 2 2>&1)
_rc=$?
[[ "$_out" != *"Unknown flag"* ]]
assert_eq "0" "$?" "--jobs 2: not reported as unknown flag"
assert_contains "$_out" "3/4" "--jobs 2: correct aggregate counts"
assert_eq "1" "$_rc"         "--jobs 2: exits 1 on failure"

# ── --jobs 1 runs one at a time, same counts ──────────────────────────────────
ptyunit_test_begin "--jobs 1: sequential-equivalent behavior"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit --jobs 1 2>&1)
assert_contains "$_out" "3/4" "--jobs 1: correct aggregate counts"

# ── --parallel is now an unknown flag ────────────────────────────────────────
ptyunit_test_begin "--parallel: rejected as unknown flag"

_out=$(bash "$PTYUNIT_DIR/run.sh" --parallel 2>&1)
_rc=$?
assert_eq "2" "$_rc"         "--parallel: exits 2"
assert_contains "$_out" "Unknown flag" "--parallel: error message"

# ── All-pass suite exits 0 ────────────────────────────────────────────────────
ptyunit_test_begin "all-pass suite exits 0"

_tmpdir2=$(mktemp -d)
mkdir -p "$_tmpdir2/tests/unit"
cat > "$_tmpdir2/tests/unit/test-pass.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "ok" "ok" "pass"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_tmpdir2" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
_rc=$?
assert_eq "0" "$_rc" "all-pass: exits 0"

# ── Skip: runner exits 0, shows SKIP, not counted as failure ─────────────────
ptyunit_test_begin "skip: runner exits 0 when all non-skipped tests pass"

_tmpdir3=$(mktemp -d)
mkdir -p "$_tmpdir3/tests/unit"

# One always-passing test, one always-skipping test
cat > "$_tmpdir3/tests/unit/test-pass.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a" "pass"
ptyunit_test_summary
FIXTURE

cat > "$_tmpdir3/tests/unit/test-skip.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
ptyunit_require_bash 999 0
assert_eq "should" "not run" "unreachable"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_tmpdir3" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
_rc=$?
assert_eq "0" "$_rc"             "skip: exits 0"
assert_contains "$_out" "SKIP"   "skip: output shows SKIP"
assert_contains "$_out" "1/1"    "skip: passing test still counted"

ptyunit_test_begin "skip: skipped file listed in summary"
assert_contains "$_out" "test-skip.sh" "skip: skipped filename in summary"

ptyunit_test_begin "skip: skipped file does not appear in Failed files"
[[ "$_out" != *"Failed files"* ]]
assert_eq "0" "$?" "skip: no Failed files section"

# ── --debug sets jobs=1 ───────────────────────────────────────────────────────
ptyunit_test_begin "--debug: recognized without error"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit --debug 2>&1)
_rc=$?
[[ "$_out" != *"Unknown flag"* ]]
assert_eq "0" "$?" "--debug: not reported as unknown flag"
assert_contains "$_out" "3/4" "--debug: correct aggregate counts"
assert_eq "1" "$_rc"          "--debug: exits 1 on failure"

# ── Timing: each file line includes elapsed time ──────────────────────────────
ptyunit_test_begin "timing: output includes elapsed time per file"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
assert_contains "$_out" " in " "timing: output contains ' in '"
assert_contains "$_out" "secs"  "timing: output contains 'secs'"

# ── --verbose / -v adds asserts/second ────────────────────────────────────────
ptyunit_test_begin "--verbose: recognized without error, adds asserts/second"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit --verbose 2>&1)
_rc=$?
[[ "$_out" != *"Unknown flag"* ]]
assert_eq "0" "$?" "--verbose: not unknown flag"
assert_contains "$_out" "asserts/second" "--verbose: output contains asserts/second"

ptyunit_test_begin "-v: recognized without error, adds asserts/second"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit -v 2>&1)
_rc=$?
[[ "$_out" != *"Unknown flag"* ]]
assert_eq "0" "$?" "-v: not unknown flag"
assert_contains "$_out" "asserts/second" "-v: output contains asserts/second"

# ── Teardown ──────────────────────────────────────────────────────────────────
rm -rf "$_tmpdir" "$_tmpdir2" "$_tmpdir3"

ptyunit_test_summary
