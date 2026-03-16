#!/usr/bin/env bash
# ptyunit/run.sh — Discover and run all test files
#
# Usage: bash run.sh [--unit | --integration | --all]
#
# Unit tests:        tests/unit/test-*.sh        (pure bash, no PTY)
# Integration tests: tests/integration/test-*.sh (require Python 3 + PTY)
#
# Each test-*.sh should source assert.sh, run assertions, then call
# ptyunit_test_summary at the end.  run.sh aggregates total pass/fail
# across all files.

set -u

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$PTYUNIT_DIR/tests"

_mode="${1:---all}"
_total_pass=0
_total_fail=0
_total_files=0
_failed_files=()

_run_file() {
    local f="$1"
    local name
    name="$(basename "$f")"
    printf '  %s ... ' "$name"

    # Run test file in a subshell; capture output; check exit code
    local out
    out=$(bash "$f" 2>&1)
    local rc=$?

    if (( rc == 0 )); then
        # Extract pass count from summary line "OK  N/M"
        local passed total
        passed=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f1)
        total=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f2)
        (( _total_pass += ${passed:-0} ))
        (( _total_fail += $(( ${total:-0} - ${passed:-0} )) ))
        printf 'OK (%s/%s)\n' "${passed:-?}" "${total:-?}"
    else
        printf 'FAIL\n'
        printf '%s\n' "$out" | sed 's/^/    /'
        _failed_files+=("$name")
        # Try to extract counts
        local passed total
        passed=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f1)
        total=$(printf '%s\n' "$out" | grep -o '[0-9]*/[0-9]*' | head -1 | cut -d/ -f2)
        (( _total_pass += ${passed:-0} ))
        (( _total_fail += $(( ${total:-0} - ${passed:-0} )) ))
    fi
    (( _total_files++ ))
}

_run_suite() {
    local suite_dir="$1" label="$2"
    local files=()

    # Collect matching test files
    local f
    for f in "$suite_dir"/test-*.sh; do
        [ -f "$f" ] && files+=("$f")
    done

    if (( ${#files[@]} == 0 )); then
        return
    fi

    printf '\n%s tests:\n' "$label"
    for f in "${files[@]}"; do
        _run_file "$f"
    done
}

printf 'ptyunit test runner\n'

case "$_mode" in
    --unit)
        _run_suite "$TESTS_DIR/unit" "Unit"
        ;;
    --integration)
        if ! command -v python3 >/dev/null 2>&1; then
            printf '\nSkipping integration tests (python3 not found)\n'
        else
            _run_suite "$TESTS_DIR/integration" "Integration"
        fi
        ;;
    --all|*)
        _run_suite "$TESTS_DIR/unit" "Unit"
        if command -v python3 >/dev/null 2>&1; then
            _run_suite "$TESTS_DIR/integration" "Integration"
        else
            printf '\nSkipping integration tests (python3 not found)\n'
        fi
        ;;
esac

# ── Summary ───────────────────────────────────────────────────────────────────
local_total=$(( _total_pass + _total_fail ))
printf '\n─────────────────────────────────\n'
printf '%d/%d assertions passed across %d file(s)\n' \
    "$_total_pass" "$local_total" "$_total_files"

if (( ${#_failed_files[@]} > 0 )); then
    printf 'Failed files:\n'
    local_f=""
    for local_f in "${_failed_files[@]}"; do
        printf '  %s\n' "$local_f"
    done
    exit 1
fi
exit 0
