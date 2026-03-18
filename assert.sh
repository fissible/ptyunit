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
# Readable aliases — use whichever reads most naturally for your test.
test_that() { ptyunit_test_begin "$@"; }
test_it()   { ptyunit_test_begin "$@"; }
test_they() { ptyunit_test_begin "$@"; }

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
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected NOT to contain: %q\n  actual: %q\n' "$needle" "$haystack"
    fi
}

# Skip this test file with an optional reason. Exits with code 3 (skip signal).
# Usage: ptyunit_skip [reason]
ptyunit_skip() {
    local reason="${1:-}"
    if [[ -n "$reason" ]]; then
        printf 'SKIP (%s)\n' "$reason"
    else
        printf 'SKIP\n'
    fi
    exit 3
}

# Skip this test file if the running bash is older than MAJOR[.MINOR].
# Usage: ptyunit_require_bash MAJOR [MINOR]
ptyunit_require_bash() {
    local major="$1" minor="${2:-0}"
    if (( BASH_VERSINFO[0] < major )) ||
       (( BASH_VERSINFO[0] == major && BASH_VERSINFO[1] < minor )); then
        ptyunit_skip "requires bash ${major}.${minor}, running ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    fi
}

# Assert two strings are NOT equal.
assert_not_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected not equal to: %q\n' "$expected"
    fi
}

# Assert a command exits 0 (true).
# Usage: assert_true command [args...]
assert_true() {
    local msg="$*"
    if "$@" 2>/dev/null; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        printf ' — expected true: %s\n' "$msg"
    fi
}

# Assert a command exits non-zero (false).
# Usage: assert_false command [args...]
assert_false() {
    local msg="$*"
    if ! "$@" 2>/dev/null; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        printf ' — expected false: %s\n' "$msg"
    fi
}

# Assert a string is empty (null).
assert_null() {
    local value="$1" msg="${2:-}"
    if [[ -z "$value" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected empty, got: %q\n' "$value"
    fi
}

# Assert a string is non-empty (not null).
assert_not_null() {
    local value="$1" msg="${2:-}"
    if [[ -n "$value" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected non-empty string\n'
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
