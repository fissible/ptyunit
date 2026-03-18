#!/usr/bin/env bash
# ptyunit/run.sh — Discover and run all test files
#
# Usage: bash run.sh [--unit | --integration | --all] [--jobs N]
#        bash tests/ptyunit/run.sh [--unit | --integration | --all] [--jobs N]
#
# Context detection (no wrapper needed):
#   - Run from ptyunit's own root  → discovers self-tests/unit/ and self-tests/integration/
#   - Run from any other directory → discovers <pwd>/tests/unit/ and <pwd>/tests/integration/
#
# Unit tests:        <tests>/unit/test-*.sh        (pure bash, no PTY)
# Integration tests: <tests>/integration/test-*.sh (require Python 3 + PTY)
#
# Each test-*.sh should source assert.sh, run assertions, then call
# ptyunit_test_summary at the end.
#
# Jobs:
#   Tests run in a streaming worker pool. --jobs N (default: nproc || 4) sets
#   the concurrency limit. Jobs start as soon as a slot is free — the scanner
#   and workers run interleaved, not collect-then-run. Use --jobs 1 for
#   sequential execution (useful for debugging).
#
# setUp / tearDown:
#   Place setUp.sh and/or tearDown.sh alongside test-*.sh files in the suite
#   directory. setUp.sh runs before each test file; tearDown.sh runs after,
#   even if the test failed. Both receive PTYUNIT_TEST_TMPDIR — a per-test
#   temporary directory created and cleaned up by the runner.
#   If setUp.sh exits non-zero, the test file is skipped (counts as failure).
#
# Color:
#   Output is colorized when stdout is a TTY. Set NO_COLOR=1 to suppress.
#   Set FORCE_COLOR=1 to enable even when stdout is not a TTY (e.g. CI).

set -u

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ "$(pwd -P)" == "$PTYUNIT_DIR" ]]; then
    TESTS_DIR="$PTYUNIT_DIR/self-tests"
else
    TESTS_DIR="$(pwd)/tests"
fi

# ── Flag parsing ──────────────────────────────────────────────────────────────
_mode="--all"
_jobs=$(nproc 2>/dev/null || echo 4)
_verbose=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit|--integration|--all)
            _mode="$1"; shift ;;
        --debug)
            _jobs=1; shift ;;
        --verbose|-v)
            _verbose=1; shift ;;
        --jobs)
            _jobs="${2:-}"
            if [[ -z "$_jobs" ]]; then
                printf 'Error: --jobs requires a value\n' >&2; exit 2
            fi
            shift 2 ;;
        --jobs=*)
            _jobs="${1#--jobs=}"; shift ;;
        *)
            printf 'Unknown flag: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# Validate --jobs value
if ! [[ "$_jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Error: --jobs requires a positive integer, got: %s\n' "$_jobs" >&2
    exit 2
fi

# ── Color setup ───────────────────────────────────────────────────────────────
_use_color=0
if [[ -n "${FORCE_COLOR:-}" && -z "${NO_COLOR:-}" ]]; then
    _use_color=1
elif [[ -z "${NO_COLOR:-}" ]] && [ -t 1 ]; then
    _use_color=1
fi

if (( _use_color )); then
    _OK_LABEL=$'\033[0;32mOK\033[0m'
    _FAIL_LABEL=$'\033[0;31mFAIL\033[0m'
    _SKIP_LABEL=$'\033[0;33mSKIP\033[0m'
else
    _OK_LABEL='OK'
    _FAIL_LABEL='FAIL'
    _SKIP_LABEL='SKIP'
fi

# ── Counters ──────────────────────────────────────────────────────────────────
_total_pass=0
_total_fail=0
_total_files=0
_total_skip=0
_failed_files=()
_skipped_files=()

# ── Timing helper ─────────────────────────────────────────────────────────────
_ptyunit_now() {
    if [[ "${BASH_VERSINFO[0]}" -ge 5 ]]; then
        printf '%s' "${EPOCHREALTIME}"
    else
        date +%s
    fi
}

# ── Worker: run one test file, write results to work_dir ─────────────────────
# Called inside a background subshell. Writes:
#   work_dir/<name>.out  — formatted output line(s) for this file
#   work_dir/<name>.res  — "rc passed total" on one line
_run_job() {
    local f="$1" setUp_file="$2" tearDown_file="$3" work_dir="$4"
    local name="${f##*/}"
    local out_f="$work_dir/$name.out"
    local res_f="$work_dir/$name.res"

    local _test_tmpdir
    _test_tmpdir=$(mktemp -d)
    export PTYUNIT_TEST_TMPDIR="$_test_tmpdir"

    # setUp
    if [[ -n "$setUp_file" ]]; then
        if ! bash "$setUp_file" > /dev/null 2>&1; then
            printf '  %s ... %s (setUp failed)\n' "$name" "$_SKIP_LABEL" > "$out_f"
            printf '1 0 0\n' > "$res_f"
            [[ -n "$tearDown_file" ]] && bash "$tearDown_file" > /dev/null 2>&1
            rm -rf "$_test_tmpdir"
            return
        fi
    fi

    local _t0 _t1 _elapsed
    _t0=$(_ptyunit_now)
    local out
    out=$(bash "$f" 2>&1)
    local rc=$?
    _t1=$(_ptyunit_now)
    local _raw_elapsed
    _raw_elapsed=$(awk "BEGIN{printf \"%.1f\", $_t1 - $_t0}")
    if [[ "$_raw_elapsed" == "0.0" ]]; then
        _elapsed="< 0.1"
    else
        _elapsed="$_raw_elapsed"
    fi

    # rc=3 means the test file called ptyunit_skip / ptyunit_require_bash
    if (( rc == 3 )); then
        printf '  %s ... %s\n' "$name" "${out:-SKIP}" > "$out_f"
        printf '3 0 0\n' > "$res_f"
        [[ -n "$tearDown_file" ]] && bash "$tearDown_file" > /dev/null 2>&1
        rm -rf "$_test_tmpdir"
        return
    fi

    local passed=0 total=0
    if [[ "$out" =~ ([0-9]+)/([0-9]+) ]]; then
        passed="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
    fi

    printf '%d %d %d\n' "$rc" "$passed" "$total" > "$res_f"

    local _aps=""
    if (( _verbose )) && [[ "$_elapsed" != "< 0.1" ]]; then
        _aps=$(awk "BEGIN{printf \" (%.2f tests/second)\", $total / $_raw_elapsed}")
    fi

    if (( rc == 0 )); then
        printf '  %s ... %s (%d/%d) in %s secs%s\n' \
            "$name" "$_OK_LABEL" "$passed" "$total" "$_elapsed" "$_aps" > "$out_f"
    else
        {
            printf '  %s ... %s in %s secs\n' "$name" "$_FAIL_LABEL" "$_elapsed"
            while IFS= read -r _line; do
                printf '    %s\n' "$_line"
            done <<< "$out"
        } > "$out_f"
    fi

    # tearDown always runs
    if [[ -n "$tearDown_file" ]]; then
        bash "$tearDown_file" > /dev/null 2>&1
    fi

    rm -rf "$_test_tmpdir"
}

# ── Suite runner: streaming worker pool ──────────────────────────────────────
# Uses an fd-based semaphore for bash 3.2-compatible bounded parallelism.
# Jobs start as soon as a slot opens — scanner and workers are interleaved.
_run_suite() {
    local suite_dir="$1" label="$2"
    local setUp_file="" tearDown_file=""

    [[ -f "$suite_dir/setUp.sh"    ]] && setUp_file="$suite_dir/setUp.sh"
    [[ -f "$suite_dir/tearDown.sh" ]] && tearDown_file="$suite_dir/tearDown.sh"

    local files=()
    local f
    for f in "$suite_dir"/test-*.sh; do
        [ -f "$f" ] && files+=("$f")
    done

    (( ${#files[@]} == 0 )) && return

    printf '\n%s tests:\n' "$label"

    local work_dir
    work_dir=$(mktemp -d)

    # fd-based semaphore: pre-fill with _jobs tokens.
    # Each worker consumes one token before starting and returns one on exit.
    # read blocks when the pipe is empty, giving us bounded parallelism without
    # polling. Compatible with bash 3.2+ (no wait -n required).
    local _sem
    _sem=$(mktemp -u)
    mkfifo "$_sem"
    exec 4<>"$_sem"
    rm -f "$_sem"  # safe once fd is open

    local i
    for (( i=0; i<_jobs; i++ )); do printf 'x' >&4; done

    for f in "${files[@]}"; do
        read -r -n1 -u4 _tok        # acquire slot (blocks when pool is full)
        (
            _run_job "$f" "$setUp_file" "$tearDown_file" "$work_dir"
            printf 'x' >&4          # release slot
        ) &
    done

    wait                            # drain all remaining workers
    exec 4>&-

    # Print results in original file order and aggregate counts
    for f in "${files[@]}"; do
        local name="${f##*/}"
        [[ -f "$work_dir/$name.out" ]] && cat "$work_dir/$name.out"
        if [[ -f "$work_dir/$name.res" ]]; then
            local rc passed total
            read -r rc passed total < "$work_dir/$name.res"
            if (( rc == 3 )); then
                (( _total_skip++ )) || true
                _skipped_files+=("$name")
            else
                (( _total_pass += passed )) || true
                (( _total_fail += total - passed )) || true
                (( _total_files++ )) || true
                if (( rc != 0 )); then
                    _failed_files+=("$name")
                fi
            fi
        fi
    done

    rm -rf "$work_dir"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
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
    --all)
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

if (( _total_skip > 0 )); then
    printf 'Skipped: %d file(s)\n' "$_total_skip"
    for local_f in "${_skipped_files[@]}"; do
        printf '  %s\n' "$local_f"
    done
fi

if (( ${#_failed_files[@]} > 0 )); then
    printf 'Failed files:\n'
    for local_f in "${_failed_files[@]}"; do
        printf '  %s\n' "$local_f"
    done
    exit 1
fi
exit 0
