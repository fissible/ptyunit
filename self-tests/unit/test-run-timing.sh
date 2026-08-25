#!/usr/bin/env bash
# self-tests/unit/test-run-timing.sh — per-file elapsed-time computation in
# run.sh. A fast test on a coarse (integer-second) clock can straddle a second
# boundary and read as "1 second"; that must be reported as fast, not as
# "in 1.0 secs" (flaky CI on Alpine busybox `date`, bash 3.2/4.4 legs).
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── Required globals (run.sh has set -u; initialize before sourcing) ─────────
_verbose=0; _fail_fast=0; _fail_sentinel=""; _format="pretty"; _jobs=1; _filter=""
_OK_LABEL="OK"; _FAIL_LABEL="FAIL"; _SKIP_LABEL="SKIP"
_suite_work_dirs=(); _suite_labels=()
_total_pass=0; _total_fail=0; _total_files=0; _total_skip=0
_failed_files=(); _skipped_files=()

source "$PTYUNIT_DIR/run.sh"

# ═════════════════════════════════════════════════════════════════════════════
describe "_ptyunit_elapsed on a coarse (integer-second) clock"

    test_that "a 1-second delta is ambiguous (0.001–1.999 s) and reported as fast"
    assert_eq "0.0" "$(_ptyunit_elapsed 100 101)"

    test_that "a zero delta is fast"
    assert_eq "0.0" "$(_ptyunit_elapsed 100 100)"

    test_that "a 2-second delta is at least 1 s and is reported"
    assert_eq "2.0" "$(_ptyunit_elapsed 100 102)"

    test_that "a negative delta (clock step) clamps to fast"
    assert_eq "0.0" "$(_ptyunit_elapsed 105 100)"

# ═════════════════════════════════════════════════════════════════════════════
describe "_ptyunit_elapsed on a fractional clock"

    test_that "tenths are computed across a second boundary"
    assert_eq "1.2" "$(_ptyunit_elapsed 100.500000 101.700000)"

    test_that "a short interval across a boundary is not rounded up to a second"
    assert_eq "0.1" "$(_ptyunit_elapsed 100.950000 101.050000)"

    test_that "sub-tenth intervals are fast"
    assert_eq "0.0" "$(_ptyunit_elapsed 100.100000 100.150000)"

    test_that "short fractional parts are padded, not misread"
    assert_eq "0.5" "$(_ptyunit_elapsed 100.5 101)"

# ═════════════════════════════════════════════════════════════════════════════
describe "_ptyunit_now"

    test_that "returns integer seconds or seconds with a 6-digit fraction"
    _now=$(_ptyunit_now)
    assert_match '^[0-9]+(\.[0-9]{6})?$' "$_now"

    test_that "uses a sub-second clock when date supports %N, even on bash < 5"
    if [[ "$(date +%s%N 2>/dev/null)" =~ ^[0-9]{16,}$ ]]; then
        _now=$(_ptyunit_now)
        assert_match '^[0-9]+\.[0-9]{6}$' "$_now"
    else
        ptyunit_skip_test "date +%N unsupported on this host (coarse clock)"
    fi

ptyunit_test_summary
