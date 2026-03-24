# Project: ptyunit
## Master Tracking Sheet

This document is the stateless source of truth for building and launching ptyunit as a
standalone open-source test framework. Start every new session by reading this file.
Update task status here when work completes.

**Repo:** `fissible/ptyunit` (https://github.com/fissible/ptyunit)
**Extracted from:** `fissible/shellframe` — the test infrastructure at `tests/`

---

## What ptyunit is

ptyunit is a test framework for bash scripts and terminal UI applications. It has three
independent layers that work together or standalone:

1. **Assertion library** (`assert.sh`) — 22 assertions (`assert_eq`, `assert_contains`,
   `assert_match`, `assert_gt/lt/ge/le`, `assert_file_exists`, `assert_line`, etc.),
   section labeling (`test_that`/`test_it`/`test_they`), `describe`/`end_describe` nesting,
   `test_each` parameterized tests, per-test `ptyunit_setup`/`ptyunit_teardown`,
   `ptyunit_skip_test` per-section skip, and PWD isolation. Auto-sources `mock.sh`.

2. **Mock library** (`mock.sh`) — `ptyunit_mock` creates command mocks (PATH-based) or
   function mocks (auto-detected). Records calls and arguments. 5 verification assertions
   (`assert_called`, `assert_not_called`, `assert_called_times`, `assert_called_with`).
   Heredoc bodies for smart mocks. Auto-cleanup at `test_that` boundaries.

3. **PTY integration driver** (`pty_run.py`) — runs a bash script inside a real
   pseudoterminal (`pty.fork()`), scripts keystroke sequences into it, strips ANSI escapes,
   and returns plain text output. This is what makes it possible to test TUI applications
   that render to `/dev/tty` — something no other bash test framework supports.

4. **Test runner** (`run.sh`) — discovers `tests/unit/test-*.sh` and
   `tests/integration/test-*.sh`, runs each in a streaming worker pool, aggregates
   pass/fail/skip counts. Supports `--filter` (filename), `--name` (test section name),
   `--fail-fast`, `--format tap|junit|pretty`, `--jobs N`, `--debug`, `-h`/`--help`.

5. **Code coverage** (`coverage.sh` + `coverage_report.py`) — PS4-based line tracing,
   text/json/html reports, `--min=N` CI gate. Works on bash 3.2.

6. **Docker cross-version matrix** (`docker/`) — bash 3.2, 4.4, 5.x on Alpine.

7. **Showdown benchmark** (`bench/showdown/`) — head-to-head comparison against bats-core
   with equivalent test suites over 4 bash libraries. Measures pass/fail alignment and
   timing. Result: 15x faster, full alignment.

---

## Current state

**Self-tests:** 221/221 assertions across 13 unit + 2 integration files (231 total).

**Core files:**

| File | Lines | Purpose |
|------|-------|---------|
| `assert.sh` | ~400 | Assertion library + lifecycle + describe/params |
| `mock.sh` | ~230 | Mocking and stubbing |
| `run.sh` | ~380 | Test runner with TAP/JUnit/pretty output |
| `pty_run.py` | ~160 | PTY driver |
| `coverage.sh` | ~165 | Coverage orchestrator |
| `coverage_report.py` | ~335 | Coverage report generator (timestamped html + index nav) |

**Self-test files:**

| File | Assertions | Tests |
|------|-----------|-------|
| `test-assert.sh` | 20 | Original assertion functions |
| `test-assert-extended.sh` | 23 | not_eq, true, false, null, not_null, skip, require_bash |
| `test-assert-new.sh` | 30 | match, file_exists, line, gt/lt/ge/le (uses describe + test_each) |
| `test-mock.sh` | 36 | Command mocks, function mocks, auto-cleanup, verification (uses describe) |
| `test-describe.sh` | 12 | describe/end_describe nesting |
| `test-params.sh` | 15 | test_each parameterized tests |
| `test-name-filter.sh` | 8 | --name filter |
| `test-runner.sh` | 21 | Runner core: jobs, parallel, skip, timing |
| `test-runner-hooks.sh` | 8 | setUp/tearDown, PTYUNIT_TEST_TMPDIR, color |
| `test-runner-filter.sh` | 14 | --filter, --fail-fast, --format validation |
| `test-runner-format.sh` | 16 | TAP and JUnit output (uses describe) |
| `test-setup-teardown.sh` | 8 | Per-test ptyunit_setup/teardown, PWD isolation |
| `test-skip-test.sh` | 10 | Per-test ptyunit_skip_test |

---

## Milestones

| Milestone | Status |
|-----------|--------|
| **M1: Standalone** — extracted from shellframe, all tests pass | **done** |
| **M2: Self-tested** — ptyunit tests its own components | **done** |
| **M3: Public launch** — README + guide, Docker matrix green | **done** |
| **M4: Coverage** — PS4-based coverage with text/json/html reports | **done** |
| **M5: Full parity** — setUp/tearDown, JUnit/TAP, assertions, color, skipping | **done** |
| **M6: Beyond parity** — mocking, describe, test_each, --name, --fail-fast, --help | **done** |

---

## Competitive position (as of 2026-03-20)

| Capability | ptyunit | bats-core | shellspec | shunit2 |
|---|---|---|---|---|
| PTY / TUI testing | **Yes** | No | No | No |
| Built-in mocking | **Yes (auto-cleanup)** | No (external) | Yes | No |
| Parallel execution | Yes (built-in, bash 3.2) | Yes (GNU parallel) | Yes | No |
| Code coverage | Yes (built-in PS4) | No (external kcov) | Yes (kcov) | No |
| TAP output | Yes | Yes | Yes | No |
| JUnit XML | Yes | Yes | Yes | No |
| Parameterized tests | **Yes (test_each)** | No | Yes | No |
| Nestable describe | **Yes** | No | Yes | No |
| Test name filter | Yes (--name) | Yes (--filter) | Yes | Yes |
| Fail-fast | Yes | Yes | Yes | No |
| Numeric assertions | Yes (gt/lt/ge/le) | Manual | Matchers | No |
| Speed (vs bats) | **15x faster** | Baseline | — | — |

**Remaining gaps:** `run` helper (capture stdout+stderr+status in one call), negative
line indices in assert_line, `refute_*` semantic inverses. All are nice-to-haves, not
blockers.

---

## Backlog

| # | Feature | Effort | Status |
|---|---------|--------|--------|
| 12 | Per-test coverage capture: run each test file individually; emit per-test coverage sets | M | todo |
| 14 | Redundancy detection: compare per-test coverage sets; report subset tests | L | todo |
| — | `run` helper: capture stdout+stderr+exit in one call like bats | S | todo |
| — | `assert_line` negative indices (-1 = last line) | XS | todo |
| — | `refute_output`, `refute_line` semantic inverses | XS | todo |
| — | CI workflow (GitHub Actions) for ptyunit itself | S | todo |
| — | Update `fissible/shellframe` to use ptyunit as submodule | S | todo |

---

## File layout

```
ptyunit/
├── assert.sh                        # assertion library + lifecycle + describe + test_each
├── mock.sh                          # mocking and stubbing (auto-sourced by assert.sh)
├── run.sh                           # test runner
├── pty_run.py                       # PTY driver
├── coverage.sh                      # coverage orchestrator
├── coverage_report.py               # coverage report generator (text/json/html)
├── README.md                        # user-facing docs
├── PROJECT.md                       # this file
├── examples/
│   ├── confirm.sh                   # minimal yes/no prompt demo
│   └── menu.sh                      # minimal arrow-key menu demo
├── bench/
│   ├── concurrency.sh               # parallelism benchmark
│   └── showdown/                    # ptyunit vs bats-core benchmark
│       ├── run-showdown.sh
│       ├── lib/                     # 4 bash libraries under test
│       ├── ptyunit/                 # ptyunit test suites
│       └── bats/                    # equivalent bats test suites
├── self-tests/
│   ├── unit/
│   │   ├── test-assert.sh           # 20 assertions
│   │   ├── test-assert-extended.sh  # 23 assertions
│   │   ├── test-assert-new.sh       # 30 assertions (describe + test_each)
│   │   ├── test-mock.sh             # 36 assertions (describe)
│   │   ├── test-describe.sh         # 12 assertions
│   │   ├── test-params.sh           # 15 assertions
│   │   ├── test-name-filter.sh      # 8 assertions
│   │   ├── test-runner.sh           # 21 assertions
│   │   ├── test-runner-hooks.sh     # 8 assertions
│   │   ├── test-runner-filter.sh    # 14 assertions
│   │   ├── test-runner-format.sh    # 16 assertions (describe)
│   │   ├── test-setup-teardown.sh   # 8 assertions
│   │   └── test-skip-test.sh        # 10 assertions
│   └── integration/
│       ├── test-confirm.sh          # 8 assertions (PTY)
│       └── test-menu.sh             # 10 assertions (PTY)
└── docker/
    ├── run-matrix.sh
    ├── Dockerfile.bash3
    ├── Dockerfile.bash4
    └── Dockerfile.bash5
```

---

## Session handoff notes
> Update this section at the end of each session.

_Last updated: 2026-03-23 (session 9)_

**274/274 tests pass. On v1.1.1.**

Completed 2026-03-23 (session 9 — coverage time bug fix, test file, v2 HTML report):

- `coverage_report.py` (main): fixed `_format_display_date` 12h→24h bug (nav labels showed 9→11→1→2 at noon crossing). Changed `%I` to `%H`. Also `.gitignore` added.
- `self-tests/unit/test-coverage-report.sh` (new): 8 unit tests for `_format_display_date`, `_parse_report_dt`, and `_ptyunit_version`.
- Homebrew formula (`fissible/homebrew-tap`): added `"VERSION"` to `libexec.install` — fixes "ptyunit vunknown" in HTML reports generated via Homebrew install.
- Renamed shellframe coverage files with wrong UTC timestamps to accurate PDT mtimes; regenerated index.
- `feat/coverage-report-v2` branch (worktree at `ptyunit-coverage-v2/`): complete rewrite of HTML coverage report featuring folder hierarchy, sortable table, coverage comparison vs prev run (JSON sidecar), cyclomatic complexity badges, GitHub-style language bar, large color-tinted total %, sticky footer, active nav link in index. 274/274 tests still pass. Report generated and visually verified.

**Downstream actions needed (flag for PM):**
- Push main branch (2 commits ahead of origin: 24h time fix + unit test file)
- Push `feat/coverage-report-v2` branch (needs PR)
- Push homebrew-tap main (VERSION install fix) then `brew upgrade ptyunit` in shellframe
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.1.1)

**Next steps:**
1. PR: `feat/coverage-report-v2` → main, then release v1.2.0
2. Update `fissible/shellframe` submodule pointer + Homebrew upgrade
3. CI workflow (GitHub Actions) for ptyunit itself
4. Per-test coverage capture + redundancy detection

---

Completed 2026-03-22 (session 8 — coverage bug fix + HTML report improvements + release):

- `coverage_report.py`: fixed bug where function declaration lines (`foo() {`) always showed as missed — bash's `set -x` never traces function definitions, only statements inside functions when called. Added `_FUNC_DEF_RE` regex to `count_source_lines()` to exclude function declaration lines from the executable set.
- `coverage_report.py`: HTML report file names in summary table now link to per-file detail sections (added `id` anchors on `<h2>` elements, `<a href="#anchor">` in table rows).
- `coverage_report.py`: HTML report now shows ptyunit version (read from `VERSION` file via `_ptyunit_version()`).
- Released v1.1.0 (`bash release.sh minor`) — tagged and pushed.

**Downstream actions needed (flag for PM):**
- Homebrew formula: bump ptyunit pin from v1.0.0 → v1.1.0
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.1.0)

**Next steps:**
1. Update `fissible/shellframe` submodule pointer to v1.1.0 (+ update Homebrew formula)
2. CI workflow (GitHub Actions) for ptyunit itself
3. Per-test coverage capture + redundancy detection
4. Minor ergonomics: `run` helper, negative line indices, `refute_*`

---

**Previous session (2026-03-20, session 6 — competitive parity + beyond):**

Completed 2026-03-20 (session 6 — competitive parity + beyond):

**Assertions & lifecycle:**
- 7 new assertions: `assert_match`, `assert_file_exists`, `assert_line`, `assert_gt/lt/ge/le`
- Per-test skip: `ptyunit_skip_test [reason]` — flag-based, resets at next `test_that`
- Per-test setup/teardown: `ptyunit_setup`/`ptyunit_teardown` functions, auto-called at section boundaries
- PWD isolation: save/restore `$PWD` between test sections
- Consistent `|| true` on all arithmetic (fixes latent `set -e` bug in original `assert_eq`/`assert_contains`)

**Runner:**
- `--filter PATTERN` — filename substring match
- `--name PATTERN` — test section name substring match (via `PTYUNIT_FILTER_NAME` env var)
- `--fail-fast` — sentinel file IPC, stops dispatching on first failure
- `--format tap` — TAP version 13 output
- `--format junit` — JUnit XML output
- `-h`/`--help` — usage statement

**Mocking (new file: mock.sh):**
- `ptyunit_mock` — auto-detects function vs command mock
- PATH-based command mocks, eval-based function mocks
- Heredoc bodies for conditional mock behavior
- Call recording (count + per-call args) to file-based state
- Auto-cleanup at `test_that` boundaries (integrated into lifecycle)
- 5 verification assertions + 2 query helpers
- Auto-sourced by assert.sh

**Describe & parameterized tests:**
- `describe`/`end_describe` — nestable name stack, produces `[outer > inner > test]` in output
- `test_each` — pipe-delimited heredoc rows, one `test_that` section per row

**Benchmark:**
- `bench/showdown/` — 4 bash libraries (math, string, filesystem, config parser)
- Equivalent test suites in ptyunit (130 assertions) and bats-core (103 @tests)
- Full pass/fail alignment, ptyunit 15x faster (873ms vs 13175ms)
- `run-showdown.sh` orchestrator compares alignment and timing

**README:**
- Complete rewrite with accessible tone
- Technical details in blockquote callouts
- Documents all features with concise code examples

**Bugs found during session:**
1. Missing `|| true` on arithmetic in original `assert_eq`/`assert_contains` (latent `set -e` bug)
2. Test fixture: wrong expected value in strlib replace test ("h-ll-" vs "hell-")
3. Test fixture: macOS `$TMPDIR` trailing slash causing double-slash path mismatch

**Self-tests: 72 → 231 assertions (13 unit + 2 integration files)**

Previous sessions: see git history. Key commits:
- `5441349` — assertions, lifecycle, TAP/JUnit, --filter, --fail-fast
- `bf38c1a` — showdown benchmark
- `30d69f2` — mocking, describe, test_each, --name, --help, README rewrite

**Next steps:**
1. CI workflow (GitHub Actions) for ptyunit itself
2. Per-test coverage capture + redundancy detection
3. Update `fissible/shellframe` submodule
4. Minor ergonomics: `run` helper, negative line indices, `refute_*`
