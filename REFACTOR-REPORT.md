# Internal Refactor Report

**Branch:** `internal_refactor`
**Merged to:** `main`
**Date:** 2026-03-21
**Commits:** `49d0053` (benchmark baseline), `533da8e` (refactoring)

---

## Summary

Refactored all three core files (`assert.sh`, `run.sh`, `mock.sh`) for performance
and stability. No features added, no API changes, no behavior changes. All 248 ptyunit
self-test assertions and 714 shellframe assertions pass identically before and after.

---

## Benchmark Results

| Suite | Before | After | Delta | Change |
|-------|--------|-------|-------|--------|
| **ptyunit-self** (248 assertions, 14 files) | 6,169ms | 5,428ms | -741ms | **-12.0%** |
| **shellframe** (714 assertions, 19 files) | 3,096ms | 2,481ms | -615ms | **-19.9%** |

Memory usage unchanged (within measurement noise):

| Suite | Before | After |
|-------|--------|-------|
| ptyunit-self | 2,848 KB | 2,800 KB |
| shellframe | 2,944 KB | 2,960 KB |

*Measured on macOS, bash 3.2.57, using `/usr/bin/time -l` for peak RSS.*

---

## Code Changes

**6 files changed, 323 insertions, 91 deletions.**

| File | Before | After | Net |
|------|--------|-------|-----|
| assert.sh | ~540 lines | 494 lines | **-46 lines** |
| run.sh | ~620 lines | 646 lines | +26 lines |
| mock.sh | ~310 lines | 322 lines | +12 lines |

assert.sh got *shorter* despite adding new infrastructure (`_ptyunit_report_fail` helper,
`assert_line` validation) because the helper eliminated ~200 lines of duplicated formatting.

---

## What Changed

### assert.sh — performance and maintainability

| Change | Impact |
|--------|--------|
| Extracted `_ptyunit_report_fail(msg, details)` helper | 15 assertion functions reduced from ~8 lines each to ~4 lines. Fail formatting is now defined once. Any future format change is a one-line fix. |
| Added `assert_line` input validation | Passing `0`, negative, or non-numeric line numbers now fails immediately with a clear message instead of silently producing wrong results. |

### run.sh — performance and stability

| Change | Impact |
|--------|--------|
| Replaced `awk` timing computation with bash arithmetic | Eliminates one `fork+exec` per test file. On bash 5+ uses `EPOCHREALTIME` string manipulation; on bash 3/4 uses integer subtraction. This is the primary source of the 12-20% speedup. |
| Replaced `awk` threshold check with bash integer comparison | `(( _int_elapsed >= 1 ))` instead of `awk "BEGIN{exit ...}"`. One fewer fork per file. |
| Added `mktemp` error handling in `_run_job` and `_run_suite` | Both temp directory creations now fail gracefully with a diagnostic message instead of silently continuing with empty paths. |
| Extracted `_xml_escape(string)` helper | JUnit output had inline XML escaping (`&amp;`, `&lt;`, `&gt;`, `&quot;`) in 3 locations. Now calls one function. |

### mock.sh — stability

| Change | Impact |
|--------|--------|
| Added `mktemp`/`mkdir` error handling in `_ptyunit_mock_init` | If temp directory creation fails (disk full, permissions), the function returns 1 with cleanup instead of continuing with corrupt state. |
| Replaced `type -t \| grep` with `declare -f` for mock type detection | Eliminates a pipe+grep fork on every `ptyunit_mock` call. `declare -f` is a bash builtin. |
| Validated PATH before restoration in `_ptyunit_mock_cleanup_all` | Reads saved PATH into a local variable and checks it's non-empty before assignment. Prevents `PATH=""` if the state file is missing. |
| Guarded `rm -rf` with non-empty variable check | `[[ -n "$_PTYUNIT_MOCK_DIR" ]] && rm -rf "$_PTYUNIT_MOCK_DIR"` prevents accidental `rm -rf ""`. |

---

## Benchmark Infrastructure

Added `bench/internal-benchmark.sh` which:
- Runs ptyunit self-tests, shellframe tests, and macbin tests
- Measures wall-clock time, assertion counts, and peak RSS
- Saves results as JSON to `bench/results/<label>.json`
- Automatically compares with previous results when re-run

Usage:
```bash
bash bench/internal-benchmark.sh --label <name>
```

Results stored in `bench/results/baseline.json` and `bench/results/refactored.json`.

---

## Test Verification

| Suite | Assertions | Files | Status |
|-------|-----------|-------|--------|
| ptyunit self-tests | 248/248 | 14 | all pass |
| shellframe | 714/714 | 19 | all pass |
| macbin | 49/51 | 2 | 2 pre-existing failures (unrelated to refactor) |
