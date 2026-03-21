#!/usr/bin/env bash
# self-tests/unit/test-mock.sh — Tests for mock.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "command mock"

    test_that "returns configured output"
    ptyunit_mock ptyunit_test_cmd --output "hello mock"
    result=$(ptyunit_test_cmd)
    assert_eq "hello mock" "$result"

    test_that "returns configured exit code"
    ptyunit_mock ptyunit_test_cmd --exit 42
    ptyunit_test_cmd 2>/dev/null; rc=$?
    assert_eq "42" "$rc"

    test_that "defaults to exit 0"
    ptyunit_mock ptyunit_test_cmd --output "ok"
    ptyunit_test_cmd >/dev/null
    assert_eq "0" "$?"

    test_that "records calls"
    ptyunit_mock ptyunit_test_cmd --output "ok"
    ptyunit_test_cmd >/dev/null
    ptyunit_test_cmd >/dev/null
    ptyunit_test_cmd >/dev/null
    assert_called ptyunit_test_cmd
    assert_called_times ptyunit_test_cmd 3

    test_that "records arguments"
    ptyunit_mock ptyunit_test_cmd --output "ok"
    ptyunit_test_cmd foo bar baz >/dev/null
    assert_called_with ptyunit_test_cmd foo bar baz

    test_that "records args per call"
    ptyunit_mock ptyunit_test_cmd --output "ok"
    ptyunit_test_cmd first >/dev/null
    ptyunit_test_cmd second >/dev/null
    assert_called_with ptyunit_test_cmd second
    first_args=$(mock_args ptyunit_test_cmd 1)
    assert_eq "first" "$first_args"

    test_that "heredoc body"
    ptyunit_mock ptyunit_test_cmd << 'MOCK'
echo "call $MOCK_CALL_NUM got: $*"
MOCK
    result=$(ptyunit_test_cmd hello world)
    assert_eq "call 1 got: hello world" "$result"

    test_that "heredoc body can branch on args"
    ptyunit_mock ptyunit_test_cmd << 'MOCK'
case "$1" in
    get)  echo "fetched" ;;
    set)  echo "stored" ;;
    *)    echo "unknown"; exit 1 ;;
esac
MOCK
    assert_eq "fetched" "$(ptyunit_test_cmd get)"
    assert_eq "stored" "$(ptyunit_test_cmd set)"
    ptyunit_test_cmd bad >/dev/null 2>&1; rc=$?
    assert_eq "1" "$rc"
    assert_called_times ptyunit_test_cmd 3

    test_that "assert_not_called passes when mock unused"
    ptyunit_mock ptyunit_test_cmd --output "ok"
    assert_not_called ptyunit_test_cmd

    test_that "mock_call_count returns count"
    ptyunit_mock ptyunit_test_cmd --output "ok"
    assert_eq "0" "$(mock_call_count ptyunit_test_cmd)"
    ptyunit_test_cmd >/dev/null
    assert_eq "1" "$(mock_call_count ptyunit_test_cmd)"
    ptyunit_test_cmd >/dev/null
    assert_eq "2" "$(mock_call_count ptyunit_test_cmd)"

    test_that "multiple mocks coexist"
    ptyunit_mock ptyunit_cmd_a --output "A"
    ptyunit_mock ptyunit_cmd_b --output "B"
    assert_eq "A" "$(ptyunit_cmd_a)"
    assert_eq "B" "$(ptyunit_cmd_b)"
    assert_called ptyunit_cmd_a
    assert_called ptyunit_cmd_b

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "auto-cleanup"

    test_that "create mock in this section"
    ptyunit_mock ptyunit_test_cmd --output "section A"
    result=$(ptyunit_test_cmd)
    assert_eq "section A" "$result"

    test_that "previous mock is gone"
    count=$(mock_call_count ptyunit_test_cmd)
    assert_eq "0" "$count"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
_test_helper() { echo "original"; }
_test_helper2() { echo "original2"; }
_test_checker() { return 0; }
_test_fn_with_args() { echo "$@"; }
_test_fn_body() { echo "original"; }
_test_manual() { echo "original manual"; }

describe "function mock"

    test_that "overrides function"
    ptyunit_mock _test_helper --output "mocked"
    result=$(_test_helper)
    assert_eq "mocked" "$result"
    assert_called _test_helper

    test_that "create mock for restore test"
    ptyunit_mock _test_helper2 --output "mocked2"
    assert_eq "mocked2" "$(_test_helper2)"

    test_that "original restored after section boundary"
    result=$(_test_helper2)
    assert_eq "original2" "$result"

    test_that "returns configured exit code"
    ptyunit_mock _test_checker --exit 1
    _test_checker 2>/dev/null; rc=$?
    assert_eq "1" "$rc"

    test_that "records arguments"
    ptyunit_mock _test_fn_with_args --output "ok"
    _test_fn_with_args alpha beta >/dev/null
    assert_called_with _test_fn_with_args alpha beta

    test_that "heredoc body"
    ptyunit_mock _test_fn_body << 'MOCK'
echo "body: $*"
MOCK
    result=$(_test_fn_body x y)
    assert_eq "body: x y" "$result"

    test_that "ptyunit_unmock restores original"
    ptyunit_mock _test_manual --output "mocked manual"
    assert_eq "mocked manual" "$(_test_manual)"
    ptyunit_unmock _test_manual
    result=$(_test_manual)
    assert_eq "original manual" "$result"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "verification failures"

    test_that "assert_called fails with message when not called"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        ptyunit_mock ptyunit_test_cmd --output ok
        assert_called ptyunit_test_cmd
        ptyunit_test_summary
    " 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "never called"

    test_that "assert_called_times fails with wrong count"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        ptyunit_mock ptyunit_test_cmd --output ok
        ptyunit_test_cmd >/dev/null
        assert_called_times ptyunit_test_cmd 5
        ptyunit_test_summary
    " 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "expected 5"

end_describe

ptyunit_test_summary
