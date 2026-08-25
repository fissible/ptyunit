#!/usr/bin/env bash
# self-tests/unit/test-coverage-bash-guard.sh — coverage.sh must refuse to run
# when the `bash` it would trace with lacks BASH_XTRACEFD (< 4.1), instead of
# silently reporting 0% (#43).
#
# Needs a bash < 4.1 on the host (macOS /bin/bash). Skipped elsewhere.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

_old_bash=""
for _cand in /bin/bash "$(command -v bash)"; do
    _v=$("$_cand" -c 'printf "%s%02d" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null || echo 999)
    if (( 10#$_v < 401 )); then _old_bash="$_cand"; break; fi
done

describe "coverage.sh bash version guard (#43)"

    test_that "exits 2 with a clear message when PATH bash is older than 4.1"
    if [[ -z "$_old_bash" ]]; then
        ptyunit_skip_test "no bash < 4.1 on this host"
    else
        _bindir=$(mktemp -d "${TMPDIR:-/tmp}/ptyunit-oldbash.XXXXXX")
        ln -s "$_old_bash" "$_bindir/bash"
        _out=$(cd "$PTYUNIT_DIR" && PATH="$_bindir:$PATH" "$_old_bash" coverage.sh --unit 2>&1); _rc=$?
        rm -rf "$_bindir"
        assert_eq "2" "$_rc"
        assert_contains "$_out" "bash 4.1"
        assert_not_contains "$_out" "ptyunit coverage"
    fi

ptyunit_test_summary
