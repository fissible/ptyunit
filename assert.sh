#!/usr/bin/env bash
# ptyunit/assert.sh — Lightweight test assertion helpers
#
# Usage:
#   source assert.sh
#   ptyunit_test_begin "my test name"
#   assert_eq "expected" "actual"
#   assert_output "expected output" my_command arg1 arg2
#   ptyunit_test_summary   # prints pass/fail counts; exits 1 if any failed

_PTYUNIT_TEST_PASS=0
_PTYUNIT_TEST_FAIL=0
_PTYUNIT_TEST_NAME=""

# Begin a named test section (optional; sets context for failure messages).
ptyunit_test_begin() {
    _PTYUNIT_TEST_NAME="$1"
}

# Assert two strings are equal.
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        (( _PTYUNIT_TEST_PASS++ ))
    else
        (( _PTYUNIT_TEST_FAIL++ ))
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected: %q\n  actual:   %q\n' "$expected" "$actual"
    fi
}

# Assert a command's stdout equals the expected string.
# Usage: assert_output "expected" command [args...]
assert_output() {
    local expected="$1"
    shift
    local actual
    actual=$("$@" 2>/dev/null)
    assert_eq "$expected" "$actual" "$*"
}

# Assert a string contains a substring.
assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        (( _PTYUNIT_TEST_PASS++ ))
    else
        (( _PTYUNIT_TEST_FAIL++ ))
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected to contain: %q\n  actual: %q\n' "$needle" "$haystack"
    fi
}

# Assert a string does NOT contain a substring.
assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        (( _PTYUNIT_TEST_PASS++ ))
    else
        (( _PTYUNIT_TEST_FAIL++ ))
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected NOT to contain: %q\n  actual: %q\n' "$needle" "$haystack"
    fi
}

# Print a summary line and exit 1 if any tests failed.
ptyunit_test_summary() {
    local total=$(( _PTYUNIT_TEST_PASS + _PTYUNIT_TEST_FAIL ))
    if (( _PTYUNIT_TEST_FAIL == 0 )); then
        printf 'OK  %d/%d tests passed\n' "$_PTYUNIT_TEST_PASS" "$total"
        return 0
    else
        printf 'FAIL  %d/%d tests passed (%d failed)\n' \
            "$_PTYUNIT_TEST_PASS" "$total" "$_PTYUNIT_TEST_FAIL"
        return 1
    fi
}
