#!/usr/bin/env bash
# self-tests/unit/test-mock-hardening.sh — Regression tests for mock.sh
# hardening (issues #39 re-mock leak, #40 name validation, #42 PATH restore).

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "re-mocking a function within one section (#39)"

    ptyunit_hardening_real_fn() { printf 'real'; }

    test_that "second mock in the same section wins"
    ptyunit_mock ptyunit_hardening_real_fn --output "m1" < /dev/null
    ptyunit_mock ptyunit_hardening_real_fn --output "m2" < /dev/null
    assert_eq "m2" "$(ptyunit_hardening_real_fn)"

    test_that "original function is restored at the next section boundary"
    assert_eq "real" "$(ptyunit_hardening_real_fn 2>&1)"

    test_that "registry holds the name once after re-mocking"
    ptyunit_mock ptyunit_hardening_real_fn --output "m1" < /dev/null
    ptyunit_mock ptyunit_hardening_real_fn --output "m2" < /dev/null
    assert_eq "1" "$(grep -c '^ptyunit_hardening_real_fn$' "$_PTYUNIT_MOCK_DIR/registry")"

    test_that "original function survives a second round of re-mocking"
    assert_eq "real" "$(ptyunit_hardening_real_fn 2>&1)"

# ═════════════════════════════════════════════════════════════════════════════
describe "mock name validation (#40)"

    test_that "rejects a name with path traversal"
    out=$(ptyunit_mock '../ptyunit_evil' 2>&1 < /dev/null); rc=$?
    assert_eq "2" "$rc"
    assert_contains "$out" "invalid mock name"

    test_that "rejects a name containing a space"
    out=$(ptyunit_mock 'git status' 2>&1 < /dev/null); rc=$?
    assert_eq "2" "$rc"
    assert_contains "$out" "invalid mock name"

    test_that "rejects a name containing shell metacharacters"
    out=$(ptyunit_mock 'x;touch /tmp/ptyunit_pwned' 2>&1 < /dev/null); rc=$?
    assert_eq "2" "$rc"
    assert_false "[[ -e /tmp/ptyunit_pwned ]]"

    test_that "accepts names with dots and dashes"
    ptyunit_mock docker-compose.v2 --output "ok" < /dev/null
    assert_eq "ok" "$(docker-compose.v2)"

# ═════════════════════════════════════════════════════════════════════════════
describe "PATH restoration (#42)"

    test_that "keeps PATH entries the test added after mocking"
    ptyunit_mock ptyunit_hardening_cmd --output "ok" < /dev/null
    PATH="/ptyunit-custom-bin:$PATH"

    test_that "custom entry still present, mock bin gone, after section boundary"
    assert_contains "$PATH" "/ptyunit-custom-bin:"
    assert_not_contains "$PATH" "ptyunit-mock"
    PATH="${PATH#/ptyunit-custom-bin:}"

ptyunit_test_summary
