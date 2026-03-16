#!/usr/bin/env bash
# docker/run-matrix.sh — Run the ptyunit test suite against bash 3.2, 4.4, and 5.x
#
# Usage: bash docker/run-matrix.sh [--no-cache]
#
# Builds one Docker image per bash version (tagged ptyunit-bash{3,4,5}),
# runs the full test suite in each, then prints a version-by-version summary.
# Pass --no-cache to force a clean rebuild of all images.

set -u

DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTYUNIT_DIR="$(cd "$DOCKER_DIR/.." && pwd)"

NO_CACHE=""
[[ "${1:-}" == "--no-cache" ]] && NO_CACHE="--no-cache"

if ! command -v docker >/dev/null 2>&1; then
    printf 'error: docker not found in PATH\n' >&2
    exit 1
fi

# ── Matrix definition ─────────────────────────────────────────────────────────

declare -a _LABELS=("bash 3.2" "bash 4.4" "bash 5.x")
declare -a _TAGS=("ptyunit-bash3" "ptyunit-bash4" "ptyunit-bash5")
declare -a _DOCKERFILES=("Dockerfile.bash3" "Dockerfile.bash4" "Dockerfile.bash5")

_pass=0
_fail=0
declare -a _results=()

# ── Build and run each image ──────────────────────────────────────────────────

for _i in "${!_LABELS[@]}"; do
    _label="${_LABELS[$_i]}"
    _tag="${_TAGS[$_i]}"
    _df="$DOCKER_DIR/${_DOCKERFILES[$_i]}"

    printf '\n══════════════════════════════════════\n'
    printf '  %s\n' "$_label"
    printf '══════════════════════════════════════\n'

    # Build
    if ! docker build $NO_CACHE -q -f "$_df" -t "$_tag" "$PTYUNIT_DIR"; then
        printf 'BUILD FAILED\n'
        _results+=("$_label: BUILD FAILED")
        (( _fail++ ))
        continue
    fi

    # Run (--rm cleans up the container; no -t since output is captured)
    if docker run --rm "$_tag" bash run.sh; then
        _results+=("$_label: PASS")
        (( _pass++ ))
    else
        _results+=("$_label: FAIL")
        (( _fail++ ))
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

printf '\n══════════════════════════════════════\n'
printf '  Matrix summary\n'
printf '══════════════════════════════════════\n'
for _r in "${_results[@]}"; do
    printf '  %s\n' "$_r"
done
printf '\n%d/%d versions passed\n' "$_pass" "$(( _pass + _fail ))"

(( _fail == 0 ))
