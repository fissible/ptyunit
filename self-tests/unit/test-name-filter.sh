#!/usr/bin/env bash
# self-tests/unit/test-name-filter.sh — Tests for --name filter (test name matching)

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

_make_suite() { local d; d=$(mktemp -d); mkdir -p "$d/tests/unit"; printf '%s' "$d"; }

# ── --name filters by test section name ──────────────────────────────────────

ptyunit_test_begin "--name: runs only matching test sections"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-a.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
test_that "alpha test"
assert_eq "a" "a"
test_that "beta test"
assert_eq "b" "b"
test_that "gamma test"
assert_eq "c" "c"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --name "beta" 2>&1)
assert_contains "$_out" "1/1"   "--name beta: only one assertion ran"
rm -rf "$_d"

# ── --name with no match produces 0/0 ───────────────────────────────────────

ptyunit_test_begin "--name: no match runs 0 assertions"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-a.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
test_that "alpha test"
assert_eq "a" "a"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --name "nonexistent" 2>&1)
assert_contains "$_out" "0/0"
rm -rf "$_d"

# ── --name works with describe prefix ────────────────────────────────────────

ptyunit_test_begin "--name: matches against describe > name"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-a.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
describe "math"
    test_that "adds"
    assert_eq "3" "\$(( 1 + 2 ))"
    test_that "subs"
    assert_eq "1" "\$(( 3 - 2 ))"
end_describe
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --name "math > adds" 2>&1)
assert_contains "$_out" "1/1"   "--name matches describe prefix"
rm -rf "$_d"

# ── --name combined with --filter ────────────────────────────────────────────

ptyunit_test_begin "--name + --filter: both applied"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-alpha.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
test_that "one"
assert_eq "a" "a"
test_that "two"
assert_eq "b" "b"
ptyunit_test_summary
FIXTURE

cat > "$_d/tests/unit/test-beta.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
test_that "one"
assert_eq "x" "x"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit --filter alpha --name "two" 2>&1)
assert_contains "$_out" "1/1"   "filter + name: one assertion"
assert_not_contains "$_out" "test-beta.sh"
rm -rf "$_d"

# ── --name missing argument exits 2 ─────────────────────────────────────────

ptyunit_test_begin "--name: missing argument exits 2"
_out=$(bash "$PTYUNIT_DIR/run.sh" --name 2>&1)
_rc=$?
assert_eq "2" "$_rc"
assert_contains "$_out" "Error"

# ── Name-filtered sections skip setup/teardown ──────────────────────────────

ptyunit_test_begin "--name: filtered sections don't run setup/teardown"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-hooks.sh" << 'FIXTURE'
PTYUNIT_DIR_L="$1"
source "$PTYUNIT_DIR_L/assert.sh"
_log=""
ptyunit_setup()    { _log="${_log}S"; }
ptyunit_teardown() { _log="${_log}T"; }
test_that "match"
assert_eq "a" "a"
test_that "nomatch"
assert_eq "b" "b"
ptyunit_test_summary
printf 'LOG=%s\n' "$_log"
FIXTURE

# Run with name filter - need to pass PTYUNIT_DIR as arg since heredoc can't interpolate
_out=$(cd "$_d" && PTYUNIT_FILTER_NAME="match" bash "$_d/tests/unit/test-hooks.sh" "$PTYUNIT_DIR" 2>&1)
# Only "match" section should trigger setup/teardown: S(match)T(match at summary)
assert_contains "$_out" "LOG=ST"   "only one setup+teardown pair"
rm -rf "$_d"

# ── inline filter rejection — covers assert.sh lines 99-100 ──────────────────
# (All --name tests above invoke run.sh in subshells; this exercises the
# filter-rejection branch of ptyunit_test_begin inline for PS4 coverage.)

ptyunit_test_begin "--name inline: unfiltered section"
assert_eq "no filter active" "no filter active"
PTYUNIT_FILTER_NAME="__no_match__"
ptyunit_test_begin "--name inline: this section is filtered"
# Body is skipped (_PTYUNIT_SECTION_FILTERED=1) — no assertions here
PTYUNIT_FILTER_NAME=""

ptyunit_test_summary
