#!/usr/bin/env bash
# run-showdown.sh — Head-to-head benchmark: ptyunit vs bats-core
#
# Runs the same logical tests in both frameworks and compares:
#   - Pass/fail alignment (do they agree?)
#   - Wall-clock time
#   - Peak memory (RSS via /usr/bin/time)
#   - Test count

set -u

SHOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTYUNIT_DIR="$(cd "$SHOW_DIR/../.." && pwd)"

# ── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD=$'\033[1m'
    GREEN=$'\033[0;32m'
    RED=$'\033[0;31m'
    CYAN=$'\033[0;36m'
    YELLOW=$'\033[0;33m'
    RESET=$'\033[0m'
else
    BOLD="" GREEN="" RED="" CYAN="" YELLOW="" RESET=""
fi

_header() { printf '\n%s══ %s ══%s\n' "$BOLD" "$1" "$RESET"; }
_ok()     { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
_fail()   { printf '%s✗%s %s\n' "$RED" "$RESET" "$1"; }
_info()   { printf '%s→%s %s\n' "$CYAN" "$RESET" "$1"; }
_warn()   { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$1"; }

# ── Preflight ────────────────────────────────────────────────────────────────
_header "Preflight"

if ! command -v bats >/dev/null 2>&1; then
    _fail "bats-core not found. Install: brew install bats-core"
    exit 1
fi
_ok "bats-core $(bats --version)"
_ok "bash ${BASH_VERSION}"
_ok "ptyunit at $PTYUNIT_DIR"

if [[ ! -d "$SHOW_DIR/bats-libs/bats-assert" ]]; then
    _fail "bats helper libraries not found. Run:"
    printf '  cd %s/bats-libs\n' "$SHOW_DIR"
    printf '  git clone https://github.com/bats-core/bats-support.git\n'
    printf '  git clone https://github.com/bats-core/bats-assert.git\n'
    exit 1
fi
_ok "bats-assert loaded"

# ── Helper: run with timing and memory ───────────────────────────────────────
_benchmark() {
    local label="$1"; shift
    local time_file
    time_file=$(mktemp)

    # Use GNU time if available (more detailed), else builtin
    local mem_kb="n/a"
    local output exit_code

    if command -v gtime >/dev/null 2>&1; then
        # GNU time via Homebrew (brew install gnu-time)
        output=$(gtime -v "$@" 2>"$time_file") || true
        exit_code=${PIPESTATUS[0]:-$?}
        mem_kb=$(grep "Maximum resident" "$time_file" | awk '{print $NF}')
    elif /usr/bin/time -l true 2>/dev/null; then
        # macOS /usr/bin/time
        output=$(/usr/bin/time -l "$@" 2>"$time_file") || true
        exit_code=${PIPESTATUS[0]:-$?}
        # macOS reports bytes, convert to KB
        local mem_bytes
        mem_bytes=$(grep "maximum resident" "$time_file" | awk '{print $1}')
        if [[ -n "$mem_bytes" ]]; then
            mem_kb=$(( mem_bytes / 1024 ))
        fi
    else
        output=$("$@" 2>/dev/null) || true
        exit_code=$?
    fi

    rm -f "$time_file"

    # Extract test count from output
    local test_count="?"
    if [[ "$output" =~ ([0-9]+)/([0-9]+) ]]; then
        test_count="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    elif [[ "$output" =~ ([0-9]+)\ tests ]]; then
        test_count="${BASH_REMATCH[1]}"
    fi

    printf '%s' "$label"
    printf '|%s' "$exit_code"
    printf '|%s' "$test_count"
    printf '|%s' "$mem_kb"
    printf '|%s' "$output"
    printf '\n'
}

# ── Run ptyunit ──────────────────────────────────────────────────────────────
_header "Running ptyunit"

_ptyunit_results=$(mktemp)
_ptyunit_t0=$(date +%s)

for f in "$SHOW_DIR/ptyunit"/test-*.sh; do
    name="${f##*/}"
    name="${name%.sh}"
    _info "Running $name"
    _t0=$(date +%s%N 2>/dev/null || date +%s)
    out=$(bash "$f" 2>&1)
    rc=$?
    _t1=$(date +%s%N 2>/dev/null || date +%s)

    # Parse pass/total
    passed=0 total=0
    if [[ "$out" =~ ([0-9]+)/([0-9]+) ]]; then
        passed="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
    fi

    # Compute elapsed (nanoseconds if available, else seconds)
    if [[ "$_t0" =~ [0-9]{10,} ]]; then
        elapsed_ms=$(( (_t1 - _t0) / 1000000 ))
    else
        elapsed_ms=$(( (_t1 - _t0) * 1000 ))
    fi

    printf '%s|%d|%d|%d|%d\n' "$name" "$rc" "$passed" "$total" "$elapsed_ms" >> "$_ptyunit_results"

    if (( rc == 0 )); then
        _ok "$name: $passed/$total passed (${elapsed_ms}ms)"
    else
        _fail "$name: $passed/$total passed (${elapsed_ms}ms)"
    fi
done

_ptyunit_t1=$(date +%s)
_ptyunit_wall=$(( _ptyunit_t1 - _ptyunit_t0 ))

# ── Run bats ─────────────────────────────────────────────────────────────────
_header "Running bats-core"

_bats_results=$(mktemp)
_bats_t0=$(date +%s)

for f in "$SHOW_DIR/bats"/test-*.bats; do
    name="${f##*/}"
    name="${name%.bats}"
    _info "Running $name"
    _t0=$(date +%s%N 2>/dev/null || date +%s)
    out=$(bats --no-tempdir-cleanup "$f" 2>&1)
    rc=$?
    _t1=$(date +%s%N 2>/dev/null || date +%s)

    # Parse bats output (TAP format when captured)
    passed=0 total=0 failures=0 skipped=0
    # Try pretty-format summary first: "N tests, M failures"
    if [[ "$out" =~ ([0-9]+)\ tests?,\ ([0-9]+)\ failures? ]]; then
        total="${BASH_REMATCH[1]}"
        failures="${BASH_REMATCH[2]}"
        passed=$(( total - failures ))
        if [[ "$out" =~ ([0-9]+)\ skipped ]]; then
            skipped="${BASH_REMATCH[1]}"
        fi
    else
        # Parse TAP: count "ok" and "not ok" lines, check plan "1..N"
        if [[ "$out" =~ 1\.\.([0-9]+) ]]; then
            total="${BASH_REMATCH[1]}"
        fi
        while IFS= read -r _bline; do
            case "$_bline" in
                "ok "*)     (( passed++ )) || true ;;
                "not ok "*) (( failures++ )) || true ;;
            esac
            [[ "$_bline" == *"# skip"* || "$_bline" == *"# SKIP"* ]] && (( skipped++ )) || true
        done <<< "$out"
    fi

    if [[ "$_t0" =~ [0-9]{10,} ]]; then
        elapsed_ms=$(( (_t1 - _t0) / 1000000 ))
    else
        elapsed_ms=$(( (_t1 - _t0) * 1000 ))
    fi

    printf '%s|%d|%d|%d|%d|%d\n' "$name" "$rc" "$passed" "$total" "$elapsed_ms" "$skipped" >> "$_bats_results"

    if (( rc == 0 )); then
        _ok "$name: $passed/$total passed (${elapsed_ms}ms)"
    else
        _fail "$name: $passed/$total passed, $failures failed (${elapsed_ms}ms)"
    fi
done

_bats_t1=$(date +%s)
_bats_wall=$(( _bats_t1 - _bats_t0 ))

# ── Comparison ───────────────────────────────────────────────────────────────
_header "Results"

printf '\n'
printf '%s%-20s  %8s  %8s  %10s  %10s%s\n' "$BOLD" "Suite" "ptyunit" "bats" "pty (ms)" "bats (ms)" "$RESET"
printf '%-20s  %8s  %8s  %10s  %10s\n' "────────────────────" "────────" "────────" "──────────" "──────────"

_pty_total_pass=0 _pty_total_tests=0 _pty_total_ms=0
_bats_total_pass=0 _bats_total_tests=0 _bats_total_ms=0
_aligned=0 _misaligned=0

while IFS='|' read -r name rc passed total elapsed_ms; do
    _pty_total_pass=$(( _pty_total_pass + passed ))
    _pty_total_tests=$(( _pty_total_tests + total ))
    _pty_total_ms=$(( _pty_total_ms + elapsed_ms ))

    # Find matching bats result
    bats_line=$(grep "^$name|" "$_bats_results" 2>/dev/null || true)
    if [[ -n "$bats_line" ]]; then
        IFS='|' read -r _ brc bpassed btotal belapsed_ms bskipped <<< "$bats_line"
        _bats_total_pass=$(( _bats_total_pass + bpassed ))
        _bats_total_tests=$(( _bats_total_tests + btotal ))
        _bats_total_ms=$(( _bats_total_ms + belapsed_ms ))

        # Check alignment (both pass or both have same number of failures)
        pty_fail=$(( total - passed ))
        bats_fail=$(( btotal - bpassed - bskipped ))
        if (( rc == 0 && brc == 0 )); then
            (( _aligned++ ))
            align_mark="${GREEN}✓${RESET}"
        elif (( pty_fail == bats_fail )); then
            (( _aligned++ ))
            align_mark="${GREEN}✓${RESET}"
        else
            (( _misaligned++ ))
            align_mark="${RED}✗${RESET}"
        fi

        printf '%-20s  %4d/%-4d  %4d/%-4d  %8dms  %8dms  %s\n' \
            "$name" "$passed" "$total" "$bpassed" "$btotal" \
            "$elapsed_ms" "$belapsed_ms" "$align_mark"
    fi
done < "$_ptyunit_results"

printf '%-20s  %8s  %8s  %10s  %10s\n' "────────────────────" "────────" "────────" "──────────" "──────────"
printf '%-20s  %4d/%-4d  %4d/%-4d  %8dms  %8dms\n' \
    "TOTAL" "$_pty_total_pass" "$_pty_total_tests" \
    "$_bats_total_pass" "$_bats_total_tests" \
    "$_pty_total_ms" "$_bats_total_ms"

printf '\n'
_header "Alignment"

if (( _misaligned == 0 )); then
    _ok "All $_aligned suites agree on pass/fail outcomes"
else
    _fail "$_misaligned suites disagree ($(( _aligned )) agree)"
fi

printf '\n'
_header "Performance"

if (( _pty_total_ms > 0 && _bats_total_ms > 0 )); then
    if (( _pty_total_ms < _bats_total_ms )); then
        ratio=$(awk "BEGIN{printf \"%.1f\", $_bats_total_ms / $_pty_total_ms}")
        _ok "ptyunit is ${ratio}x faster (${_pty_total_ms}ms vs ${_bats_total_ms}ms)"
    elif (( _bats_total_ms < _pty_total_ms )); then
        ratio=$(awk "BEGIN{printf \"%.1f\", $_pty_total_ms / $_bats_total_ms}")
        _warn "bats-core is ${ratio}x faster (${_bats_total_ms}ms vs ${_pty_total_ms}ms)"
    else
        _info "Dead heat: both took ${_pty_total_ms}ms"
    fi
fi

printf '\n'
_header "Feature coverage (ptyunit assertions exercised)"
printf '  assert_eq, assert_not_eq       — equality\n'
printf '  assert_output                  — command stdout\n'
printf '  assert_contains, not_contains  — substrings\n'
printf '  assert_true, assert_false      — exit codes\n'
printf '  assert_null, assert_not_null   — empty/non-empty\n'
printf '  assert_match                   — regex\n'
printf '  assert_file_exists             — file system\n'
printf '  assert_line                    — line extraction\n'
printf '  assert_gt, lt, ge, le          — numeric comparisons\n'
printf '  ptyunit_skip_test              — per-test skip\n'
printf '  ptyunit_setup / teardown       — per-test lifecycle\n'
printf '  test_that / test_it / test_they — aliases\n'
printf '  PWD isolation                  — directory restore\n'
printf '\n'

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -f "$_ptyunit_results" "$_bats_results"
