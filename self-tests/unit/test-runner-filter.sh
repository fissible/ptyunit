#!/usr/bin/env bash
# self-tests/unit/test-runner-filter.sh — Tests for --filter and --fail-fast

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

_make_suite() { local d; d=$(mktemp -d); mkdir -p "$d/tests/unit"; printf '%s' "$d"; }

# ── --filter: matches substring ──────────────────────────────────────────────

ptyunit_test_begin "--filter: matches test file by substring"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-alpha.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a"
ptyunit_test_summary
FIXTURE

cat > "$_d/tests/unit/test-beta.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "b" "b"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --filter alpha 2>&1)
assert_contains "$_out" "test-alpha.sh"
assert_not_contains "$_out" "test-beta.sh"
assert_contains "$_out" "1/1"
rm -rf "$_d"

# ── --filter: no match runs nothing ─────────────────────────────────────────

ptyunit_test_begin "--filter: no match runs no tests"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-alpha.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --filter nonexistent 2>&1)
_rc=$?
assert_eq "0" "$_rc" "filter no match: exits 0"
assert_contains "$_out" "0/0"
rm -rf "$_d"

# ── --filter: missing argument exits 2 ──────────────────────────────────────

ptyunit_test_begin "--filter: missing argument exits 2"

_out=$(bash "$PTYUNIT_DIR/run.sh" --filter 2>&1)
_rc=$?
assert_eq "2" "$_rc"
assert_contains "$_out" "Error"

# ── --fail-fast: stops after first failure ───────────────────────────────────

ptyunit_test_begin "--fail-fast: stops after first failure"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-a-pass.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a"
ptyunit_test_summary
FIXTURE

cat > "$_d/tests/unit/test-b-fail.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "x" "y"
ptyunit_test_summary
FIXTURE

cat > "$_d/tests/unit/test-c-pass.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "c" "c"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --fail-fast --jobs 1 2>&1)
_rc=$?
assert_eq "1" "$_rc"                                "--fail-fast: exits 1"
assert_contains "$_out" "test-b-fail.sh"            "--fail-fast: failing file appears"
assert_not_contains "$_out" "test-c-pass.sh"        "--fail-fast: later file skipped"
assert_contains "$_out" "fail-fast"                  "--fail-fast: notice shown"
rm -rf "$_d"

# ── --fail-fast: all passing exits 0 ─────────────────────────────────────────

ptyunit_test_begin "--fail-fast: all passing exits 0"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-pass.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --fail-fast 2>&1)
_rc=$?
assert_eq "0" "$_rc"
rm -rf "$_d"

# ── --format: unknown format exits 2 ─────────────────────────────────────────

ptyunit_test_begin "--format: unknown format exits 2"

_out=$(bash "$PTYUNIT_DIR/run.sh" --format unknown 2>&1)
_rc=$?
assert_eq "2" "$_rc"
assert_contains "$_out" "Error"

ptyunit_test_summary
