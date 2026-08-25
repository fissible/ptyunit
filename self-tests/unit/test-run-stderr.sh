#!/usr/bin/env bash
# self-tests/unit/test-run-stderr.sh — run --separate-stderr, $stderr,
# assert_success / assert_failure (#48)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

_in_subshell() {
    bash -c "source '$PTYUNIT_DIR/assert.sh'; $1; ptyunit_test_summary" 2>&1
}

_both_streams() { echo "to-stdout"; echo "to-stderr" >&2; return 3; }

# ═════════════════════════════════════════════════════════════════════════════
describe "run --separate-stderr"

    test_that "stdout goes to \$output, stderr to \$stderr, exit code to \$status"
    run --separate-stderr _both_streams
    assert_eq "to-stdout" "$output"
    assert_eq "to-stderr" "$stderr"
    assert_eq "3" "$status"
    assert_eq "to-stdout" "${lines[0]}"

    test_that "default mode still merges both streams into \$output"
    run _both_streams
    assert_contains "$output" "to-stdout"
    assert_contains "$output" "to-stderr"
    assert_eq "3" "$status"

    test_that "default mode leaves \$stderr empty (set -u safe)"
    run _both_streams
    assert_eq "" "$stderr"

    test_that "separate mode with no stderr output yields empty \$stderr"
    run --separate-stderr echo "only-out"
    assert_eq "only-out" "$output"
    assert_eq "" "$stderr"
    assert_eq "0" "$status"

# ═════════════════════════════════════════════════════════════════════════════
describe "assert_success / assert_failure"

    test_that "assert_success passes when \$status is 0"
    run true
    assert_success

    test_that "assert_failure passes on any non-zero status"
    run _both_streams
    assert_failure

    test_that "assert_failure with an expected code"
    run _both_streams
    assert_failure 3

    test_that "assert_success fails and reports the status and output"
    out=$(_in_subshell '_f() { echo boom; return 2; }; run _f; assert_success')
    assert_contains "$out" "FAIL"
    assert_contains "$out" "status 2"
    assert_contains "$out" "boom"

    test_that "assert_failure fails when the command succeeded"
    out=$(_in_subshell 'run true; assert_failure')
    assert_contains "$out" "FAIL"
    assert_contains "$out" "status 0"

    test_that "assert_failure N fails when the status differs"
    out=$(_in_subshell '_f() { return 3; }; run _f; assert_failure 4')
    assert_contains "$out" "FAIL"
    assert_contains "$out" "expected status 4"
    assert_contains "$out" "got status 3"

ptyunit_test_summary
