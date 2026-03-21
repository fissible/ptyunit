#!/usr/bin/env bash
# ptyunit/run.sh — Discover and run all test files
#
# Usage: bash run.sh [--unit | --integration | --all] [--jobs N]
#        [--filter PATTERN] [--fail-fast] [--format pretty|tap|junit]
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
_filter=""
_name_filter=""
_fail_fast=0
_format="pretty"

_usage() {
    cat << 'USAGE'
Usage: bash run.sh [options]

Suites:
  --unit              Unit tests only (tests/unit/test-*.sh)
  --integration       Integration tests only (tests/integration/test-*.sh)
  --all               Both (default)

Filtering:
  --filter PATTERN    Only run files whose name contains PATTERN
  --name PATTERN      Only run test sections whose name contains PATTERN

Execution:
  --jobs N            Max parallel test files (default: number of CPU cores)
  --fail-fast         Stop after the first failure
  --debug             Same as --jobs 1 --verbose

Output:
  --format pretty     Human-readable (default)
  --format tap        TAP version 13
  --format junit      JUnit XML
  -v, --verbose       Show timing for every file

  NO_COLOR=1          Suppress color
  FORCE_COLOR=1       Force color in CI

  -h, --help          Show this help
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            _usage ;;
        --unit|--integration|--all)
            _mode="$1"; shift ;;
        --debug)
            _jobs=1; _verbose=1; shift ;;
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
        --filter)
            _filter="${2:-}"
            if [[ -z "$_filter" ]]; then
                printf 'Error: --filter requires a pattern\n' >&2; exit 2
            fi
            shift 2 ;;
        --filter=*)
            _filter="${1#--filter=}"; shift ;;
        --name)
            _name_filter="${2:-}"
            if [[ -z "$_name_filter" ]]; then
                printf 'Error: --name requires a pattern\n' >&2; exit 2
            fi
            shift 2 ;;
        --name=*)
            _name_filter="${1#--name=}"; shift ;;
        --fail-fast)
            _fail_fast=1; shift ;;
        --format)
            _format="${2:-}"
            if [[ -z "$_format" ]]; then
                printf 'Error: --format requires a value\n' >&2; exit 2
            fi
            shift 2 ;;
        --format=*)
            _format="${1#--format=}"; shift ;;
        *)
            printf 'Unknown flag: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# Validate --jobs value
if ! [[ "$_jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Error: --jobs requires a positive integer, got: %s\n' "$_jobs" >&2
    exit 2
fi

# Validate --format value
case "$_format" in
    pretty|tap|junit) ;;
    *) printf 'Error: unknown format: %s (expected pretty, tap, or junit)\n' "$_format" >&2; exit 2 ;;
esac

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

# Suite tracking for TAP/JUnit output
_suite_work_dirs=()
_suite_labels=()

# Fail-fast sentinel (file-based IPC for subshells)
_fail_sentinel=""
if (( _fail_fast )); then
    _fail_sentinel="${TMPDIR:-/tmp}/ptyunit-fail-$$"
fi

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
#   work_dir/<name>.res  — "rc passed total elapsed" on one line
#   work_dir/<name>.raw  — raw test output (for TAP/JUnit diagnostics)
_run_job() {
    local f="$1" setUp_file="$2" tearDown_file="$3" work_dir="$4" _col="${5:-0}"
    local name="${f##*/}"
    local out_f="$work_dir/$name.out"
    local res_f="$work_dir/$name.res"
    local raw_f="$work_dir/$name.raw"

    local _test_tmpdir
    _test_tmpdir=$(mktemp -d)
    export PTYUNIT_TEST_TMPDIR="$_test_tmpdir"

    # setUp
    if [[ -n "$setUp_file" ]]; then
        if ! bash "$setUp_file" > /dev/null 2>&1; then
            printf '  %-*s ... %s (setUp failed)\n' "$_col" "$name" "$_SKIP_LABEL" > "$out_f"
            printf '1 0 0 0.0\n' > "$res_f"
            printf 'setUp failed\n' > "$raw_f"
            [[ -n "$tearDown_file" ]] && bash "$tearDown_file" > /dev/null 2>&1
            rm -rf "$_test_tmpdir"
            if (( _fail_fast )) && [[ -n "${_fail_sentinel:-}" ]]; then
                touch "$_fail_sentinel"
            fi
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

    # Save raw output for TAP/JUnit diagnostics
    printf '%s\n' "$out" > "$raw_f"

    # rc=3 means the test file called ptyunit_skip / ptyunit_require_bash
    if (( rc == 3 )); then
        printf '  %-*s ... %s\n' "$_col" "$name" "${out:-SKIP}" > "$out_f"
        printf '3 0 0 %s\n' "$_raw_elapsed" > "$res_f"
        [[ -n "$tearDown_file" ]] && bash "$tearDown_file" > /dev/null 2>&1
        rm -rf "$_test_tmpdir"
        return
    fi

    local passed=0 total=0
    if [[ "$out" =~ ([0-9]+)/([0-9]+) ]]; then
        passed="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
    fi

    printf '%d %d %d %s\n' "$rc" "$passed" "$total" "$_raw_elapsed" > "$res_f"

    # Show timing if verbose OR the file took >= 1 second
    local _timing_str=""
    if (( _verbose )) || awk "BEGIN{exit ($_raw_elapsed >= 1.0) ? 0 : 1}" 2>/dev/null; then
        _timing_str=" in $_elapsed secs"
        if (( _verbose )) && [[ "$_elapsed" != "< 0.1" ]]; then
            _timing_str+=$(awk "BEGIN{printf \" (%.2f tests/second)\", $total / $_raw_elapsed}")
        fi
    fi

    if (( rc == 0 )); then
        printf '  %-*s ... %s (%d/%d)%s\n' \
            "$_col" "$name" "$_OK_LABEL" "$passed" "$total" "$_timing_str" > "$out_f"
    else
        {
            printf '  %-*s ... %s%s\n' "$_col" "$name" "$_FAIL_LABEL" "$_timing_str"
            while IFS= read -r _line; do
                printf '    %s\n' "$_line"
            done <<< "$out"
        } > "$out_f"
        # Signal fail-fast
        if (( _fail_fast )) && [[ -n "${_fail_sentinel:-}" ]]; then
            touch "$_fail_sentinel"
        fi
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

    # Apply --filter
    if [[ -n "$_filter" ]] && (( ${#files[@]} > 0 )); then
        local _filtered=()
        for f in "${files[@]}"; do
            local _n="${f##*/}"
            if [[ "$_n" == *"$_filter"* ]]; then
                _filtered+=("$f")
            fi
        done
        if (( ${#_filtered[@]} > 0 )); then
            files=("${_filtered[@]}")
        else
            files=()
        fi
    fi

    (( ${#files[@]} == 0 )) && return

    local _col=0
    for f in "${files[@]}"; do
        local _n="${f##*/}"
        (( ${#_n} > _col )) && _col=${#_n}
    done

    [[ "$_format" == "pretty" ]] && printf '\n%s tests:\n' "$label"

    local work_dir
    work_dir=$(mktemp -d)

    # Save file list for TAP/JUnit emission
    for f in "${files[@]}"; do
        printf '%s\n' "$f"
    done > "$work_dir/.file_list"

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
        # Check fail-fast after a worker finishes (token released)
        if (( _fail_fast )) && [[ -n "${_fail_sentinel:-}" ]] && [[ -f "$_fail_sentinel" ]]; then
            break
        fi
        (
            _run_job "$f" "$setUp_file" "$tearDown_file" "$work_dir" "$_col"
            printf 'x' >&4          # release slot
        ) &
    done

    wait                            # drain all remaining workers
    exec 4>&-

    # Print pretty results and aggregate counts
    for f in "${files[@]}"; do
        local name="${f##*/}"
        [[ "$_format" == "pretty" ]] && [[ -f "$work_dir/$name.out" ]] && cat "$work_dir/$name.out"
        if [[ -f "$work_dir/$name.res" ]]; then
            local rc passed total elapsed
            read -r rc passed total elapsed < "$work_dir/$name.res"
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

    # Show fail-fast notice
    if [[ "$_format" == "pretty" ]] && (( _fail_fast )) && [[ -n "${_fail_sentinel:-}" ]] && [[ -f "$_fail_sentinel" ]]; then
        printf '  [stopped: --fail-fast]\n'
    fi

    # Save or clean up work_dir
    if [[ "$_format" != "pretty" ]]; then
        _suite_work_dirs+=("$work_dir")
        _suite_labels+=("$label")
    else
        rm -rf "$work_dir"
    fi
}

# ── TAP output emitter ──────────────────────────────────────────────────────
_emit_tap() {
    printf 'TAP version 13\n'

    # Count total tests across all suites
    local total_tests=0 i
    for (( i=0; i < ${#_suite_work_dirs[@]}; i++ )); do
        local wd="${_suite_work_dirs[$i]}"
        while IFS= read -r _f; do
            (( total_tests++ )) || true
        done < "$wd/.file_list"
    done

    printf '1..%d\n' "$total_tests"

    local test_num=0
    for (( i=0; i < ${#_suite_work_dirs[@]}; i++ )); do
        local wd="${_suite_work_dirs[$i]}"
        while IFS= read -r _f; do
            local name="${_f##*/}"
            (( test_num++ )) || true

            if [[ ! -f "$wd/$name.res" ]]; then
                printf 'ok %d - %s # SKIP did not run\n' "$test_num" "$name"
                continue
            fi

            local rc passed total elapsed
            read -r rc passed total elapsed < "$wd/$name.res"

            if (( rc == 3 )); then
                printf 'ok %d - %s # SKIP\n' "$test_num" "$name"
            elif (( rc == 0 )); then
                printf 'ok %d - %s # %d/%d assertions passed\n' "$test_num" "$name" "$passed" "$total"
            else
                printf 'not ok %d - %s\n' "$test_num" "$name"
                printf '  ---\n'
                printf '  passed: %d\n  total: %d\n' "$passed" "$total"
                if [[ -f "$wd/$name.raw" ]]; then
                    printf '  output: |\n'
                    while IFS= read -r _line; do
                        printf '    %s\n' "$_line"
                    done < "$wd/$name.raw"
                fi
                printf '  ...\n'
            fi
        done < "$wd/.file_list"
    done
}

# ── JUnit XML output emitter ────────────────────────────────────────────────
_emit_junit() {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<testsuites>\n'

    local i
    for (( i=0; i < ${#_suite_work_dirs[@]}; i++ )); do
        local wd="${_suite_work_dirs[$i]}"
        local label="${_suite_labels[$i]}"
        local classname
        classname=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')

        local n_tests=0 n_fail=0 n_skip=0 total_time="0"

        # First pass: count totals
        while IFS= read -r _f; do
            local name="${_f##*/}"
            (( n_tests++ )) || true
            if [[ -f "$wd/$name.res" ]]; then
                local rc passed total elapsed
                read -r rc passed total elapsed < "$wd/$name.res"
                if (( rc == 3 )); then
                    (( n_skip++ )) || true
                elif (( rc != 0 )); then
                    (( n_fail++ )) || true
                fi
                total_time=$(awk "BEGIN{printf \"%.3f\", $total_time + $elapsed}")
            else
                (( n_skip++ )) || true
            fi
        done < "$wd/.file_list"

        printf '  <testsuite name="%s" tests="%d" failures="%d" skipped="%d" time="%s">\n' \
            "$label" "$n_tests" "$n_fail" "$n_skip" "$total_time"

        # Second pass: emit testcases
        while IFS= read -r _f; do
            local name="${_f##*/}"
            local esc_name="${name//&/&amp;}"
            esc_name="${esc_name//</&lt;}"
            esc_name="${esc_name//>/&gt;}"
            esc_name="${esc_name//\"/&quot;}"

            if [[ ! -f "$wd/$name.res" ]]; then
                printf '    <testcase name="%s" classname="%s" time="0">\n' "$esc_name" "$classname"
                printf '      <skipped message="did not run"/>\n'
                printf '    </testcase>\n'
                continue
            fi

            local rc passed total elapsed
            read -r rc passed total elapsed < "$wd/$name.res"

            printf '    <testcase name="%s" classname="%s" time="%s"' \
                "$esc_name" "$classname" "$elapsed"

            if (( rc == 3 )); then
                printf '>\n      <skipped/>\n    </testcase>\n'
            elif (( rc != 0 )); then
                printf '>\n      <failure message="%d/%d assertions passed">' "$passed" "$total"
                if [[ -f "$wd/$name.raw" ]]; then
                    local raw
                    raw=$(<"$wd/$name.raw")
                    raw="${raw//&/&amp;}"
                    raw="${raw//</&lt;}"
                    raw="${raw//>/&gt;}"
                    printf '%s' "$raw"
                fi
                printf '</failure>\n    </testcase>\n'
            else
                printf '/>\n'
            fi
        done < "$wd/.file_list"

        printf '  </testsuite>\n'
    done

    printf '</testsuites>\n'
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
if [[ "$_format" == "pretty" ]]; then
    if (( _jobs == 1 )); then
        printf 'ptyunit test runner (sequential)\n'
    else
        printf 'ptyunit test runner (%d workers)\n' "$_jobs"
    fi
fi

# Export name filter for test files (checked by ptyunit_test_begin)
if [[ -n "$_name_filter" ]]; then
    export PTYUNIT_FILTER_NAME="$_name_filter"
fi

_fail_fast_triggered=0

case "$_mode" in
    --unit)
        _run_suite "$TESTS_DIR/unit" "Unit"
        ;;
    --integration)
        if ! command -v python3 >/dev/null 2>&1; then
            [[ "$_format" == "pretty" ]] && printf '\nSkipping integration tests (python3 not found)\n'
        else
            _run_suite "$TESTS_DIR/integration" "Integration"
        fi
        ;;
    --all)
        _run_suite "$TESTS_DIR/unit" "Unit"
        if (( _fail_fast )) && [[ -n "${_fail_sentinel:-}" ]] && [[ -f "$_fail_sentinel" ]]; then
            _fail_fast_triggered=1
        fi
        if (( ! _fail_fast_triggered )); then
            if command -v python3 >/dev/null 2>&1; then
                _run_suite "$TESTS_DIR/integration" "Integration"
            else
                [[ "$_format" == "pretty" ]] && printf '\nSkipping integration tests (python3 not found)\n'
            fi
        else
            [[ "$_format" == "pretty" ]] && printf '\nSkipping integration tests (--fail-fast)\n'
        fi
        ;;
esac

# ── Output / Summary ─────────────────────────────────────────────────────────
case "$_format" in
    tap)
        _emit_tap
        ;;
    junit)
        _emit_junit
        ;;
    pretty)
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
        fi
        ;;
esac

# Clean up TAP/JUnit work dirs
if (( ${#_suite_work_dirs[@]} > 0 )); then
    for _wd in "${_suite_work_dirs[@]}"; do
        rm -rf "$_wd"
    done
fi

# Clean up fail-fast sentinel
if [[ -n "${_fail_sentinel:-}" ]]; then
    rm -f "$_fail_sentinel"
fi

# Exit code
if (( ${#_failed_files[@]} > 0 )); then
    exit 1
fi
exit 0
