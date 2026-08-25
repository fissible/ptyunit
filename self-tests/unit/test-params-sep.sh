#!/usr/bin/env bash
# self-tests/unit/test-params-sep.sh — test_each field separator (#49)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

_seen=()
_cb_record() { _seen+=("$#:$1:${2:-}"); }

# ═════════════════════════════════════════════════════════════════════════════
describe "test_each --sep"

    test_each --sep $'\t' _cb_record <<'PARAMS'
a|b	c
x	y|z
PARAMS

    test_that "tab separator keeps pipes inside values"
    assert_eq "2:a|b:c" "${_seen[0]}"
    assert_eq "2:x:y|z" "${_seen[1]}"

    _seen=()
    test_each --sep , _cb_record <<'PARAMS'
one,two
PARAMS

    test_that "any single character works as the separator"
    assert_eq "2:one:two" "${_seen[0]}"

    test_that "--sep rejects a multi-character separator"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        _cb() { :; }
        test_each --sep '::' _cb <<< 'a::b'; printf 'rc=%s\n' \$?
    " 2>&1)
    assert_contains "$out" "rc=2"
    assert_contains "$out" "single character"

# ═════════════════════════════════════════════════════════════════════════════
describe "test_each default separator (documented behavior)"

    _seen=()
    test_each _cb_record <<'PARAMS'
p|q
PARAMS

    test_that "default separator is still |"
    assert_eq "2:p:q" "${_seen[0]}"

    _cnt=""
    _cb_count() { _cnt="$#"; }
    test_each _cb_count <<'PARAMS'
a|b|
PARAMS

    test_that "a trailing empty field is dropped (read -a semantics)"
    assert_eq "2" "$_cnt"

ptyunit_test_summary
