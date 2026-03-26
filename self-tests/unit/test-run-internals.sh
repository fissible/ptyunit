#!/usr/bin/env bash
# Note: assert_output/assert_true/assert_false suppress stderr (2>/dev/null),
# which swallows the PS4 trace. Call functions directly — result=$(...) traces
# the function body; direct predicate calls + $? check also trace correctly.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"

# ── Required globals (run.sh has set -u; initialize before sourcing) ─────────
_verbose=0
_fail_fast=0
_fail_sentinel=""
_format="pretty"
_jobs=1
_filter=""
_OK_LABEL="OK"
_FAIL_LABEL="FAIL"
_SKIP_LABEL="SKIP"
_suite_work_dirs=()
_suite_labels=()
_total_pass=0
_total_fail=0
_total_files=0
_total_skip=0
_failed_files=()
_skipped_files=()

source "$PTYUNIT_DIR/run.sh"

# ── Per-test setup/teardown ───────────────────────────────────────────────────
_ws=""
ptyunit_setup() {
    # Reset shared globals to safe defaults before each test section
    _verbose=0
    _fail_fast=0
    _fail_sentinel=""
    _format="pretty"
    _jobs=1
    _filter=""
    _OK_LABEL="OK"
    _FAIL_LABEL="FAIL"
    _SKIP_LABEL="SKIP"
    _total_pass=0
    _total_fail=0
    _total_files=0
    _total_skip=0
    _failed_files=()
    _skipped_files=()

    # Build a fixture work_dir for _emit_tap and _emit_junit
    # Four cases: pass, fail (with diagnostics), skip (rc=3), missing .res (did not run)
    _ws=$(mktemp -d)
    printf 'test-pass.sh\ntest-fail.sh\ntest-skip.sh\ntest-missing.sh\n' > "$_ws/.file_list"
    printf '0 5 5 0.1\n'   > "$_ws/test-pass.sh.res"    # rc passed total elapsed
    printf '1 3 5 0.2\n'   > "$_ws/test-fail.sh.res"
    printf '3 0 0 0.0\n'   > "$_ws/test-skip.sh.res"
    printf 'diagnostics\n' > "$_ws/test-fail.sh.raw"
    # test-missing.sh has no .res file — covers "did not run" branch
    _suite_work_dirs=("$_ws")
    _suite_labels=("Unit")
}
ptyunit_teardown() {
    [[ -n "$_ws" ]] && rm -rf "$_ws"
    _suite_work_dirs=()
    _suite_labels=()
}

# ── _xml_escape ───────────────────────────────────────────────────────────────

test_that "_xml_escape leaves plain string unchanged"
result=$(_xml_escape "hello")
assert_eq "hello" "$result"

test_that "_xml_escape escapes ampersand"
result=$(_xml_escape "a&b")
assert_eq "a&amp;b" "$result"

test_that "_xml_escape escapes less-than"
result=$(_xml_escape "a<b")
assert_eq "a&lt;b" "$result"

test_that "_xml_escape escapes greater-than"
result=$(_xml_escape "a>b")
assert_eq "a&gt;b" "$result"

test_that "_xml_escape escapes double-quote"
result=$(_xml_escape 'a"b')
assert_eq "a&quot;b" "$result"

test_that "_xml_escape escapes combined special chars"
result=$(_xml_escape '<tag attr="v&a">content</tag>')
assert_eq '&lt;tag attr=&quot;v&amp;a&quot;&gt;content&lt;/tag&gt;' "$result"

# ── _ptyunit_now ──────────────────────────────────────────────────────────────

test_that "_ptyunit_now returns a non-empty numeric string"
result=$(_ptyunit_now)
assert_not_null "$result"
assert_match "^[0-9]" "$result"

# ── _main arg validation ──────────────────────────────────────────────────────
# Note: _main calls exit; use $(...) for cases that print output, ( ) subshell
# for exit-2 cases. Neither suppresses stderr, so PS4 traces are preserved.

test_that "_main --version prints version and exits 0"
result=$(_main --version)
assert_eq "0" "$?"
assert_match "ptyunit" "$result"

test_that "_main --help prints usage and exits 0"
result=$(_main --help)
assert_eq "0" "$?"
assert_match "Usage" "$result"

test_that "_main --format bad exits 2"
( _main --format bad )
assert_eq "2" "$?"

test_that "_main --jobs 0 exits 2"
( _main --jobs 0 )
assert_eq "2" "$?"

test_that "_main --jobs abc exits 2"
( _main --jobs abc )
assert_eq "2" "$?"

test_that "_main unknown flag exits 2"
( _main --no-such-flag )
assert_eq "2" "$?"

test_that "_main --unit --format tap with no matching files exits 0"
( _main --unit --format tap --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

test_that "_main --unit --format junit with no matching files exits 0"
( _main --unit --format junit --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

test_that "_main --all --format pretty with no matching files exits 0"
( _main --all --format pretty --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

test_that "_main --unit --fail-fast with no matching files exits 0"
( _main --unit --fail-fast --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

test_that "_main --integration --format tap with no matching files exits 0"
( _main --integration --format tap --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

test_that "_main --all --format tap with no matching files exits 0"
( _main --all --format tap --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

test_that "_main --all --fail-fast --format pretty with no matching files exits 0"
( _main --all --fail-fast --format pretty --filter __no_such_test__ ) >/dev/null
assert_eq "0" "$?"

# ── _run_suite ────────────────────────────────────────────────────────────────

test_that "_run_suite processes a passing test file"
_filter=""
_format="pretty"
_jobs=1
_tmp_suite=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "fixture"\nassert_eq "1" "1"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_tmp_suite/test-pass.sh"
chmod +x "$_tmp_suite/test-pass.sh"
_run_suite "$_tmp_suite" "Fixture" >/dev/null
assert_eq "0" "$?"
assert_eq "1" "$_total_files"
assert_eq "1" "$_total_pass"
rm -rf "$_tmp_suite"

# ── _emit_tap ─────────────────────────────────────────────────────────────────

test_that "_emit_tap outputs TAP version 13 header"
result=$(_emit_tap)
assert_match "TAP version 13" "$result"

test_that "_emit_tap outputs plan 1..4"
result=$(_emit_tap)
assert_match "1\.\.4" "$result"

test_that "_emit_tap outputs ok for passing test"
result=$(_emit_tap)
assert_match "ok 1" "$result"

test_that "_emit_tap outputs not ok for failing test"
result=$(_emit_tap)
assert_match "not ok 2" "$result"

test_that "_emit_tap outputs YAML diagnostic block for failing test"
result=$(_emit_tap)
assert_match "diagnostics" "$result"

test_that "_emit_tap outputs SKIP for skip and missing"
result=$(_emit_tap)
assert_match "SKIP" "$result"

# ── _emit_junit ───────────────────────────────────────────────────────────────

test_that "_emit_junit outputs XML declaration"
result=$(_emit_junit)
assert_match "xml version" "$result"

test_that "_emit_junit outputs testsuites element"
result=$(_emit_junit)
assert_match "<testsuites>" "$result"

test_that "_emit_junit outputs testsuite with correct counts"
result=$(_emit_junit)
assert_match 'tests="4"' "$result"
assert_match 'failures="1"' "$result"

test_that "_emit_junit outputs passing testcase"
result=$(_emit_junit)
assert_match 'name="test-pass.sh"' "$result"

test_that "_emit_junit outputs failure element for failing test"
result=$(_emit_junit)
assert_match "<failure" "$result"
assert_match "diagnostics" "$result"

test_that "_emit_junit outputs skipped message for missing test"
result=$(_emit_junit)
assert_match "did not run" "$result"

# ── _run_job: setUp failure ───────────────────────────────────────────────────

test_that "_run_job writes setUp-failed output when setUp exits non-zero"
_rj_tmp=$(mktemp -d); _rj_wd=$(mktemp -d)
printf '#!/usr/bin/env bash\nexit 1\n' > "$_rj_tmp/setUp.sh"
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "1"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-su.sh"
chmod +x "$_rj_tmp/setUp.sh" "$_rj_tmp/test-su.sh"
_run_job "$_rj_tmp/test-su.sh" "$_rj_tmp/setUp.sh" "" "$_rj_wd" 10
assert_contains "$(cat "$_rj_wd/test-su.sh.out")" "setUp failed"
rm -rf "$_rj_tmp" "$_rj_wd"

# ── _run_job: rc=3 skip ───────────────────────────────────────────────────────

test_that "_run_job writes rc=3 .res when test file calls ptyunit_skip"
_rj_tmp=$(mktemp -d); _rj_wd=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\nptyunit_skip "reason"\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-sk.sh"
chmod +x "$_rj_tmp/test-sk.sh"
_run_job "$_rj_tmp/test-sk.sh" "" "" "$_rj_wd" 10
read -r _rj_rc _rj_pass _rj_total _rj_e < "$_rj_wd/test-sk.sh.res"
assert_eq "3" "$_rj_rc"
rm -rf "$_rj_tmp" "$_rj_wd"

# ── _run_job: fail output ─────────────────────────────────────────────────────

test_that "_run_job writes FAIL output line when test file has a failing assertion"
_rj_tmp=$(mktemp -d); _rj_wd=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "2"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-fb.sh"
chmod +x "$_rj_tmp/test-fb.sh"
_run_job "$_rj_tmp/test-fb.sh" "" "" "$_rj_wd" 10
assert_contains "$(cat "$_rj_wd/test-fb.sh.out")" "FAIL"
rm -rf "$_rj_tmp" "$_rj_wd"

# ── _run_job: verbose timing ──────────────────────────────────────────────────

test_that "_run_job writes elapsed timing in output when _verbose=1"
_verbose=1
_rj_tmp=$(mktemp -d); _rj_wd=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "1"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-vb.sh"
chmod +x "$_rj_tmp/test-vb.sh"
_run_job "$_rj_tmp/test-vb.sh" "" "" "$_rj_wd" 10
assert_contains "$(cat "$_rj_wd/test-vb.sh.out")" " in "
rm -rf "$_rj_tmp" "$_rj_wd"

# ── _run_job: tearDown always runs ────────────────────────────────────────────

test_that "_run_job runs tearDown.sh after a passing test"
_rj_tmp=$(mktemp -d); _rj_wd=$(mktemp -d)
_rj_marker="$_rj_tmp/teardown-ran"
printf '#!/usr/bin/env bash\ntouch "%s"\n' "$_rj_marker" > "$_rj_tmp/tearDown.sh"
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "1"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-td.sh"
chmod +x "$_rj_tmp/tearDown.sh" "$_rj_tmp/test-td.sh"
_run_job "$_rj_tmp/test-td.sh" "" "$_rj_tmp/tearDown.sh" "$_rj_wd" 10
assert_file_exists "$_rj_marker"
rm -rf "$_rj_tmp" "$_rj_wd"

# ── _run_suite: TAP work_dir saved ───────────────────────────────────────────

test_that "_run_suite appends to _suite_work_dirs when format is tap"
_rj_tmp=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "1"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-tp.sh"
chmod +x "$_rj_tmp/test-tp.sh"
_format="tap"
_run_suite "$_rj_tmp" "TapSuite" >/dev/null
# _suite_work_dirs[0] is the emit fixture ws (from ptyunit_setup); [1] is the new tap dir
assert_eq "2" "${#_suite_work_dirs[@]}"
rm -rf "$_rj_tmp" "${_suite_work_dirs[1]}"
_suite_work_dirs=("${_suite_work_dirs[0]}")

# ── _run_suite: skip counting ─────────────────────────────────────────────────

test_that "_run_suite increments _total_skip for files that call ptyunit_skip"
_rj_tmp=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\nptyunit_skip "reason"\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-sk2.sh"
chmod +x "$_rj_tmp/test-sk2.sh"
_format="pretty"
_run_suite "$_rj_tmp" "SkipSuite" >/dev/null
assert_not_eq "0" "$_total_skip"
rm -rf "$_rj_tmp"

# ── _run_suite: failed file tracking ─────────────────────────────────────────

test_that "_run_suite adds failing file name to _failed_files"
_rj_tmp=$(mktemp -d)
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "2"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_rj_tmp/test-fl.sh"
chmod +x "$_rj_tmp/test-fl.sh"
_format="pretty"
_run_suite "$_rj_tmp" "FailSuite" >/dev/null
assert_not_eq "0" "${#_failed_files[@]}"
rm -rf "$_rj_tmp"

# ── _main: color labels via FORCE_COLOR ───────────────────────────────────────

test_that "_main sets ANSI color labels when FORCE_COLOR=1"
( FORCE_COLOR=1; _main --unit --filter __no_such_test__ ) >/dev/null 2>&1
assert_eq "0" "$?"

# ── _main: sequential header ──────────────────────────────────────────────────

test_that "_main prints sequential header when --jobs 1"
_main_out=$( _main --unit --jobs 1 --format pretty --filter __no_such_test__ )
assert_contains "$_main_out" "sequential"

# ── _main: name filter export ─────────────────────────────────────────────────

test_that "_main exports PTYUNIT_FILTER_NAME when --name is given"
( _main --unit --name sometest --filter __no_such_test__ ) >/dev/null 2>&1
assert_eq "0" "$?"

# ── _main: missing-value flag errors ─────────────────────────────────────────

test_that "_main --jobs with no value exits 2"
( _main --jobs ) 2>/dev/null
assert_eq "2" "$?"

test_that "_main --filter with no value exits 2"
( _main --filter ) 2>/dev/null
assert_eq "2" "$?"

test_that "_main --name with no value exits 2"
( _main --name ) 2>/dev/null
assert_eq "2" "$?"

test_that "_main --format with no value exits 2"
( _main --format ) 2>/dev/null
assert_eq "2" "$?"

# ── _main: pretty summary skip/fail listing ───────────────────────────────────

test_that "_main pretty summary lists skipped files"
_main_td=$(mktemp -d)
mkdir -p "$_main_td/unit"
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\nptyunit_skip "reason"\n' "$PTYUNIT_DIR" > "$_main_td/unit/test-sk3.sh"
chmod +x "$_main_td/unit/test-sk3.sh"
_main_out=$( TESTS_DIR="$_main_td"; _main --unit --format pretty )
assert_contains "$_main_out" "Skipped:"
rm -rf "$_main_td"

test_that "_main pretty summary lists failed files"
_main_td=$(mktemp -d)
mkdir -p "$_main_td/unit"
printf '#!/usr/bin/env bash\nset -u\nPTYUNIT_DIR="%s"\nsource "$PTYUNIT_DIR/assert.sh"\ntest_that "x"\nassert_eq "1" "2"\nptyunit_test_summary\n' "$PTYUNIT_DIR" > "$_main_td/unit/test-fl2.sh"
chmod +x "$_main_td/unit/test-fl2.sh"
_main_out=$( TESTS_DIR="$_main_td"; _main --unit --format pretty )
assert_contains "$_main_out" "Failed files:"
rm -rf "$_main_td"

ptyunit_test_summary
