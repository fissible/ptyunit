#!/usr/bin/env bash
# run-hostile.sh — Run the hostile-environment stability test suite.
#
# These tests exercise timing-sensitive failure modes not covered by the default
# suite. They are intentionally slow (~10s+) and require OS-level tooling.
#
# Requirements: Python 3, pytest, pyte
#
# Usage:
#   bash run-hostile.sh              # all scenarios
#   bash run-hostile.sh -k slow      # filter by test name
#   bash run-hostile.sh -v           # verbose

set -eu

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf 'ptyunit hostile-environment tests\n'
printf '(slow)\n\n'

exec python3 -m pytest "$PTYUNIT_DIR/self-tests/hostile/" -v "$@"
