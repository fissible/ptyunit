#!/usr/bin/env bash
# ptyunit/coverage.sh — Bash code coverage via PS4 trace
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#
#   cd /path/to/project
#   bash path/to/ptyunit/coverage.sh [--unit|--all] [--src=<dir>] [--report=<fmt>]
#
#   --src=<dir>     Source directory to measure (default: src/ or .)
#   --report=text   Plain text report to stdout (default)
#   --report=json   JSON report to stdout
#   --report=html   HTML report to coverage/index.html
#   --min=<N>       Exit 1 if total coverage < N% (for CI)
#
# ── How it works ──────────────────────────────────────────────────────────────
#
# Runs each test file with set -x and a custom PS4 that logs file:line.
# On bash 3.2 (macOS), BASH_XTRACEFD is not available, so xtrace goes to
# stderr. The wrapper redirects stderr to the trace file and captures
# stdout for test results.

set -u

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# PTYUNIT_HOME: public variable pointing to the ptyunit installation.
# Auto-detect from this script's directory if not already set.
# Always export so test subshells can source assert.sh via $PTYUNIT_HOME.
PTYUNIT_HOME="${PTYUNIT_HOME:-$PTYUNIT_DIR}"
if [[ ! -f "$PTYUNIT_HOME/assert.sh" ]]; then
    printf 'Error: PTYUNIT_HOME="%s" does not contain assert.sh\n' "$PTYUNIT_HOME" >&2
    printf 'Set PTYUNIT_HOME to the ptyunit installation directory and export it.\n' >&2
    exit 1
fi
export PTYUNIT_HOME

# ── Parse arguments ──────────────────────────────────────────────────────────

_cov_src=""
_cov_report="text"
_cov_min=0
_cov_mode="--all"

for _arg in "$@"; do
    case "$_arg" in
        --src=*)     _cov_src="${_arg#--src=}" ;;
        --report=*)  _cov_report="${_arg#--report=}" ;;
        --min=*)     _cov_min="${_arg#--min=}" ;;
        --unit|--integration|--all) _cov_mode="$_arg" ;;
    esac
done

if [[ -z "$_cov_src" ]]; then
    if [[ -d "src" ]]; then _cov_src="src"; else _cov_src="."; fi
fi

_cov_src="$(cd "$_cov_src" 2>/dev/null && pwd -P)" || {
    printf 'coverage: source directory not found: %s\n' "$_cov_src" >&2
    exit 1
}

if [[ "$(pwd -P)" == "$PTYUNIT_DIR" ]]; then
    _TESTS_DIR="$PTYUNIT_DIR/self-tests"
else
    _TESTS_DIR="$(pwd)/tests"
fi

# ── Set up trace ─────────────────────────────────────────────────────────────

_cov_trace=$(mktemp "${TMPDIR:-/tmp}/ptyunit-coverage.XXXXXX")
trap "rm -f '$_cov_trace'" EXIT
export PTYUNIT_COVERAGE_FILE="$_cov_trace"

if [[ "$_cov_mode" == "--unit" ]]; then
    printf 'Note: --unit skips integration tests; use --all for complete coverage.\n' >&2
fi

printf 'ptyunit coverage\n'
printf '  source: %s\n' "$_cov_src"
printf '  trace:  %s\n\n' "$_cov_trace"

# ── Run tests with tracing ───────────────────────────────────────────────────
#
# Each test file is run via a wrapper that:
#   1. Sets PS4 to log file:line
#   2. Enables set -x
#   3. Sources the test file
#   4. stderr (xtrace) goes to the trace file
#   5. stdout (test results) is captured for pass/fail parsing

_total_pass=0
_total_fail=0
_total_files=0
_failed_files=()

_run_cov_file() {
    local f="$1"
    local name
    name="$(basename "$f")"
    printf '  %s ... ' "$name"

    # Run test with xtrace: traces → fd 3 (trace file), stderr → /dev/null.
    # Using BASH_XTRACEFD keeps traces off fd 2, so assert.sh's run() helper
    # (which does 2>&1) cannot capture PS4 lines into $output.
    local out
    out=$(bash -c "
        exec 3>>'$_cov_trace'
        BASH_XTRACEFD=3
        PS4='+\${BASH_SOURCE:-?}:\${LINENO} '
        set -x
        source \"$f\"
    " 2>/dev/null)
    local rc=$?

    local passed total _summary
    _summary=$(printf '%s\n' "$out" | grep -oE '[0-9]+/[0-9]+ tests passed' | head -1)
    passed="${_summary%%/*}"
    total="${_summary#*/}"; total="${total%% *}"

    if (( rc == 3 )); then
        local skip_reason
        skip_reason=$(printf '%s\n' "$out" | grep -oE '\([^)]+\)' | head -1)
        printf 'SKIP%s\n' "${skip_reason:+ $skip_reason}"
    elif (( rc == 0 )); then
        (( _total_pass += ${passed:-0} ))
        (( _total_fail += $(( ${total:-0} - ${passed:-0} )) ))
        printf 'OK (%s/%s)\n' "${passed:-?}" "${total:-?}"
    else
        printf 'FAIL\n'
        printf '%s\n' "$out" | sed 's/^/    /'
        _failed_files+=("$name")
        (( _total_pass += ${passed:-0} ))
        (( _total_fail += $(( ${total:-0} - ${passed:-0} )) ))
    fi
    (( _total_files++ ))
}

_run_cov_suite() {
    local suite_dir="$1" label="$2"
    local files=()
    local f
    for f in "$suite_dir"/test-*.sh; do
        [ -f "$f" ] && files+=("$f")
    done
    if (( ${#files[@]} == 0 )); then return; fi

    printf '%s tests:\n' "$label"
    for f in "${files[@]}"; do
        _run_cov_file "$f"
    done
}

case "$_cov_mode" in
    --unit)        _run_cov_suite "$_TESTS_DIR/unit" "Unit" ;;
    --integration) _run_cov_suite "$_TESTS_DIR/integration" "Integration" ;;
    --all|*)
        _run_cov_suite "$_TESTS_DIR/unit" "Unit"
        _run_cov_suite "$_TESTS_DIR/integration" "Integration"
        ;;
esac

_local_total=$(( _total_pass + _total_fail ))
printf '\n%d/%d assertions passed across %d file(s)\n' \
    "$_total_pass" "$_local_total" "$_total_files"

if (( ${#_failed_files[@]} > 0 )); then
    printf 'Failed files:\n'
    for _ff in "${_failed_files[@]}"; do printf '  %s\n' "$_ff"; done
fi

_test_rc=0
(( _total_fail > 0 )) && _test_rc=1

# ── Post-process ─────────────────────────────────────────────────────────────

printf '\n'

python3 "$PTYUNIT_DIR/coverage_report.py" \
    --trace "$_cov_trace" \
    --src "$_cov_src" \
    --format "$_cov_report" \
    --min "$_cov_min"
_report_rc=$?

if (( _test_rc != 0 )); then exit "$_test_rc"; fi
exit "$_report_rc"
