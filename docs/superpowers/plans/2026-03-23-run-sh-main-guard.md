# run.sh Main Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `_main()` function and main-guard to `run.sh` so it can be sourced in unit tests, enabling direct coverage of `_xml_escape`, `_ptyunit_now`, `_emit_tap`, `_emit_junit`, and `_main` arg-parsing.

**Architecture:** Move all top-level execution code (flag defaults, arg parsing, validation, color setup, counters, dispatch, output, cleanup) into `_main()`. Leave only `PTYUNIT_DIR`/`TESTS_DIR` detection and the seven function definitions at file scope. Add `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _main "$@"` at end of file. Write `self-tests/unit/test-run-internals.sh` to source `run.sh` and call internal functions directly.

**Tech Stack:** bash 3.2–5.x, ptyunit assert.sh

---

## File Map

| Action | Path |
|--------|------|
| Create | `self-tests/unit/test-run-internals.sh` |
| Modify | `run.sh` |

---

### Task 1: Write the failing test file (RED)

**Files:**
- Create: `self-tests/unit/test-run-internals.sh`

- [ ] **Step 1: Write the test file**

```bash
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

ptyunit_test_summary
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard/self-tests/unit/test-run-internals.sh
```

- [ ] **Step 3: Run to confirm RED**

```bash
bash /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard/self-tests/unit/test-run-internals.sh
```

Expected: Fails or errors because sourcing the un-refactored `run.sh` executes all its top-level code (runs the full test suite), then `_main` is not defined → "command not found" errors on the `_main` tests. The file will not cleanly produce a passing summary.

- [ ] **Step 4: Commit RED test file**

```bash
cd /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard
git add self-tests/unit/test-run-internals.sh
git commit -m "test(run-internals): add RED unit tests for run.sh internal functions"
```

---

### Task 2: Refactor run.sh — add `_main()` and main guard (GREEN)

**Files:**
- Modify: `run.sh`

**Current structure (what's at file scope today):**

```
set -u
PTYUNIT_DIR / TESTS_DIR detection     ← stays at file scope
# ── Flag parsing ─────           ← moves into _main()
_mode=... _jobs=... etc             ← moves into _main()
_usage()                            ← stays (function def, called by _main)
while [[ $# -gt 0 ]]; do ... done  ← moves into _main()
# validation                        ← moves into _main()
# color setup                       ← moves into _main()
# counters + fail-fast sentinel     ← moves into _main()
_ptyunit_now()                      ← stays (function def)
_xml_escape()                       ← stays (function def)
_run_job()                          ← stays (function def)
_run_suite()                        ← stays (function def)
_emit_tap()                         ← stays (function def)
_emit_junit()                       ← stays (function def)
# dispatch case statement           ← moves into _main()
# output / summary                  ← moves into _main()
# cleanup                           ← moves into _main()
# exit                              ← moves into _main()
```

**Target structure:**

```
set -u
PTYUNIT_DIR / TESTS_DIR detection
_usage()
_ptyunit_now()
_xml_escape()
_run_job()
_run_suite()
_emit_tap()
_emit_junit()
_main() { <everything that was at file scope but is not a function def> }
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _main "$@"
```

- [ ] **Step 1: Move flag defaults and `PTYUNIT_VERSION` into `_main()`**

In `run.sh`, locate the `# ── Flag parsing ──` block (currently lines 45–54):

```bash
# ── Flag parsing ──────────────────────────────────────────────────────────────
_mode="--all"
_jobs=$(nproc 2>/dev/null || echo 4)
_verbose=0
_filter=""
_name_filter=""
_fail_fast=0
_format="pretty"

PTYUNIT_VERSION="1.0.0"
```

These will become the opening lines of the new `_main()` function. Delete them from file scope (they'll be re-added inside `_main()` in Step 4).

- [ ] **Step 2: Move the `while` loop, validation, color setup, and counters into `_main()`**

The following blocks currently follow `_usage()` at file scope (lines 91–188):
- `while [[ $# -gt 0 ]]; do ... done` (arg parsing)
- `if ! [[ "$_jobs" =~ ... ]]` (jobs validation)
- `case "$_format" in` (format validation)
- `# ── Color setup ──` block
- `# ── Counters ──` block
- `# ── Fail-fast sentinel ──` block

These will move into `_main()` in Step 4.

- [ ] **Step 3: Move the dispatch, output/summary, and cleanup blocks into `_main()`**

The following blocks currently follow `_emit_junit()` at file scope (lines 563–653):
- `# ── Dispatch ──` block (`if [[ "$_format" == "pretty" ]]; then ... fi`, `export PTYUNIT_FILTER_NAME`, `_fail_fast_triggered=0`, `case "$_mode" in ... esac`)
- `# ── Output / Summary ──` block (`case "$_format" in ... esac`)
- `# Clean up TAP/JUnit work dirs` block
- `# Clean up fail-fast sentinel` block
- `# Exit code` block + `exit 0`

These will move into `_main()` in Step 4.

- [ ] **Step 4: Write the new `_main()` function and guard**

After `_emit_junit()` ends (after line 561), replace the dispatch-through-exit block with:

```bash
# ── Main entry point ─────────────────────────────────────────────────────────
_main() {
    # ── Flag defaults ─────────────────────────────────────────────────────────
    _mode="--all"
    _jobs=$(nproc 2>/dev/null || echo 4)
    _verbose=0
    _filter=""
    _name_filter=""
    _fail_fast=0
    _format="pretty"
    PTYUNIT_VERSION="1.0.0"

    # ── Arg parsing ───────────────────────────────────────────────────────────
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                _usage ;;
            --version)
                printf 'ptyunit %s\n' "$PTYUNIT_VERSION"; exit 0 ;;
            --unit|--integration|--all)
                _mode="$1"; shift ;;
            --debug)
                _jobs=1; _verbose=1; shift ;;
            --verbose|-v)
                _verbose=1; shift ;;
            --jobs)
                _jobs="${2:-}"
                if [[ -z "$_jobs" ]]; then
                    printf 'Error: --jobs requires a value\n' >&2; exit 2
                fi
                shift 2 ;;
            --jobs=*)
                _jobs="${1#--jobs=}"; shift ;;
            --filter)
                _filter="${2:-}"
                if [[ -z "$_filter" ]]; then
                    printf 'Error: --filter requires a pattern\n' >&2; exit 2
                fi
                shift 2 ;;
            --filter=*)
                _filter="${1#--filter=}"; shift ;;
            --name)
                _name_filter="${2:-}"
                if [[ -z "$_name_filter" ]]; then
                    printf 'Error: --name requires a pattern\n' >&2; exit 2
                fi
                shift 2 ;;
            --name=*)
                _name_filter="${1#--name=}"; shift ;;
            --fail-fast)
                _fail_fast=1; shift ;;
            --format)
                _format="${2:-}"
                if [[ -z "$_format" ]]; then
                    printf 'Error: --format requires a value\n' >&2; exit 2
                fi
                shift 2 ;;
            --format=*)
                _format="${1#--format=}"; shift ;;
            *)
                printf 'Unknown flag: %s\n' "$1" >&2; exit 2 ;;
        esac
    done

    # Validate --jobs value
    if ! [[ "$_jobs" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Error: --jobs requires a positive integer, got: %s\n' "$_jobs" >&2
        exit 2
    fi

    # Validate --format value
    case "$_format" in
        pretty|tap|junit) ;;
        *) printf 'Error: unknown format: %s (expected pretty, tap, or junit)\n' "$_format" >&2; exit 2 ;;
    esac

    # ── Color setup ───────────────────────────────────────────────────────────
    _use_color=0
    if [[ -n "${FORCE_COLOR:-}" && -z "${NO_COLOR:-}" ]]; then
        _use_color=1
    elif [[ -z "${NO_COLOR:-}" ]] && [ -t 1 ]; then
        _use_color=1
    fi

    if (( _use_color )); then
        _OK_LABEL=$'\033[0;32mOK\033[0m'
        _FAIL_LABEL=$'\033[0;31mFAIL\033[0m'
        _SKIP_LABEL=$'\033[0;33mSKIP\033[0m'
    else
        _OK_LABEL='OK'
        _FAIL_LABEL='FAIL'
        _SKIP_LABEL='SKIP'
    fi

    # ── Counters ──────────────────────────────────────────────────────────────
    _total_pass=0
    _total_fail=0
    _total_files=0
    _total_skip=0
    _failed_files=()
    _skipped_files=()

    # Suite tracking for TAP/JUnit output
    _suite_work_dirs=()
    _suite_labels=()

    # Fail-fast sentinel (file-based IPC for subshells)
    _fail_sentinel=""
    if (( _fail_fast )); then
        _fail_sentinel="${TMPDIR:-/tmp}/ptyunit-fail-$$"
    fi

    # ── Dispatch ──────────────────────────────────────────────────────────────
    if [[ "$_format" == "pretty" ]]; then
        if (( _jobs == 1 )); then
            printf 'ptyunit test runner (sequential)\n'
        else
            printf 'ptyunit test runner (%d workers)\n' "$_jobs"
        fi
    fi

    # Export name filter for test files (checked by ptyunit_test_begin)
    if [[ -n "$_name_filter" ]]; then
        export PTYUNIT_FILTER_NAME="$_name_filter"
    fi

    _fail_fast_triggered=0

    case "$_mode" in
        --unit)
            _run_suite "$TESTS_DIR/unit" "Unit"
            ;;
        --integration)
            if ! command -v python3 >/dev/null 2>&1; then
                [[ "$_format" == "pretty" ]] && printf '\nSkipping integration tests (python3 not found)\n'
            else
                _run_suite "$TESTS_DIR/integration" "Integration"
            fi
            ;;
        --all)
            _run_suite "$TESTS_DIR/unit" "Unit"
            if (( _fail_fast )) && [[ -n "${_fail_sentinel:-}" ]] && [[ -f "$_fail_sentinel" ]]; then
                _fail_fast_triggered=1
            fi
            if (( ! _fail_fast_triggered )); then
                if command -v python3 >/dev/null 2>&1; then
                    _run_suite "$TESTS_DIR/integration" "Integration"
                else
                    [[ "$_format" == "pretty" ]] && printf '\nSkipping integration tests (python3 not found)\n'
                fi
            else
                [[ "$_format" == "pretty" ]] && printf '\nSkipping integration tests (--fail-fast)\n'
            fi
            ;;
    esac

    # ── Output / Summary ──────────────────────────────────────────────────────
    case "$_format" in
        tap)
            _emit_tap
            ;;
        junit)
            _emit_junit
            ;;
        pretty)
            local_total=$(( _total_pass + _total_fail ))
            printf '\n─────────────────────────────────\n'
            printf '%d/%d assertions passed across %d file(s)\n' \
                "$_total_pass" "$local_total" "$_total_files"

            if (( _total_skip > 0 )); then
                printf 'Skipped: %d file(s)\n' "$_total_skip"
                for local_f in "${_skipped_files[@]}"; do
                    printf '  %s\n' "$local_f"
                done
            fi

            if (( ${#_failed_files[@]} > 0 )); then
                printf 'Failed files:\n'
                for local_f in "${_failed_files[@]}"; do
                    printf '  %s\n' "$local_f"
                done
            fi
            ;;
    esac

    # Clean up TAP/JUnit work dirs
    if (( ${#_suite_work_dirs[@]} > 0 )); then
        for _wd in "${_suite_work_dirs[@]}"; do
            rm -rf "$_wd"
        done
    fi

    # Clean up fail-fast sentinel
    if [[ -n "${_fail_sentinel:-}" ]]; then
        rm -f "$_fail_sentinel"
    fi

    # Exit code
    if (( ${#_failed_files[@]} > 0 )); then
        exit 1
    fi
    exit 0
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _main "$@"
```

> **Important:** No `local` declarations are used in `_main()`. All variables remain global, exactly as they were at file scope in the original run.sh. This ensures `_run_job` and `_run_suite` — which read `_verbose`, `_fail_fast`, `_fail_sentinel`, `_format`, `_jobs`, `_filter`, `_OK_LABEL`, `_FAIL_LABEL`, `_SKIP_LABEL` directly — continue to see the values set during arg parsing. Counters and tracking arrays (`_total_pass`, `_total_fail`, `_total_files`, `_total_skip`, `_failed_files`, `_skipped_files`, `_suite_work_dirs`, `_suite_labels`) also remain global so `_run_suite` can modify them in place.

> **Also remove** from file scope: the `# ── Flag parsing ──` comment block, the defaults (`_mode=`, `_jobs=`, `_verbose=`, `_filter=`, `_name_filter=`, `_fail_fast=`, `_format=`, `PTYUNIT_VERSION=`), the `while [[ $# -gt 0 ]]; do` arg loop, the validation blocks, the color setup block, the counters block, and the dispatch-through-exit block that currently lives after `_emit_junit()`.

- [ ] **Step 5: Smoke-test the refactored script behaves identically when invoked directly**

```bash
bash /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard/run.sh --version
```

Expected output: `ptyunit 1.0.0`

```bash
bash /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard/run.sh --help 2>&1 | head -5
```

Expected: shows usage header

---

### Task 3: Run new unit tests (GREEN)

- [ ] **Step 1: Run test-run-internals.sh standalone**

```bash
bash /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard/self-tests/unit/test-run-internals.sh
```

Expected: `30/30 assertions passed` (or similar — 6 `_xml_escape` + 2 `_ptyunit_now` + 8 `_main` + 6 `_emit_tap` + 8 `_emit_junit` = 30 assertions). All tests pass, no "command not found" errors.

- [ ] **Step 2: Run full suite via run.sh**

```bash
bash /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard/run.sh
```

Expected: all existing tests pass (256+ assertions), `test-run-internals.sh` is included and passes, exit 0.

> If any pre-existing test fails, investigate before proceeding — do not commit broken tests.

---

### Task 4: Verify coverage improvement

- [ ] **Step 1: Run coverage report**

```bash
cd /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard
bash coverage.sh
```

Expected: `run.sh` coverage ≥ 50% (was 0%). Overall project coverage ≥ 53% (was ~47%).

> If `run.sh` coverage is below 50%, check whether `test-run-internals.sh` is being traced. The coverage scanner must pick it up from `self-tests/unit/`. Run `bash coverage.sh --help` to confirm the scan path.

---

### Task 5: Commit

- [ ] **Step 1: Stage and commit**

```bash
cd /Users/allenmccabe/.config/superpowers/worktrees/ptyunit/feat/run-sh-main-guard
git add run.sh self-tests/unit/test-run-internals.sh
git commit -m "feat(run): add _main() guard so run.sh can be sourced for unit testing

Moves all execution code into _main(). Functions stay at file scope.
Adds self-tests/unit/test-run-internals.sh with 30 assertions covering
_xml_escape, _ptyunit_now, _main arg validation, _emit_tap, _emit_junit.
run.sh coverage improves from 0% to >= 50%."
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bash self-tests/unit/test-run-internals.sh` | Run new unit tests standalone |
| `bash run.sh` | Full suite regression check |
| `bash coverage.sh` | Verify coverage improvement |
| `bash run.sh --version` | Smoke-test main guard fires |

## Success Criteria

- [ ] All 256+ pre-existing tests still pass
- [ ] `test-run-internals.sh` passes standalone
- [ ] `run.sh` coverage ≥ 50%
- [ ] Overall project coverage ≥ 53%
- [ ] `bash run.sh`, `bash run.sh --help`, `bash run.sh --version` all behave identically to before
