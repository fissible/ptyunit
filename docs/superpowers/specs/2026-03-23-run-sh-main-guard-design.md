# Design: run.sh Main Guard for Coverage

**Date:** 2026-03-23
**Branch:** feat/run-sh-main-guard
**Status:** Approved

---

## Problem

`run.sh` shows 0% code coverage despite having comprehensive functional tests
(`test-runner.sh`, `test-runner-format.sh`, `test-runner-filter.sh`, etc.).
The root cause: all those tests invoke `bash run.sh ...` which forks a new
process — the PS4 tracer in the coverage shell cannot follow into it.

`coverage.sh` has the same issue but is a thin orchestrator (~88 lines) with
less internal logic worth isolating. It will remain as-is (Option C: accept
0%, no structural change).

---

## Solution: Main Guard Pattern

Add a bash equivalent of Python's `if __name__ == "__main__"` to `run.sh`:

```bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _main "$@"
```

When invoked as `bash run.sh ...` → `_main` fires, behavior identical to
today. When sourced in a test → only `PTYUNIT_DIR`/`TESTS_DIR` detection and
function definitions load; nothing executes.

---

## run.sh Structure Changes

### Stays at file scope (unchanged behavior on source)

| Code | Why at file scope |
|------|-------------------|
| `PTYUNIT_DIR` / `TESTS_DIR` detection | Functions reference these at call time |
| `_usage()` | Called by `_main`; definition must precede `_main` |
| `_ptyunit_now()` | Pure helper; no side effects |
| `_xml_escape()` | Pure helper; no side effects |
| `_run_job()` | Worker function; tests call directly |
| `_run_suite()` | Suite runner; tests call directly |
| `_emit_tap()` | TAP formatter; tests call directly |
| `_emit_junit()` | JUnit formatter; tests call directly |

### Moves into `_main()`

- Default variable declarations: `_mode`, `_jobs`, `_verbose`, `_filter`,
  `_name_filter`, `_fail_fast`, `_format`, `PTYUNIT_VERSION`
- Arg-parsing `while` loop
- `--jobs` and `--format` validation
- Color setup: `_use_color`, `_OK_LABEL`, `_FAIL_LABEL`, `_SKIP_LABEL`
- Counter initialization: `_total_pass`, `_total_fail`, `_total_files`,
  `_total_skip`, `_failed_files`, `_skipped_files`
- Suite tracking arrays: `_suite_work_dirs`, `_suite_labels`
- Fail-fast sentinel: `_fail_sentinel`
- Dispatch `case "$_mode"` block
- Output / summary / cleanup

### Added at end of file

```bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _main "$@"
```

### Compatibility

Existing tests that invoke `bash run.sh ...` are unaffected — `_main` fires
identically to the current top-level code.

---

## New Tests: `self-tests/unit/test-run-internals.sh`

Sources `run.sh`, sets required globals, calls internal functions directly.

### `_xml_escape`

6–8 assertions covering each special character (`&`, `<`, `>`, `"`) in
isolation and combined. Currently has zero direct tests.

### `_ptyunit_now`

Assert returns a non-empty numeric string. Exercises both branches: bash 5
(`EPOCHREALTIME`) and bash 3/4 (`date +%s`).

### `_main` arg validation

| Input | Expected |
|-------|----------|
| `--format bad` | exits 2 |
| `--jobs 0` | exits 2 |
| `--jobs abc` | exits 2 |
| `--version` | prints version, exits 0 |
| `--help` | prints usage, exits 0 |
| unknown flag | exits 2 |

These branches already exist in `run.sh` but are not individually traceable
today because they're executed inside a subprocess.

### Required globals when sourcing `run.sh`

`run.sh` has `set -u` at file scope. Any test that sources it and calls an
internal function **must** initialize these globals first or bash will abort
with "unbound variable". Minimum required set:

| Variable | Used by | Default for tests |
|----------|---------|-------------------|
| `_verbose` | `_run_job` | `0` |
| `_fail_fast` | `_run_job`, `_run_suite` | `0` |
| `_fail_sentinel` | `_run_job`, `_run_suite` | `""` |
| `_format` | `_run_suite`, `_emit_*` | `"pretty"` |
| `_jobs` | `_run_suite` | `1` |
| `_filter` | `_run_suite` | `""` |
| `_OK_LABEL` | `_run_job` | `"OK"` |
| `_FAIL_LABEL` | `_run_job` | `"FAIL"` |
| `_SKIP_LABEL` | `_run_job` | `"SKIP"` |
| `_suite_work_dirs` | `_emit_tap`, `_emit_junit` | `()` |
| `_suite_labels` | `_emit_junit` | `()` |
| `_total_pass/fail/files/skip` | `_run_suite` aggregation | `0` |
| `_failed_files`, `_skipped_files` | `_run_suite` aggregation | `()` |

`ptyunit_setup` in `test-run-internals.sh` sets all of these to safe defaults
before each test section.

### `_emit_tap` and `_emit_junit`

Use a fixture work_dir constructed in `ptyunit_setup`. `.file_list` entries
are bare filenames (a deliberate simplification — the real runner writes full
paths, but `name="${_f##*/}"` handles both identically):

```bash
_ws=$(mktemp -d)
# Four cases: pass, fail (with diagnostics), skip (rc=3), missing .res (did not run)
printf 'test-pass.sh\ntest-fail.sh\ntest-skip.sh\ntest-missing.sh\n' > "$_ws/.file_list"
printf '0 5 5 0.1\n'   > "$_ws/test-pass.sh.res"    # rc pass total elapsed
printf '1 3 5 0.2\n'   > "$_ws/test-fail.sh.res"
printf '3 0 0 0.0\n'   > "$_ws/test-skip.sh.res"
printf 'diagnostics\n' > "$_ws/test-fail.sh.raw"
# test-missing.sh has no .res file — covers "did not run" branch
_suite_work_dirs=("$_ws")
_suite_labels=("Unit")
```

**TAP assertions:** `TAP version 13`, `1..4` plan, `ok 1`, `not ok 2` with
YAML diagnostic block, `ok 3 # SKIP`, `ok 4 - test-missing.sh # SKIP did not run`.

**JUnit assertions:** XML declaration, `<testsuites>`, `<testsuite>` with
correct counts, `<testcase>` elements with `<failure>`, `<skipped/>`, and
`<skipped message="did not run"/>` nodes, `_xml_escape` applied to names.

---

## coverage.sh

No changes. 0% coverage is accepted for this orchestrator. The meaningful
coverage gains come from `run.sh` internal functions.

---

## Success Criteria

- All existing tests still pass after the refactor (`bash run.sh` behavior
  unchanged)
- `run.sh` coverage improves from 0% to ≥ 50%. The helpers (`_xml_escape`,
  `_ptyunit_now`), both emitters, and `_main` arg-parsing together represent
  ~110–130 executable lines out of ~230 total (~48–56%). Reaching 60%+ would
  require at least one direct `_run_job` call with a real fixture test file,
  which is out of scope for this change.
- `test-run-internals.sh` passes standalone: `bash self-tests/unit/test-run-internals.sh`
- Overall project coverage improves from ~47% toward ~53%+
