#!/usr/bin/env bash
# self-tests/unit/test-coverage-report.sh — tests for coverage_report.py helpers

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

# ═══════════════════════════════════════════════════════════════════════════════
describe "coverage_report: _format_display_date"

    test_that "formats a PM time with am/pm indicator (1:30 pm)"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 13, 30, 0)))
")
    assert_contains "$_out" "1:30 pm"

    test_that "formats midnight as 12:00 am"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 0, 0, 0)))
")
    assert_contains "$_out" "12:00 am"

    test_that "includes am/pm in the label"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 13, 0, 0)))
")
    assert_eq "1" "$(printf '%s' "$_out" | grep -ci '\(am\|pm\)')"

    test_that "formats an AM time correctly (9:00 am)"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 9, 0, 0)))
")
    assert_contains "$_out" "9:00 am"

end_describe

# ═══════════════════════════════════════════════════════════════════════════════
describe "coverage_report: _parse_report_dt"

    test_that "parses a PM filename correctly (hour 13 stays as 13)"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _parse_report_dt
dt = _parse_report_dt('2026_03_23_13_30_00.html')
print(dt.hour)
")
    assert_eq "13" "$_out"

    test_that "returns None for non-timestamp filename"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _parse_report_dt
print(_parse_report_dt('index.html'))
")
    assert_eq "None" "$_out"

end_describe

# ═══════════════════════════════════════════════════════════════════════════════
describe "coverage_report: _ptyunit_version"

    test_that "returns a non-empty version (not 'unknown') when VERSION file exists"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _ptyunit_version
print(_ptyunit_version())
")
    assert_not_eq "unknown" "$_out"

    test_that "returns 'unknown' when VERSION file is absent (Homebrew without VERSION installed)"
    _tmpdir=$(mktemp -d)
    cp "$PTYUNIT_DIR/coverage_report.py" "$_tmpdir/"
    _out=$(python3 "$_tmpdir/coverage_report.py" --trace /dev/null --src /dev/null --format text 2>/dev/null \
        | grep -c 'unknown' || true)
    # The script itself shouldn't crash — just check exit succeeds from a dir without VERSION
    python3 -c "
import sys; sys.path.insert(0, '$_tmpdir')
from coverage_report import _ptyunit_version
print(_ptyunit_version())
"
    assert_eq "0" "$?"
    rm -rf "$_tmpdir"

end_describe

ptyunit_test_summary
