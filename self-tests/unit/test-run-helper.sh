#!/usr/bin/env bash
# self-tests/unit/test-run-helper.sh — Tests for run(), ptyunit_pass/fail

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "run helper"

    test_that "captures stdout into output"
    run printf "hello"
    assert_eq "hello" "$output"

    test_that "captures exit code into status"
    run bash -c "exit 42"
    assert_eq "42" "$status"

    test_that "status is 0 on success"
    run true
    assert_eq "0" "$status"

    test_that "captures stderr into output"
    run bash -c "echo err >&2"
    assert_eq "err" "$output"

    test_that "captures stdout+stderr combined"
    run bash -c "echo out; echo err >&2"
    assert_contains "$output" "out"
    assert_contains "$output" "err"

    test_that "splits output into lines array"
    run printf 'line1\nline2\nline3'
    assert_eq "line1" "${lines[0]}"
    assert_eq "line2" "${lines[1]}"
    assert_eq "line3" "${lines[2]}"

    test_that "lines array is empty when no output"
    run true
    assert_eq "0" "${#lines[@]}"

    test_that "works with functions"
    _greet() { printf 'Hi, %s' "$1"; }
    run _greet "world"
    assert_eq "Hi, world" "$output"
    assert_eq "0" "$status"

    test_that "does not trigger set -e on failure"
    run false
    assert_eq "1" "$status"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "custom matchers"

    # Define a custom assertion using ptyunit_pass / ptyunit_fail
    assert_even() {
        local n="$1"
        if (( n % 2 == 0 )); then
            ptyunit_pass
        else
            ptyunit_fail "expected even number, got: $n"
        fi
    }

    assert_positive() {
        local n="$1"
        if (( n > 0 )); then
            ptyunit_pass
        else
            ptyunit_fail "expected positive number, got: $n"
        fi
    }

    test_that "custom assertion passes"
    assert_even 4
    assert_even 0
    assert_positive 7

    test_that "custom assertion fails with message"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        assert_odd() {
            if (( \$1 % 2 != 0 )); then ptyunit_pass; else ptyunit_fail \"expected odd, got: \$1\"; fi
        }
        test_that 'check'
        assert_odd 4
        ptyunit_test_summary
    " 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "expected odd, got: 4"

    test_that "ptyunit_pass increments pass counter"
    # We're already in a test section; the assert_even calls above added to the count.
    # Just verify it works by calling directly.
    _before=$_PTYUNIT_TEST_PASS
    ptyunit_pass
    assert_eq "$(( _before + 1 ))" "$_PTYUNIT_TEST_PASS"

    test_that "custom matchers respect skip"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        assert_custom() { ptyunit_pass; }
        test_that 'skipped'
        ptyunit_skip_test
        assert_custom
        ptyunit_test_summary
    " 2>&1)
    assert_contains "$out" "0/0"

end_describe

ptyunit_test_summary
