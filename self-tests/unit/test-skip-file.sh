#!/usr/bin/env bash
# self-tests/unit/test-skip-file.sh — exercises ptyunit_skip (file-level skip)
#
# This file intentionally calls ptyunit_skip inline so the PS4 tracer captures
# lines 206-212 of assert.sh. It exits with code 3; the runner reports it as
# skipped (not a failure).

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

ptyunit_skip "file-level skip (intentional — for coverage of ptyunit_skip body)"
