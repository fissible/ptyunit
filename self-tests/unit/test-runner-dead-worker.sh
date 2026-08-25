#!/usr/bin/env bash
# self-tests/unit/test-runner-dead-worker.sh — a worker that dies before writing
# its .res file must be reported as FAIL and must not deadlock or silently
# drop the file (#55).
#
# Fixtures kill the worker from setUp.sh: setUp runs as a direct child of the
# worker subshell, so `kill -9 $PPID` there takes the worker down before it can
# report or return its pool token.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

# Run a command with a wall-clock cap; sets _wd_out / _wd_rc. A run that hits
# the cap is killed and _wd_out gets a __WATCHDOG_TIMEOUT__ marker.
_run_with_watchdog() {
    local _limit="$1"; shift
    local _outf; _outf=$(mktemp)
    "$@" > "$_outf" 2>&1 &
    local _pid=$! _i=0
    while kill -0 "$_pid" 2>/dev/null; do
        if (( _i >= _limit )); then
            kill -9 "$_pid" 2>/dev/null
            printf '__WATCHDOG_TIMEOUT__\n' >> "$_outf"
            break
        fi
        sleep 1; (( _i++ ))
    done
    wait "$_pid" 2>/dev/null; _wd_rc=$?
    _wd_out=$(<"$_outf"); rm -f "$_outf"
}

_mk_suite() {   # _mk_suite <dir> <kill-on-nth-setUp> <file names...>
    local _dir="$1" _nth="$2"; shift 2
    mkdir -p "$_dir/tests/unit"
    local _f
    for _f in "$@"; do
        cat > "$_dir/tests/unit/$_f" << FIXTURE
source "$PTYUNIT_DIR/assert.sh"
assert_eq "x" "x" "$_f passes"
ptyunit_test_summary
FIXTURE
    done
    cat > "$_dir/tests/unit/setUp.sh" << FIXTURE
n=\$(cat "$_dir/count" 2>/dev/null || echo 0); n=\$(( n + 1 )); echo "\$n" > "$_dir/count"
(( n == $_nth )) && kill -9 \$PPID
exit 0
FIXTURE
}

# ═════════════════════════════════════════════════════════════════════════════
describe "worker killed while more files are queued (files > jobs)"

    _d1=$(mktemp -d); _mk_suite "$_d1" 2 test-a.sh test-b.sh test-c.sh
    _run_with_watchdog 25 bash -c "cd '$_d1' && bash '$PTYUNIT_DIR/run.sh' --unit --jobs 1"

    test_that "the suite completes instead of deadlocking on the pool semaphore"
    assert_not_contains "$_wd_out" "__WATCHDOG_TIMEOUT__"

    test_that "the dead worker's file is reported as FAIL with a reason"
    assert_match 'test-b\.sh +\.\.\. FAIL' "$_wd_out"
    assert_contains "$_wd_out" "worker did not report"

    test_that "the files after it still run"
    assert_match 'test-c\.sh +\.\.\. OK' "$_wd_out"

    test_that "totals count the dead file and the run exits 1"
    assert_contains "$_wd_out" "2/3 assertions passed across 3 file(s)"
    assert_contains "$_wd_out" "test-b.sh"
    assert_eq "1" "$_wd_rc"
    rm -rf "$_d1"

# ═════════════════════════════════════════════════════════════════════════════
describe "worker killed with no files queued (files <= jobs)"

    _d2=$(mktemp -d); _mk_suite "$_d2" 1 test-x.sh
    _run_with_watchdog 25 bash -c "cd '$_d2' && bash '$PTYUNIT_DIR/run.sh' --unit --jobs 4"

    test_that "the file is not silently dropped from the results"
    assert_not_contains "$_wd_out" "__WATCHDOG_TIMEOUT__"
    assert_match 'test-x\.sh +\.\.\. FAIL' "$_wd_out"
    assert_contains "$_wd_out" "0/1 assertions passed across 1 file(s)"
    assert_eq "1" "$_wd_rc"

    test_that "TAP output marks it not ok with the reason as a diagnostic"
    rm -f "$_d2/count"
    _run_with_watchdog 25 bash -c "cd '$_d2' && bash '$PTYUNIT_DIR/run.sh' --unit --jobs 4 --format tap"
    assert_contains "$_wd_out" "not ok 1 - test-x.sh"
    assert_contains "$_wd_out" "worker did not report"
    rm -rf "$_d2"

ptyunit_test_summary
