#!/usr/bin/env bash
# self-tests/unit/test-runner-home.sh
# Tests for PTYUNIT_HOME auto-export (#33) and --unit warning (#35).

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

mkdir -p "$_tmpdir/tests/unit"

# Fixture: a test that captures $PTYUNIT_HOME into a file (expanded at run time)
cat > "$_tmpdir/tests/unit/test-check-home.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
printf '%s' "\${PTYUNIT_HOME:-}" > "$_tmpdir/captured_home"
assert_not_null "\${PTYUNIT_HOME:-}" "PTYUNIT_HOME is set and exported"
ptyunit_test_summary
FIXTURE

# ── #33: PTYUNIT_HOME auto-detected when not set ─────────────────────────────
test_that "PTYUNIT_HOME is exported to test files when not pre-set"

( cd "$_tmpdir" && env -u PTYUNIT_HOME bash "$PTYUNIT_DIR/run.sh" --unit \
    --filter test-check-home > /dev/null 2>&1 ) || true
_captured=$(cat "$_tmpdir/captured_home" 2>/dev/null || true)
assert_not_null "$_captured"     "PTYUNIT_HOME: non-empty value exported to test"
assert_contains "$_captured" "/" "PTYUNIT_HOME: looks like a path"

# ── #33: PTYUNIT_HOME pre-set to valid path is preserved ─────────────────────
test_that "PTYUNIT_HOME pre-set to valid path is preserved"

( cd "$_tmpdir" && PTYUNIT_HOME="$PTYUNIT_DIR" bash "$PTYUNIT_DIR/run.sh" --unit \
    --filter test-check-home > /dev/null 2>&1 ) || true
_captured=$(cat "$_tmpdir/captured_home" 2>/dev/null || true)
assert_eq "$PTYUNIT_DIR" "$_captured" "PTYUNIT_HOME pre-set: value preserved"

# ── #33: PTYUNIT_HOME set to invalid path produces a clear error ──────────────
test_that "PTYUNIT_HOME set to invalid path exits with clear error message"

_out=$(cd "$_tmpdir" && PTYUNIT_HOME="/no/such/path" bash "$PTYUNIT_DIR/run.sh" --unit 2>&1 || true)
assert_contains "$_out" "PTYUNIT_HOME" "PTYUNIT_HOME bad path: error names the var"
assert_contains "$_out" "assert.sh"    "PTYUNIT_HOME bad path: error mentions assert.sh"

# ── #35: --unit emits warning about skipped integration tests ─────────────────
test_that "--unit emits a warning that integration tests are skipped"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
assert_contains "$_out" "--unit"      "--unit warning: message mentions --unit"
assert_contains "$_out" "integration" "--unit warning: message mentions integration"

# ── #35: --all does NOT emit the --unit warning ───────────────────────────────
test_that "--all does not emit the --unit skipped-integration warning"

_out=$(cd "$_tmpdir" && bash "$PTYUNIT_DIR/run.sh" --all 2>&1)
[[ "$_out" != *"--unit skips integration"* ]]
assert_eq "0" "$?" "--all: no --unit warning in output"

ptyunit_test_summary
