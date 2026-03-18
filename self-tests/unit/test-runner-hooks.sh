#!/usr/bin/env bash
# self-tests/unit/test-runner-hooks.sh — setUp / tearDown / color in run.sh

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

# Helper: create a temp project root with tests/unit/ layout
_make_suite() { local d; d=$(mktemp -d); mkdir -p "$d/tests/unit"; printf '%s' "$d"; }

# ── setUp runs before each test file ─────────────────────────────────────────
ptyunit_test_begin "setUp: runs before test file"

_d=$(_make_suite)
_sentinel="/tmp/ptyunit-hooks-$$-1"

# setUp creates sentinel
printf '#!/usr/bin/env bash\ntouch "%s"\n' "$_sentinel" > "$_d/tests/unit/setUp.sh"

# test verifies sentinel exists
cat > "$_d/tests/unit/test-a.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
[ -f "$_sentinel" ]
assert_eq "0" "\$?" "setUp ran before test"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
assert_contains "$_out" "1/1" "setUp: test saw sentinel"
rm -rf "$_d" "$_sentinel"

# ── tearDown runs after test file even on failure ─────────────────────────────
ptyunit_test_begin "tearDown: runs after failed test file"

_d=$(_make_suite)
_sentinel="/tmp/ptyunit-hooks-$$-2"

printf '#!/usr/bin/env bash\ntouch "%s"\n' "$_sentinel"  > "$_d/tests/unit/setUp.sh"
printf '#!/usr/bin/env bash\nrm -f "%s"\n' "$_sentinel"  > "$_d/tests/unit/tearDown.sh"

cat > "$_d/tests/unit/test-b.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "b" "intentional failure"
ptyunit_test_summary
FIXTURE

cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit > /dev/null 2>&1
# Sentinel should be gone — tearDown removed it
[ ! -f "$_sentinel" ]
assert_eq "0" "$?" "tearDown: removed sentinel after failure"
rm -rf "$_d"

# ── setUp failure → SKIP, runner exits 1 ─────────────────────────────────────
ptyunit_test_begin "setUp: failure causes SKIP and non-zero exit"

_d=$(_make_suite)

printf '#!/usr/bin/env bash\nexit 1\n' > "$_d/tests/unit/setUp.sh"

cat > "$_d/tests/unit/test-c.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "should" "not run" "unreachable"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
_rc=$?
assert_contains "$_out" "SKIP" "setUp failure: output says SKIP"
assert_eq "1" "$_rc"         "setUp failure: runner exits 1"
rm -rf "$_d"

# ── PTYUNIT_TEST_TMPDIR shared between setUp and test ────────────────────────
ptyunit_test_begin "PTYUNIT_TEST_TMPDIR: accessible in setUp and test file"

_d=$(_make_suite)

# setUp writes a value into the shared tmpdir
cat > "$_d/tests/unit/setUp.sh" << 'FIXTURE'
printf 'hello' > "$PTYUNIT_TEST_TMPDIR/msg"
FIXTURE

# test reads it back
cat > "$_d/tests/unit/test-d.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
_msg=\$(cat "\$PTYUNIT_TEST_TMPDIR/msg" 2>/dev/null)
assert_eq "hello" "\$_msg" "setUp wrote, test read PTYUNIT_TEST_TMPDIR"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
assert_contains "$_out" "1/1" "PTYUNIT_TEST_TMPDIR: shared read/write works"
rm -rf "$_d"

# ── tearDown also gets PTYUNIT_TEST_TMPDIR ────────────────────────────────────
ptyunit_test_begin "tearDown: receives same PTYUNIT_TEST_TMPDIR as setUp and test"

_d=$(_make_suite)
_sentinel="/tmp/ptyunit-hooks-$$-3"

# setUp writes a path into tmpdir; tearDown reads it and touches sentinel
cat > "$_d/tests/unit/setUp.sh" << 'FIXTURE'
printf '%s' "$PTYUNIT_TEST_TMPDIR" > "$PTYUNIT_TEST_TMPDIR/self"
FIXTURE

cat > "$_d/tests/unit/tearDown.sh" << FIXTURE
_path=\$(cat "\$PTYUNIT_TEST_TMPDIR/self" 2>/dev/null)
[ "\$_path" = "\$PTYUNIT_TEST_TMPDIR" ] && touch "$_sentinel"
FIXTURE

cat > "$_d/tests/unit/test-e.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "ok" "ok" "pass"
ptyunit_test_summary
FIXTURE

cd "$_d" && bash "$PTYUNIT_DIR/run.sh" --unit > /dev/null 2>&1
[ -f "$_sentinel" ]
assert_eq "0" "$?" "tearDown: received matching PTYUNIT_TEST_TMPDIR"
rm -rf "$_d" "$_sentinel"

# ── Colorized output: FORCE_COLOR=1 adds ANSI codes ──────────────────────────
ptyunit_test_begin "color: FORCE_COLOR=1 enables ANSI codes"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-color.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a" "pass"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && FORCE_COLOR=1 bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
assert_contains "$_out" $'\033' "FORCE_COLOR=1: output contains ESC"
rm -rf "$_d"

# ── Colorized output: NO_COLOR suppresses even when FORCE_COLOR set ───────────
ptyunit_test_begin "color: NO_COLOR=1 suppresses ANSI codes"

_d=$(_make_suite)
cat > "$_d/tests/unit/test-nocolor.sh" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "a" "a" "pass"
ptyunit_test_summary
FIXTURE

_out=$(cd "$_d" && FORCE_COLOR=1 NO_COLOR=1 bash "$PTYUNIT_DIR/run.sh" --unit 2>&1)
[[ "$_out" != *$'\033'* ]]
assert_eq "0" "$?" "NO_COLOR=1: output contains no ESC"
rm -rf "$_d"

ptyunit_test_summary
