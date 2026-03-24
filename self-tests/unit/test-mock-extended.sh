#!/usr/bin/env bash
# self-tests/unit/test-mock-extended.sh — coverage for uncovered mock paths

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_called_with failures"

    test_that "fails when mock was never called"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        ptyunit_mock ptyunit_test_cmd --output ok
        assert_called_with ptyunit_test_cmd foo
    " 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "never called"

    test_that "fails when args do not match"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        ptyunit_mock ptyunit_test_cmd --output ok
        ptyunit_test_cmd actual_arg >/dev/null
        assert_called_with ptyunit_test_cmd expected_arg
    " 2>&1)
    assert_contains "$out" "FAIL"

    test_that "fails when args do not match — shows actual"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        ptyunit_mock ptyunit_test_cmd --output ok
        ptyunit_test_cmd actual_arg >/dev/null
        assert_called_with ptyunit_test_cmd expected_arg
    " 2>&1)
    assert_contains "$out" "actual_arg"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_not_called failure"

    test_that "assert_not_called fails when mock was called"
    out=$(bash -c "
        source '$PTYUNIT_DIR/assert.sh'
        ptyunit_mock ptyunit_test_cmd --output ok
        ptyunit_test_cmd >/dev/null
        assert_not_called ptyunit_test_cmd
    " 2>&1)
    assert_contains "$out" "FAIL"
    assert_contains "$out" "1"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
describe "ptyunit_unmock for command mocks"

    test_that "unmocked command is no longer on PATH"
    ptyunit_mock ptyunit_unmock_test_cmd --output "mocked"
    assert_eq "mocked" "$(ptyunit_unmock_test_cmd)"
    ptyunit_unmock ptyunit_unmock_test_cmd
    # After unmock, the command should not be found
    result=0
    command -v ptyunit_unmock_test_cmd >/dev/null 2>&1 && result=1
    assert_eq "0" "$result"

end_describe

# ═════════════════════════════════════════════════════════════════════════════
_ext_fn_a() { echo "original_a"; }
_ext_fn_b() { echo "original_b"; }

describe "mock output vs exit-only paths"

    test_that "command mock with only exit code produces no output"
    ptyunit_mock ptyunit_test_cmd --exit 7
    result=$(ptyunit_test_cmd 2>/dev/null)
    assert_eq "" "$result"
    ptyunit_test_cmd 2>/dev/null; rc=$?
    assert_eq "7" "$rc"

    test_that "function mock with only exit code produces no output"
    ptyunit_mock _ext_fn_a --exit 3
    result=$(_ext_fn_a 2>/dev/null)
    assert_eq "" "$result"
    _ext_fn_a 2>/dev/null; rc=$?
    assert_eq "3" "$rc"

    test_that "mock_args with explicit call number retrieves that call"
    ptyunit_mock ptyunit_test_cmd --output ok
    ptyunit_test_cmd first_call >/dev/null
    ptyunit_test_cmd second_call >/dev/null
    ptyunit_test_cmd third_call >/dev/null
    result=$(mock_args ptyunit_test_cmd 2)
    assert_eq "second_call" "$result"

    test_that "function mock with no body and no output exits 0 silently"
    ptyunit_mock _ext_fn_b
    result=$(_ext_fn_b 2>/dev/null)
    assert_eq "" "$result"
    _ext_fn_b 2>/dev/null; rc=$?
    assert_eq "0" "$rc"

end_describe

ptyunit_test_summary
