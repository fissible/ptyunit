#!/usr/bin/env bash
# self-tests/unit/test-help.sh — Tests for help.sh infrastructure
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/help.sh"

# ── _help_index ───────────────────────────────────────────────────────────────

test_that "_help_index lists every topic name from _TOPICS"
_idx=$(_help_index)
for (( _i=0; _i<${#_TOPICS[@]}; _i+=2 )); do
    assert_contains "$_idx" "${_TOPICS[_i]}"
done

test_that "_help_index includes Where to start note"
assert_contains "$(_help_index)" "Where to start"

# ── _dispatch ─────────────────────────────────────────────────────────────────

test_that "_dispatch with no argument shows index (does not error)"
_out=$(_dispatch)
assert_eq "0" "$?"
assert_contains "$_out" "Where to start"

test_that "_dispatch with unknown topic exits 1"
( _dispatch "__no_such_topic__" ) 2>/dev/null
assert_eq "1" "$?"

test_that "_dispatch unknown topic message mentions ptyunit help"
_err=$( ( _dispatch "__bad__" ) 2>&1 )
assert_contains "$_err" "ptyunit help"

# ── _detect_install ───────────────────────────────────────────────────────────

test_that "_detect_install returns a recognised value"
_inst=$(_detect_install)
case "$_inst" in
    submodule|brew|bpkg) assert_eq "0" "0" ;;
    *) assert_eq "submodule|brew|bpkg" "$_inst" ;;
esac

# ── _help_coverage ────────────────────────────────────────────────────────────

test_that "_help_coverage exits 0"
_help_coverage >/dev/null
assert_eq "0" "$?"

test_that "_help_coverage output contains all three install variants"
_cov=$(_help_coverage)
assert_contains "$_cov" "tests/ptyunit/coverage.sh"
assert_contains "$_cov" "deps/bpkg/ptyunit/coverage.sh"
assert_contains "$_cov" "brew --prefix ptyunit"

test_that "_help_coverage output contains flags table"
_cov=$(_help_coverage)
assert_contains "$_cov" "--src="
assert_contains "$_cov" "--report="
assert_contains "$_cov" "--min=N"

test_that "_help_coverage output mentions .coverageignore"
assert_contains "$(_help_coverage)" ".coverageignore"

test_that "_help_coverage output mentions @pty_skip"
assert_contains "$(_help_coverage)" "@pty_skip"

# ── pty, mocking, params, describe ───────────────────────────────────────────

test_that "_help_pty exits 0 and mentions pty_run.py and pty_session.py"
_out=$(_help_pty)
assert_eq "0" "$?"
assert_contains "$_out" "pty_run.py"
assert_contains "$_out" "pty_session.py"

test_that "_help_mocking exits 0 and mentions ptyunit_mock and assert_called"
_out=$(_help_mocking)
assert_eq "0" "$?"
assert_contains "$_out" "ptyunit_mock"
assert_contains "$_out" "assert_called"

test_that "_help_params exits 0 and mentions test_each"
_out=$(_help_params)
assert_eq "0" "$?"
assert_contains "$_out" "test_each"

test_that "_help_describe exits 0 and mentions end_describe"
_out=$(_help_describe)
assert_eq "0" "$?"
assert_contains "$_out" "end_describe"

# ── _help_setup_teardown ──────────────────────────────────────────────────────

test_that "_help_setup_teardown exits 0 and mentions setUp.sh"
_ht_out=$(_help_setup_teardown)
assert_eq "0" "$?"
assert_contains "$_ht_out" "setUp.sh"
assert_contains "$_ht_out" "tearDown.sh"

test_that "_help_setup_teardown mentions PTYUNIT_TEST_TMPDIR"
assert_contains "$(_help_setup_teardown)" "PTYUNIT_TEST_TMPDIR"

# ── _help_filters ─────────────────────────────────────────────────────────────

test_that "_help_filters exits 0 and mentions --filter and --name"
_hf_out=$(_help_filters)
assert_eq "0" "$?"
assert_contains "$_hf_out" "--filter"
assert_contains "$_hf_out" "--name"

test_that "_help_filters explains combining both flags"
assert_contains "$(_help_filters)" "Combine"

# ── _help_formats ─────────────────────────────────────────────────────────────

test_that "_help_formats exits 0 and mentions tap and junit"
_hfmt_out=$(_help_formats)
assert_eq "0" "$?"
assert_contains "$_hfmt_out" "tap"
assert_contains "$_hfmt_out" "junit"

test_that "_help_formats mentions --verbose"
assert_contains "$(_help_formats)" "--verbose"

# ── _help_install ─────────────────────────────────────────────────────────────

test_that "_help_install exits 0 and mentions submodule and brew"
_hi_out=$(_help_install)
assert_eq "0" "$?"
assert_contains "$_hi_out" "submodule"
assert_contains "$_hi_out" "brew"

test_that "_help_install mentions bpkg and make test"
_hi_out=$(_help_install)
assert_contains "$_hi_out" "bpkg"
assert_contains "$_hi_out" "make test"

# ── _help_skip ────────────────────────────────────────────────────────────────

test_that "_help_skip exits 0 and mentions ptyunit_skip and ptyunit_require_bash"
_hs_out=$(_help_skip)
assert_eq "0" "$?"
assert_contains "$_hs_out" "ptyunit_skip"
assert_contains "$_hs_out" "ptyunit_require_bash"

# ── _help_matrix ──────────────────────────────────────────────────────────────

test_that "_help_matrix exits 0 and mentions docker/run-matrix.sh"
_hm_out=$(_help_matrix)
assert_eq "0" "$?"
assert_contains "$_hm_out" "run-matrix.sh"
assert_contains "$_hm_out" "Docker"

# ── registry / function sync ──────────────────────────────────────────────────

test_that "every topic in _TOPICS has a corresponding _help_<name> function"
_i=0
while (( _i < ${#_TOPICS[@]} )); do
    _tname="${_TOPICS[$_i]}"
    _fn="_help_${_tname//-/_}"
    if ! declare -f "$_fn" >/dev/null 2>&1; then
        assert_eq "function exists" "missing: $_fn"
    fi
    _i=$(( _i + 2 ))
done

ptyunit_test_summary
