#!/usr/bin/env bash
# tests/integration/test-menu.sh — PTY-driven tests for examples/menu.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_DIR/pty_run.py"
SCRIPT="$PTYUNIT_DIR/examples/menu.sh"

source "$PTYUNIT_DIR/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "menu: ENTER on first item — selects apple"
out=$(_pty ENTER)
assert_contains "$out" "apple"

ptyunit_test_begin "menu: DOWN then ENTER — selects banana"
out=$(_pty DOWN ENTER)
assert_contains "$out" "banana"

ptyunit_test_begin "menu: DOWN DOWN then ENTER — selects cherry"
out=$(_pty DOWN DOWN ENTER)
assert_contains "$out" "cherry"

ptyunit_test_begin "menu: DOWN at bottom — stays on last item"
out=$(_pty DOWN DOWN DOWN DOWN DOWN DOWN ENTER)
assert_contains "$out" "elderberry"

ptyunit_test_begin "menu: UP at top — stays on first item"
out=$(_pty UP ENTER)
assert_contains "$out" "apple"

ptyunit_test_begin "menu: DOWN then UP — back to first — selects apple"
out=$(_pty DOWN UP ENTER)
assert_contains "$out" "apple"

ptyunit_test_begin "menu: q key — no selection"
out=$(_pty q)
assert_contains "$out" "No selection"

ptyunit_test_begin "menu: Q key — no selection"
out=$(_pty Q)
assert_contains "$out" "No selection"

ptyunit_test_begin "menu: ESC key — no selection"
out=$(_pty ESC)
assert_contains "$out" "No selection"

ptyunit_test_begin "menu: SPACE selects current item"
out=$(_pty SPACE)
assert_contains "$out" "apple"

ptyunit_test_summary
