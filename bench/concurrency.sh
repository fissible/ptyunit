#!/usr/bin/env bash
# bench/concurrency.sh — show how worker count affects total run time
#
# NOT part of the test suite. Run explicitly when you want to measure
# parallelism. It is never discovered by run.sh (wrong directory, wrong
# filename pattern) and all synthetic files it creates live in a temp
# directory that is cleaned up on exit.
#
# Generates N synthetic test files that each sleep 1 second, then runs the
# suite with 1 through min(N, nproc) workers. Prints wall-clock time and
# speedup for each worker count so the parallelism benefit is concrete.
#
# Usage:
#   bash bench/concurrency.sh [N]
#
#   N  Number of synthetic test files (default: 6)

set -u

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
N=${1:-6}

if ! [[ "$N" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Usage: bench/concurrency.sh [N]\n  N must be a positive integer\n' >&2
    exit 2
fi

# ── Timing helper ─────────────────────────────────────────────────────────────
_now() {
    if [[ "${BASH_VERSINFO[0]}" -ge 5 ]]; then
        printf '%s' "${EPOCHREALTIME}"
    else
        python3 -c 'import time; print("%.3f" % time.time())' 2>/dev/null \
            || date +%s
    fi
}

# ── Synthetic test suite ───────────────────────────────────────────────────────
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/tests/unit"

for (( i=1; i<=N; i++ )); do
    fname="$tmpdir/tests/unit/test-worker-$(printf '%02d' "$i").sh"
    cat > "$fname" <<TESTEOF
#!/usr/bin/env bash
source "$PTYUNIT_DIR/assert.sh"
sleep 1
test_that "worker $i always passes"
assert_eq "ok" "ok"
ptyunit_test_summary
TESTEOF
    chmod +x "$fname"
done

# ── Run and time ───────────────────────────────────────────────────────────────
max=$(nproc 2>/dev/null || echo 4)
(( max > N )) && max=$N

printf 'Concurrency benchmark: %d files × 1s each  (serial lower bound: %ds)\n\n' "$N" "$N"
printf '  %-10s  %-12s  %s\n' "workers" "wall time" "speedup vs 1"
printf '  %-10s  %-12s  %s\n' "-------" "---------" "------------"

_baseline=""
for (( jobs=1; jobs<=max; jobs++ )); do
    t0=$(_now)
    (cd "$tmpdir" && bash "$PTYUNIT_DIR/run.sh" --unit --jobs "$jobs") > /dev/null 2>&1
    t1=$(_now)
    elapsed=$(awk "BEGIN{printf \"%.1f\", $t1 - $t0}")

    if [[ -z "$_baseline" ]]; then
        _baseline="$elapsed"
        speedup="—"
    else
        speedup=$(awk "BEGIN{printf \"%.1fx\", $_baseline / $elapsed}")
    fi

    label="$jobs"
    (( jobs == 1 )) && label="1 (sequential)"

    printf '  %-14s  %-12s  %s\n' "$label" "${elapsed}s" "$speedup"
done

printf '\n'
