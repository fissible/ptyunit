#!/usr/bin/env bash
# self-tests/integration/test-confirm.sh — PTY-driven tests for examples/confirm.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_DIR/pty_run.py"
SCRIPT="$PTYUNIT_DIR/examples/confirm.sh"

source "$PTYUNIT_DIR/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "confirm: y key — confirmed"
out=$(_pty y)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: n key — cancelled"
out=$(_pty n)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: ENTER selects default (Yes) — confirmed"
out=$(_pty ENTER)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: RIGHT then ENTER — moves to No — cancelled"
out=$(_pty RIGHT ENTER)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: RIGHT then LEFT then ENTER — back to Yes — confirmed"
out=$(_pty RIGHT LEFT ENTER)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: q key — cancelled"
out=$(_pty q)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: Q key — cancelled"
out=$(_pty Q)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: ESC key — cancelled"
out=$(_pty ESC)
assert_contains "$out" "Cancelled"

ptyunit_test_summary
