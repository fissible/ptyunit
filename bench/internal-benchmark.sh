#!/usr/bin/env bash
# bench/internal-benchmark.sh — Benchmark ptyunit across all workloads
#
# Measures wall-clock time, assertion counts, and peak memory for:
#   1. ptyunit self-tests (unit)
#   2. shellframe tests (via symlink to current ptyunit)
#   3. macbin tests (via symlink to current ptyunit)
#
# Usage:
#   bash bench/internal-benchmark.sh [--label NAME]
#
# Saves results to bench/results/<label>.json

set -u

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$PTYUNIT_DIR/bench/results"
mkdir -p "$RESULTS_DIR"

SHELLFRAME_DIR="/Users/amccabe/lib/fissible/shellframe"
MACBIN_DIR="/Users/amccabe/lib/fissible/macbin"

# Parse args
_label="baseline"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --label) _label="$2"; shift 2 ;;
        --label=*) _label="${1#--label=}"; shift ;;
        *) shift ;;
    esac
done

_result_file="$RESULTS_DIR/${_label}.json"

printf 'ptyunit benchmark: %s\n' "$_label"
printf '══════════════════════════════════════════\n\n'

# ── Helpers ──────────────────────────────────────────────────────────────────

_now_ms() {
    if [[ "${BASH_VERSINFO[0]}" -ge 5 ]]; then
        local t="${EPOCHREALTIME}"
        local secs="${t%.*}"
        local frac="${t#*.}"
        printf '%s%s' "$secs" "${frac:0:3}"
    else
        python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s000
    fi
}

_bench_suite() {
    local name="$1" dir="$2" runner="$3" flags="$4"
    local t0 t1 elapsed_ms out rc pass total files mem_kb

    printf '  %-20s ' "$name" >&2

    # Measure with /usr/bin/time for peak RSS
    local time_out
    time_out=$(mktemp)

    t0=$(_now_ms)
    out=$(/usr/bin/time -l bash "$runner" $flags 2>"$time_out")
    rc=$?
    t1=$(_now_ms)
    elapsed_ms=$(( t1 - t0 ))

    # Parse assertion counts from output
    pass=0 total=0 files=0
    if [[ "$out" =~ ([0-9]+)/([0-9]+)\ assertions\ passed\ across\ ([0-9]+) ]]; then
        pass="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
        files="${BASH_REMATCH[3]}"
    fi

    # Parse peak RSS from /usr/bin/time output (macOS: bytes)
    mem_kb=0
    local mem_bytes
    mem_bytes=$(grep "maximum resident" "$time_out" 2>/dev/null | awk '{print $1}')
    if [[ -n "$mem_bytes" ]]; then
        mem_kb=$(( mem_bytes / 1024 ))
    fi
    rm -f "$time_out"

    if (( rc == 0 )); then
        printf '%d/%d  %3d files  %5dms  %4dKB\n' "$pass" "$total" "$files" "$elapsed_ms" "$mem_kb" >&2
    else
        printf 'FAIL (rc=%d)  %d/%d  %5dms\n' "$rc" "$pass" "$total" "$elapsed_ms" >&2
    fi

    # Return JSON fragment via stdout
    printf '{"name":"%s","pass":%d,"total":%d,"files":%d,"ms":%d,"kb":%d,"rc":%d}' \
        "$name" "$pass" "$total" "$files" "$elapsed_ms" "$mem_kb" "$rc"
}

# ── Symlink helper for external projects ─────────────────────────────────────

_link_ptyunit() {
    local project_dir="$1"
    local ptyunit_tests="$project_dir/tests/ptyunit"
    if [[ -d "$ptyunit_tests" ]] || [[ -L "$ptyunit_tests" ]]; then
        mv "$ptyunit_tests" "${ptyunit_tests}.bench_backup" 2>/dev/null || true
    fi
    ln -sf "$PTYUNIT_DIR" "$ptyunit_tests"
}

_unlink_ptyunit() {
    local project_dir="$1"
    local ptyunit_tests="$project_dir/tests/ptyunit"
    rm -f "$ptyunit_tests" 2>/dev/null
    if [[ -d "${ptyunit_tests}.bench_backup" ]] || [[ -L "${ptyunit_tests}.bench_backup" ]]; then
        mv "${ptyunit_tests}.bench_backup" "$ptyunit_tests"
    fi
}

# ── Run benchmarks ───────────────────────────────────────────────────────────

results=()

# 1. ptyunit self-tests
printf 'Workloads:\n'
r=$(_bench_suite "ptyunit-self" "$PTYUNIT_DIR" "$PTYUNIT_DIR/run.sh" "--unit")
results+=("$r")

# 2. shellframe (if present)
if [[ -d "$SHELLFRAME_DIR/tests/unit" ]]; then
    _link_ptyunit "$SHELLFRAME_DIR"
    r=$(cd "$SHELLFRAME_DIR" && _bench_suite "shellframe" "$SHELLFRAME_DIR" "$SHELLFRAME_DIR/tests/ptyunit/run.sh" "--unit")
    results+=("$r")
    _unlink_ptyunit "$SHELLFRAME_DIR"
else
    printf '  %-20s (not found)\n' "shellframe"
fi

# 3. macbin (if present)
if [[ -d "$MACBIN_DIR/tests/unit" ]]; then
    _link_ptyunit "$MACBIN_DIR"
    r=$(cd "$MACBIN_DIR" && _bench_suite "macbin" "$MACBIN_DIR" "$MACBIN_DIR/tests/ptyunit/run.sh" "--unit")
    results+=("$r")
    _unlink_ptyunit "$MACBIN_DIR"
else
    printf '  %-20s (not found)\n' "macbin"
fi

# ── Write JSON ───────────────────────────────────────────────────────────────

{
    printf '{\n'
    printf '  "label": "%s",\n' "$_label"
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "bash_version": "%s",\n' "$BASH_VERSION"
    printf '  "git_sha": "%s",\n' "$(git -C "$PTYUNIT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    printf '  "suites": [\n'
    _first=1
    for r in "${results[@]}"; do
        (( _first )) && _first=0 || printf ',\n'
        printf '    %s' "$r"
    done
    printf '\n  ]\n'
    printf '}\n'
} > "$_result_file"

printf '\nResults saved to: %s\n' "$_result_file"

# ── Compare with previous (if exists) ───────────────────────────────────────

_compare_file=""
for f in "$RESULTS_DIR"/*.json; do
    [[ "$f" == "$_result_file" ]] && continue
    [[ -f "$f" ]] && _compare_file="$f"
done

if [[ -n "$_compare_file" ]]; then
    printf '\n══ Comparison with %s ══\n\n' "$(basename "$_compare_file" .json)"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$_compare_file" "$_result_file" << 'PYCOMPARE'
import json, sys

with open(sys.argv[1]) as f: old = json.load(f)
with open(sys.argv[2]) as f: new = json.load(f)

old_suites = {s["name"]: s for s in old["suites"]}
new_suites = {s["name"]: s for s in new["suites"]}

print(f"{'Suite':<20} {'Before':>10} {'After':>10} {'Delta':>10} {'Change':>10}")
print(f"{'─'*20} {'─'*10} {'─'*10} {'─'*10} {'─'*10}")

for name in new_suites:
    ns = new_suites[name]
    if name in old_suites:
        os = old_suites[name]
        delta = ns["ms"] - os["ms"]
        if os["ms"] > 0:
            pct = (delta / os["ms"]) * 100
            sign = "+" if delta > 0 else ""
            print(f"{name:<20} {os['ms']:>7}ms {ns['ms']:>7}ms {sign}{delta:>7}ms {sign}{pct:>8.1f}%")
        else:
            print(f"{name:<20} {os['ms']:>7}ms {ns['ms']:>7}ms {'':>10} {'':>10}")

        # Assertion count changes
        if ns["total"] != os["total"]:
            print(f"  {'assertions:':<18} {os['pass']}/{os['total']:>3} → {ns['pass']}/{ns['total']:>3}")
        if ns["kb"] > 0 and os["kb"] > 0:
            mem_delta = ns["kb"] - os["kb"]
            if mem_delta != 0:
                sign = "+" if mem_delta > 0 else ""
                print(f"  {'memory:':<18} {os['kb']:>4}KB → {ns['kb']:>4}KB ({sign}{mem_delta}KB)")
    else:
        print(f"{name:<20} {'new':>10} {ns['ms']:>7}ms")

print()
print(f"Label: {old['label']} → {new['label']}")
print(f"Commit: {old.get('git_sha','?')} → {new.get('git_sha','?')}")
PYCOMPARE
    fi
fi
