#!/usr/bin/env bash
# self-tests/unit/test-run-py-internals.sh — Direct coverage for _run_py_job and _run_py_suite
# Skipped automatically when python3 or pytest are unavailable.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

command -v python3 >/dev/null 2>&1             || ptyunit_skip "python3 not available"
python3 -c "import pytest" 2>/dev/null         || ptyunit_skip "pytest not available"

# ── Pre-initialize run.sh globals (set -u requires these before sourcing) ─────
_verbose=0; _fail_fast=0; _fail_sentinel=""; _format="pretty"; _jobs=1; _filter=""
_OK_LABEL="OK"; _FAIL_LABEL="FAIL"; _SKIP_LABEL="SKIP"
_suite_work_dirs=(); _suite_labels=()
_total_pass=0; _total_fail=0; _total_files=0; _total_skip=0
_failed_files=(); _skipped_files=()

source "$PTYUNIT_DIR/run.sh"

# ── Per-test setup/teardown ───────────────────────────────────────────────────
_py_ws=""; _wd=""
ptyunit_setup() {
    _verbose=0; _fail_fast=0; _fail_sentinel=""; _format="pretty"; _jobs=1; _filter=""
    _OK_LABEL="OK"; _FAIL_LABEL="FAIL"; _SKIP_LABEL="SKIP"
    _total_pass=0; _total_fail=0; _total_files=0; _total_skip=0
    _failed_files=(); _skipped_files=(); _suite_work_dirs=(); _suite_labels=()
    _py_ws=$(mktemp -d)
    _wd=$(mktemp -d)
}
ptyunit_teardown() {
    [[ -n "$_py_ws" ]] && rm -rf "$_py_ws"
    [[ -n "$_wd"    ]] && rm -rf "$_wd"
}

# ── _run_py_job: passing tests ────────────────────────────────────────────────

test_that "_run_py_job writes rc=0 .res for a passing test file"
printf 'def test_pass(): assert True\n' > "$_py_ws/test_ok.py"
_run_py_job "$_py_ws/test_ok.py" "$_wd" 10
read -r _rc _passed _total _e < "$_wd/test_ok.py.res"
assert_eq "0"  "$_rc"
assert_eq "1"  "$_passed"
assert_eq "1"  "$_total"

test_that "_run_py_job writes OK output line for passing tests"
printf 'def test_a(): assert True\ndef test_b(): assert True\n' > "$_py_ws/test_two.py"
_run_py_job "$_py_ws/test_two.py" "$_wd" 12
_out=$(cat "$_wd/test_two.py.out")
assert_contains "$_out" "OK"
assert_contains "$_out" "2/2"

test_that "_run_py_job writes elapsed timing when verbose"
_verbose=1
printf 'def test_v(): assert True\n' > "$_py_ws/test_verbose.py"
_run_py_job "$_py_ws/test_verbose.py" "$_wd" 15
assert_contains "$(cat "$_wd/test_verbose.py.out")" " in "

# ── _run_py_job: failing tests ────────────────────────────────────────────────

test_that "_run_py_job writes non-zero rc for a failing test file"
printf 'def test_fail(): assert False\n' > "$_py_ws/test_bad.py"
_run_py_job "$_py_ws/test_bad.py" "$_wd" 10
read -r _rc _passed _total _e < "$_wd/test_bad.py.res"
assert_not_eq "0" "$_rc"
assert_eq "0" "$_passed"
assert_eq "1" "$_total"

test_that "_run_py_job writes FAIL output line for a failing test file"
printf 'def test_fail(): assert False\n' > "$_py_ws/test_bad.py"
_run_py_job "$_py_ws/test_bad.py" "$_wd" 10
assert_contains "$(cat "$_wd/test_bad.py.out")" "FAIL"

test_that "_run_py_job writes .raw output for a failing test file"
printf 'def test_fail(): assert False\n' > "$_py_ws/test_bad.py"
_run_py_job "$_py_ws/test_bad.py" "$_wd" 10
assert_file_exists "$_wd/test_bad.py.raw"

test_that "_run_py_job touches fail sentinel when fail-fast is active"
printf 'def test_fail(): assert False\n' > "$_py_ws/test_bad.py"
_fail_fast=1
_fail_sentinel="$_wd/.sentinel"
_run_py_job "$_py_ws/test_bad.py" "$_wd" 10
assert_file_exists "$_wd/.sentinel"

# ── _run_py_suite ─────────────────────────────────────────────────────────────

test_that "_run_py_suite accumulates pass counts across files"
printf 'def test_p1(): assert True\n' > "$_py_ws/test_s1.py"
printf 'def test_p2(): assert True\n' > "$_py_ws/test_s2.py"
_run_py_suite "$_py_ws" "TestSuite"
assert_eq "2" "$_total_pass"
assert_eq "2" "$_total_files"

test_that "_run_py_suite accumulates fail count for failing file"
printf 'def test_bad(): assert False\n' > "$_py_ws/test_fail_s.py"
_run_py_suite "$_py_ws" "TestSuite"
assert_not_eq "0" "$_total_fail"

test_that "_run_py_suite respects --filter"
printf 'def test_x(): assert True\n' > "$_py_ws/test_alpha.py"
printf 'def test_y(): assert True\n' > "$_py_ws/test_beta.py"
_filter="alpha"
_run_py_suite "$_py_ws" "Filtered"
assert_eq "1" "$_total_files"

test_that "_run_py_suite saves work_dir in tap format"
printf 'def test_t(): assert True\n' > "$_py_ws/test_tap.py"
_format="tap"
_run_py_suite "$_py_ws" "Tap"
assert_eq "1" "${#_suite_work_dirs[@]}"
rm -rf "${_suite_work_dirs[@]}"

test_that "_run_py_suite returns silently when no .py files exist"
_empty=$(mktemp -d)
_run_py_suite "$_empty" "Empty"
assert_eq "0" "$_total_files"
rm -rf "$_empty"

ptyunit_test_summary
