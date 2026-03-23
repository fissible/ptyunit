#!/usr/bin/env bash
# self-tests/unit/test-coverage-report.sh — tests for coverage_report.py helpers

set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"

# ═══════════════════════════════════════════════════════════════════════════════
describe "coverage_report: _format_display_date"

    test_that "formats a PM time using 24-hour clock (13:30, not 1:30 pm)"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 13, 30, 0)))
")
    assert_contains "$_out" "13:30"

    test_that "formats midnight using 24-hour clock (00:00, not 12:00 am)"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 0, 0, 0)))
")
    assert_contains "$_out" "00:00"

    test_that "does not include am/pm in the label"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
# 1pm — would show 'pm' with 12h format
print(_format_display_date(datetime.datetime(2026, 3, 23, 13, 0, 0)))
")
    assert_eq "0" "$(printf '%s' "$_out" | grep -ci '\(am\|pm\)')"

    test_that "formats an AM time correctly (09:00)"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _format_display_date
import datetime
print(_format_display_date(datetime.datetime(2026, 3, 23, 9, 0, 0)))
")
    assert_contains "$_out" "09:00"

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

    test_that "returns a non-empty version (not 'unknown')"
    _out=$(python3 -c "
import sys; sys.path.insert(0, '$PTYUNIT_DIR')
from coverage_report import _ptyunit_version
print(_ptyunit_version())
")
    assert_not_eq "unknown" "$_out"

end_describe

ptyunit_test_summary
