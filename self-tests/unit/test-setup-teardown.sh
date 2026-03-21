#!/usr/bin/env bash
# self-tests/unit/test-setup-teardown.sh — Tests for per-test setup/teardown + PWD isolation

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── ptyunit_setup runs before each section ───────────────────────────────────

ptyunit_test_begin "setup: runs before each test section"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _log=''
    ptyunit_setup() { _log=\"\${_log}S\"; }
    ptyunit_test_begin 'first'
    ptyunit_test_begin 'second'
    ptyunit_test_begin 'third'
    printf '%s' \"\$_log\"
" 2>&1)
assert_eq "SSS" "$out"

# ── ptyunit_teardown runs between sections ────────────────────────────────────

ptyunit_test_begin "teardown: runs between sections"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _log=''
    ptyunit_teardown() { _log=\"\${_log}T\"; }
    ptyunit_test_begin 'first'
    ptyunit_test_begin 'second'
    printf '%s' \"\$_log\"
" 2>&1)
assert_eq "T" "$out"

# ── ptyunit_teardown runs for last section via summary ───────────────────────

ptyunit_test_begin "teardown: runs for last section at summary time"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _log=''
    ptyunit_teardown() { _log=\"\${_log}T\"; }
    ptyunit_test_begin 'first'
    assert_eq 'a' 'a'
    ptyunit_test_begin 'second'
    assert_eq 'b' 'b'
    ptyunit_test_summary
    printf 'LOG=%s' \"\$_log\"
" 2>&1)
assert_contains "$out" "LOG=TT"

# ── setup/teardown interleaving order ─────────────────────────────────────────

ptyunit_test_begin "lifecycle: teardown-then-setup order between sections"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _log=''
    ptyunit_setup()    { _log=\"\${_log}S\"; }
    ptyunit_teardown() { _log=\"\${_log}T\"; }
    ptyunit_test_begin 'first'
    ptyunit_test_begin 'second'
    printf '%s' \"\$_log\"
" 2>&1)
assert_eq "STS" "$out"

# ── teardown runs even when section is skipped ────────────────────────────────

ptyunit_test_begin "teardown: runs even on skipped sections"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _log=''
    ptyunit_teardown() { _log=\"\${_log}T\"; }
    ptyunit_test_begin 'skipped'
    ptyunit_skip_test
    ptyunit_test_begin 'next'
    assert_eq 'a' 'a'
    ptyunit_test_summary
    printf 'LOG=%s' \"\$_log\"
" 2>&1)
assert_contains "$out" "LOG=TT"

# ── PWD isolation: cd in one section doesn't affect next ─────────────────────

ptyunit_test_begin "PWD isolation: cd in one section is restored for next"
out=$(bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    _orig_pwd=\$PWD
    ptyunit_test_begin 'section with cd'
    cd /tmp
    ptyunit_test_begin 'next section'
    if [[ \"\$PWD\" == \"\$_orig_pwd\" ]]; then
        printf 'RESTORED'
    else
        printf 'NOT_RESTORED: %s' \"\$PWD\"
    fi
" 2>&1)
assert_contains "$out" "RESTORED"
assert_not_contains "$out" "NOT_RESTORED"

# ── No setup/teardown defined: works normally ─────────────────────────────────

ptyunit_test_begin "lifecycle: works without setup/teardown defined"
rc=0
bash -c "
    source '$PTYUNIT_DIR/assert.sh'
    ptyunit_test_begin 'no hooks'
    assert_eq 'a' 'a'
    ptyunit_test_summary
" > /dev/null 2>&1 || rc=$?
assert_eq "0" "$rc"

ptyunit_test_summary
