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

_Last updated: 2026-03-25 (session 16)_

**477/477 tests pass. Released v1.3.0. Submodules bumped in shellframe, shellql, seed.**

Completed 2026-03-25 (session 16 — mock.sh 100% coverage + v1.3.0 release):

- Added heredoc detection to `coverage_report.py` `count_source_lines()`: lines between `<< WORD` and `WORD` terminator are no longer counted as executable (they run in a subprocess, never traced inline). Also added `_HEREDOC_RE` constant.
- Added `# @pty_skip` block pragmas to all unreachable branches in `mock.sh`: 2 infrastructure error handlers (mktemp/mkdir failure), and all 5 mock assertion failure `else`/`if` blocks. mock.sh is now at **100%**.
- Added 2 new tests to `test-mock-extended.sh`: `mock_args` without explicit N (retrieves last call), and extra positional arg after flags (exercises `*)` break branch in ptyunit_mock's option parser).
- Released **v1.3.0** (`bash release.sh minor`) and pushed. Submodule bumps in shellframe, shellql, seed completed by PM.
- Total coverage: **83% (559/672)** — assert.sh 96%, mock.sh 100%, run.sh 71%.

**Next steps:**
1. CI workflow (GitHub Actions) for ptyunit itself
2. run.sh coverage improvement (71%, 105 missed lines) — next major opportunity
3. Optional: trailing-incomplete-sequence mitigation (ticket stub in #18)

**Next steps:**
1. CI workflow (GitHub Actions) for ptyunit itself
2. Update `fissible/shellframe` submodule pointer + Homebrew upgrade
3. Optional: trailing-incomplete-sequence mitigation (ticket stub in #18)

---

Completed 2026-03-24 (session 14 — coverage fixes + post-release housekeeping):

- Fixed coverage reporting: `coverage.sh` now uses `BASH_XTRACEFD=3` (dedicated fd) so PS4 traces never reach fd 2. Prevents `run()` helper's `2>&1` from capturing trace output into `$output`. All 433 assertions pass cleanly under coverage mode.
- Fixed `release.sh` to update `package.json` version on every release (via `sed -i`). Also added `package.json` to the release commit's `git add`.
- Fixed `coverage_report.py`: `detect_app_info()` now reads `VERSION` file first for app version, falls back to `package.json`. Prevents stale `package.json` version from appearing in coverage reports.
- Manually synced `package.json` to `1.2.0` (was stale at `1.1.1` after v1.2.0 release).
- Confirmed: no other fissible repos with `release.sh` have a `package.json` at root. `accord` has `composer.json` but no `"version"` field — nothing to update.
- Coverage: 43% (all clean, 433/433 assertions).

**Downstream actions needed (flag for PM):**
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.2.0)

**Next steps:**
1. Update `fissible/shellframe` submodule pointer + Homebrew upgrade
2. CI workflow (GitHub Actions) for ptyunit itself
3. Optional: trailing-incomplete-sequence mitigation (ticket stub in #18)

---

Completed 2026-03-24 (session 12 — ANSI stripping bug fix):

- Investigated issue [#18](https://github.com/fissible/ptyunit/issues/18): `ANSI_RE` ordering bug — Fe catch-all arm `[@-Z\\-_]` matched single-byte openers for OSC (`]`), DCS (`P`), SOS (`X`), PM (`^`), APC (`_`) before their dedicated multi-byte arms, leaving payloads unstripped in output.
- Fixed `ANSI_RE` in `pty_run.py`: promoted ST-terminated arm `[PX^_][^\x1b]*\x1b\\` and OSC arm before Fe. Fe now only catches true single-char sequences.
- Added `PTY_RAW=1` docstring warning — bypasses all stripping; corrupts parent terminal if stdout reaches a live terminal.
- Added `self-tests/integration/test-pty-ansi-strip.sh`: 13 new regression assertions covering OSC (BEL + ST terminated), DCS, SOS, PM, APC, and raw ESC byte presence.
- Investigation conducted via Rubber Ducky pair-programming session (`~/.config/rubber-ducky/rooms/investigation_of_pty_run2/`).

**Downstream actions needed (flag for PM):**
- Submodule bump needed in: shellframe, shellql, seed (pick up ANSI fix)
- Consider releasing v1.1.2 (patch) for the ANSI stripping fix

**Next steps:**
1. Fix `release.sh` to update `package.json` version (XS) — before next release
2. Update `fissible/shellframe` submodule pointer + Homebrew upgrade
3. CI workflow (GitHub Actions) for ptyunit itself
4. Optional: trailing-incomplete-sequence mitigation (ticket stub in #18)

---

Completed 2026-03-23 (session 11 — v2 report UI feedback + version fixes):

- `package.json` (main + feat): synced version from stale `1.0.0` → `1.1.1`. Root cause: `release.sh` updates VERSION and git tag but not `package.json`. Should be addressed before next release.
- `feat/coverage-report-v2` (worktree): iterated on HTML report based on visual review:
  - Fixed double-spacing in source view: root cause was `'\n'.join(source_sections)` putting literal newlines between `<span>` elements inside `<pre>`. Fix: collect line spans into a local list, join with `''`.
  - Fixed 24h time in report header/footer (`dt_str` was still using `%H:%M`; changed to call `_format_display_date()`).
  - Fixed directory prefix appearing after filename in Files table — moved before.
  - Removed language analysis bar (pointless for bash-only tool).
  - Added bash syntax highlighting: keywords (blue), strings (orange), comments (green italic), variables (light blue) via `_highlight_bash()` tokenizer.
  - CSS: font-size 13→14px, coverage bar 60×4→80×8px, code background `#111`, line-number border-right separator, tighter line-height (1.45).
  - Suppressed redundant "ptyunit v{version}" meta line when measuring ptyunit itself.

**Known gap (flag for PM):**
- `release.sh` does not update `package.json` — causes stale version display in coverage reports. Should be added to release procedure before v1.2.0.

**Downstream actions needed (flag for PM):**
- Push main branch (2 commits ahead of origin)
- Push `feat/coverage-report-v2` branch (needs PR — awaiting user approval)
- Push homebrew-tap main (VERSION install fix) then `brew upgrade ptyunit` in shellframe
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.1.1)

**Next steps:**
1. User approval of v2 report → PR `feat/coverage-report-v2` → main, release v1.2.0
2. Fix `release.sh` to update `package.json` version (XS)
3. Update `fissible/shellframe` submodule pointer + Homebrew upgrade
4. CI workflow (GitHub Actions) for ptyunit itself

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
