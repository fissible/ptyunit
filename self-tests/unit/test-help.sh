#!/usr/bin/env bash
# self-tests/unit/test-help.sh — Tests for help.sh infrastructure
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/help.sh"

# ── _help_index ───────────────────────────────────────────────────────────────

test_that "_help_index lists every topic name from _TOPICS"
_idx=$(_help_index)
for (( _i=0; _i<${#_TOPICS[@]}; _i+=2 )); do
    assert_contains "$_idx" "${_TOPICS[_i]}"
done

test_that "_help_index includes Where to start note"
assert_contains "$(_help_index)" "Where to start"

# ── _dispatch ─────────────────────────────────────────────────────────────────

test_that "_dispatch with no argument shows index (does not error)"
_out=$(_dispatch)
assert_eq "0" "$?"
assert_contains "$_out" "Where to start"

test_that "_dispatch with unknown topic exits 1"
( _dispatch "__no_such_topic__" ) 2>/dev/null
assert_eq "1" "$?"

test_that "_dispatch unknown topic message mentions ptyunit help"
_err=$( ( _dispatch "__bad__" ) 2>&1 )
assert_contains "$_err" "ptyunit help"

# ── _detect_install ───────────────────────────────────────────────────────────

test_that "_detect_install returns a recognised value"
_inst=$(_detect_install)
case "$_inst" in
    submodule|brew|bpkg) assert_eq "0" "0" ;;
    *) assert_eq "submodule|brew|bpkg" "$_inst" ;;
esac

ptyunit_test_summary
