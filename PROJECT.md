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

**Self-tests:** 662/662 assertions across 32 files (647 bash + 15 Python). v1.5.1 current.

**Core files:**

| File | Lines | Purpose |
|------|-------|---------|
| `assert.sh` | ~400 | Assertion library + lifecycle + describe/params |
| `mock.sh` | ~230 | Mocking and stubbing |
| `run.sh` | ~840 | Test runner with TAP/JUnit/pretty output; discovers test-*.sh + test_*.py |
| `pty_run.py` | ~160 | PTY driver (legacy) |
| `pty_session.py` | ~180 | PTY screen inspection engine (pyte-based, Screen + PTYSession) |
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

_Last updated: 2026-03-26 (session 29)_

**617/617 assertions pass (unit). v1.5.2 current. Hardening complete.**

---

### Next session: pick up here

**State:** All hardening-complete issues (#36–#38) are closed. No open tickets.

**Completed this session (session 29):**

| What | Detail |
|------|--------|
| CI pytest fix | `ci.yml` + `test.yml`: use `python3 -m pip install pytest pyte --break-system-packages` — `pip3 install` was not reaching `/usr/bin/python3` on Ubuntu 24.04 runners (`4842c26`) |
| [#37](https://github.com/fissible/ptyunit/issues/37) PTYSession behavioral self-tests | `self-tests/unit/test_pty_session.py` — 8 tests: stdout after entry, first-byte semantics, exit_code, no-zombie, fd close, send() OSError swallow, timeout |
| [#38](https://github.com/fissible/ptyunit/issues/38) Docker matrix CI | `test.yml` pytest/pyte install in Alpine unit matrix + ubuntu integration job (`a7d46a5`) |
| [#36](https://github.com/fissible/ptyunit/issues/36) Hostile-environment test suite | `self-tests/hostile/` — 5 scenarios, `run-hostile.sh`, `hostile.yml` weekly CI, `ptyunit help pty` docs (`f498919`) |

**Hardening complete path: DONE.** All issues #22–#38 closed.

**Next: cut v1.5.3** — `bash release.sh patch`. 4 commits since v1.5.2 (CI fixes + test additions). PM decision required; flag for `projects/`.

**Consumer install model:** shellframe, shellql, and seed use the **Homebrew-installed** ptyunit. No submodule bumps needed. When v1.5.3 is cut and the Homebrew tap is updated, consumers pick it up automatically.

**Other backlog:**

| # | Feature | Effort |
|---|---------|--------|
| 12 | Per-test coverage capture | M |
| 14 | Redundancy detection | L |
| — | `run` helper: capture stdout+stderr+exit in one call | S |

---

### Session 27 (archived)

**Completed this session (session 27):**

| Issue | What shipped |
|-------|-------------|
| [#32](https://github.com/fissible/ptyunit/issues/32) | `_drain_until_stable()` in `pty_run.py`; first-byte gate + hard deadline; 5 unit tests incl. both Evidence Mode adversarial tests |
| [#34](https://github.com/fissible/ptyunit/issues/34) | `BASH_ENV` coverage injection in `PTYSession.__enter__`; bash 4.1+ guard; exception-safe restore order; 6 unit tests incl. Breaker pass |
| [#33](https://github.com/fissible/ptyunit/issues/33) | `PTYUNIT_HOME` auto-export in `run.sh` + `coverage.sh`; invalid-path error |
| [#35](https://github.com/fissible/ptyunit/issues/35) | `--unit` stderr warning; README coverage guide updated |

---

Completed 2026-03-26 (session 25 — hardening audit, all 10 bugs fixed):

Full adversarial audit of all 5 components via Rubber Ducky room (`ptyunit-hardening`).
10 GitHub issues (#22–#31) filed and all closed in this session.

**assert.sh** (3 fixes, committed `a3b9b1c`):
- #22 `assert_count` infinite loop on empty needle — guard added
- #28 `ptyunit_skip_test` double-count on repeated calls — idempotency guard added
- #25 `describe` stack corruption on names containing ` > ` — replaced delimited string with indexed array; join via explicit loop (IFS trick fails: `${array[*]}` only uses first char of IFS)

**mock.sh** (1 fix, committed `c020b7d`):
- #24 `assert_called_with` couldn't distinguish `'foo bar'` (1 arg) from `foo bar` (2 args) — switched to NUL-delimited storage (`printf '%s\0' "$@"`) and binary comparison (`cmp -s`)

**pty_session.py** (2 fixes + docs, committed `36f02e6`):
- #26 `send()` raises unhandled `OSError` if child already exited — wrapped in try/except
- #27 `wait_for_stable` starts stability clock at fork time; blank screen declared stable if process slow to start — clock now starts after first byte arrives
- #23 Python 3.9+ documented in docstring (`os.waitstatus_to_exitcode`)

**pty_run.py** (docs, committed `5c2d9cb`):
- #23 Python 3.9+ documented; numeric kill signals replaced with `signal.SIGTERM`/`SIGKILL`

**run.sh** (3 fixes, committed `0ef4d2b`):
- #29 Temp dirs leaked on SIGINT/SIGTERM — EXIT trap + `_all_work_dirs[]` registry added
- #30 `mkfifo` failure caused unbounded parallelism — guard added in both `_run_suite` and `_run_py_suite`
- #31 `--fail-fast` not checked between bash and Python suites in `--unit`/`--integration` modes — check added (was already correct in `--all`)

**Decisions (from RD room):**
- Mock arg format: NUL-delimited bytes, not space-separated (round-trip fidelity for args with spaces)
- Python min version: 3.9 (document, don't add runtime check)
- Stability algorithm: start clock after first byte (chosen over "wait for first content change")

**Next steps:**
1. **Cut v1.5.2** — `bash release.sh patch`. 6 commits since v1.5.1, all bug fixes. (PM decision — flag for `projects/`)
2. **Submodule bumps**: shellframe, shellql, seed (pick up v1.5.1 now; v1.5.2 when cut) — flag for PM.
3. `pty_session.py` still has no `PTYSession` behavioral self-tests (only `test_screen.py` covers the Screen wrapper). Worthwhile follow-up ticket.

---

Completed 2026-03-26 (session 24 — CI fix + v1.5.1 release):

- Fixed 3 bugs exposed by the targeted coverage tests added in session 23:
  1. `_run_py_suite` filter bug: `files=("${_filtered[@]:-}")` set `files=("")` when no files matched, bypassing the empty guard and calling `_run_py_job ""`. Fixed to use same `if (( ${#_filtered[@]} > 0 ))` pattern as `_run_suite`.
  2. `_run_py_job` bash 3.2 empty array: `"${_ff_args[@]}"` with empty array + `set -u` crashes bash 3.2. Fixed with `${_ff_args[@]+"${_ff_args[@]}"}` idiom.
  3. CI: no `bootstrap-command` in `ci.yml` meant `pytest` was never installed on runners. Added `pip3 install pytest`.
- Released **v1.5.1** (`bash release.sh patch`). Homebrew tap bumped to v1.5.1.
- 634/634 assertions pass (was 585/600 — 15 bash tests now pass + all Python tests pass in CI).

**Decisions:**
- None new.

**Next steps:**
1. Submodule bumps: shellframe, shellql, seed (v1.5.1) — flag for PM.
2. `pty_session.py` still has no direct `PTYSession` behavioral tests.
3. `run.sh` coverage opportunity still open (next major opportunity).

**PM ticket proposal (XS — in `fissible/.github`):**
- Add optional Homebrew formula bump step to `release.sh`. Pattern: check for a `.homebrew-tap` config file in repo root (like `release.sh` already does for `package.json`). If present, file specifies tap path and formula name; script fetches sha256, updates the formula, commits, and pushes. Repos without `.homebrew-tap` are unaffected — safe to copy `release.sh` everywhere. Suggest: `echo "fissible/homebrew-tap Formula/ptyunit.rb" > .homebrew-tap`.

---

Completed 2026-03-26 (session 23 — help subcommand + coverage improvements):

- Implemented `ptyunit help [topic]` (11 topics: coverage, pty, mocking, params, describe, setup-teardown, filters, formats, install, skip, matrix). New files: `help.sh`, `self-tests/unit/test-help.sh` (66 assertions). `run.sh` wired with 2-line intercept at top of `_main()`.
- Added targeted coverage tests for install detection, flag parsing (`=` forms), and `_main` dispatch paths. run.sh: 84% → 85%; help.sh: new at 94%.
- Released **v1.5.0** (`bash release.sh minor`). Homebrew tap bumped to v1.5.0 (`help.sh` and `pty_session.py` added to formula `libexec.install`).
- Coverage HTML report improvements: thinner nav scrollbar (3px), auto-scroll to active (rightmost) tab on load, unified scrollbar style across nav and iframe content, case branch labels now inherit coverage from their first body line (Option B — run.sh jumps 85% → 89%, total 91% → 93% with `--all`).
- Confirmed `--all` is the right standard for coverage reports (integration tests cover `examples/confirm.sh` and `examples/menu.sh`; `--unit` only gives 83%).
- `ptyunit help` added to README under new `## Help` section.

**Decisions:**
- Coverage default: `--all --src=.` (not `--unit`); documents honestly at 93%.
- Case label coverage: Option B (inherit from branch body), not exclusion — shows which branches were exercised.

**Next steps:**
1. Submodule bumps: shellframe, shellql, seed (v1.5.0) — flag for PM.
2. `pty_session.py` has no direct self-tests beyond `test_screen.py` (Screen wrapper only). No `PTYSession` behavioral tests in self-tests suite.
3. v1.5.1 pending: 2 `fix(coverage)` commits (scrollbar style + case labels). Cut when convenient.

---

Completed 2026-03-25 (session 21 — run.sh Python test discovery):

- Implemented [#21](https://github.com/fissible/ptyunit/issues/21) — `run.sh` now discovers and runs `test_*.py` files alongside `test-*.sh` in unit and integration directories.
- Added `_run_py_job()` (runs one pytest file, parses `N passed`/`M failed` from summary) and `_run_py_suite()` (streaming parallel pool, same fd-semaphore design as `_run_suite`).
- Python tests respect `--jobs`, `--fail-fast` (→ pytest `--exitfirst`), `--filter`, `--format tap|junit|pretty`, `--verbose`.
- TAP and JUnit output include Python test file results via shared `_suite_work_dirs` mechanism.
- Issue #21 closed.

**Downstream actions needed (flag for PM):**
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.4.0 — unchanged from prior sessions; pty_session.py is a new optional file, no breaking changes)

**Next steps:**
1. run.sh coverage improvement (71%, 105 missed lines) — next major opportunity
2. Submodule bumps: shellframe, shellql, seed (v1.4.0 + pick up confirm.sh fix)

Completed 2026-03-25 (session 20 — pty_session.py implementation):

- Implemented [#20](https://github.com/fissible/ptyunit/issues/20) — `pty_session.py` + `PTYSession` fully shipped and merged to `main`.
- New files: `pty_session.py`, `requirements-screen.txt`, `conftest.py`, `self-tests/unit/test_screen.py`, `self-tests/integration/test_confirm.py`
- Fixed `examples/confirm.sh`: `$'...'` quoting for ESC sequences (was silently rendering literal `\033`), and spacing symmetry `[ No  ]` → `[ No ]`
- Notable bugs caught during review: `__enter__` cleanup guard (child orphan on `TimeoutError`), `waitpid` EOF race fix, ANSI_RE coverage gap in test
- Implementation notes: `close(master_fd)` before `waitpid` in `__exit__` (macOS deadlock fix); blocking `waitpid` fallback in `send()` when `_eof` is True

**Downstream actions needed (flag for PM):**
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.4.0 — unchanged from prior session; pty_session.py is a new optional file, no breaking changes)

**Next steps (as of session 20 close):**
1. ~~Open XS ticket: `run.sh` `.py` test discovery~~ → done (issue #21, session 21)
2. run.sh coverage improvement (71%, 105 missed lines) — next major opportunity
3. Submodule bumps: shellframe, shellql, seed (v1.4.0 + pick up confirm.sh fix)

Completed 2026-03-25 (session 19 — post-release housekeeping + implementation plan):

- Generated implementation plan for [#20](https://github.com/fissible/ptyunit/issues/20) via `writing-plans` — at `docs/superpowers/plans/2026-03-25-pty-session-engine.md`.
- Closed rubber-ducky room `ptyunit-pyte-engine` — design phase complete, Allen approved.
- Added `.claude/` and `*.json-e` to `.gitignore`.

Completed 2026-03-25 (session 18 — CI bug fixes + release + PTYSession design):

- Merged PR #19 (`fix/xml-escape-bash-compat`): two CI bug fixes:
  - `_xml_escape` in `run.sh`: replaced bash `${//}` substitutions with `sed -e` chains; bash 5.0/5.2 broke `\&` and `&` semantics in different directions — sed's `\&` is POSIX-stable.
  - `fs_tmpfile`/`fs_tmpdir` in `bench/showdown/lib/fslib.sh`: guarded against unbound `TMPDIR` under `set -u` and trailing slash on macOS.
- Released **v1.4.0** (minor — includes feat: PTY child coverage instrumentation from session 17).
- Designed and spec'd `pty_session.py` — PTY screen inspection engine using pyte as terminal emulator. Spec at `docs/superpowers/specs/2026-03-25-ptyunit-pyte-engine-design.md`, status: **Approved**.
- Filed [#20](https://github.com/fissible/ptyunit/issues/20) — implementation ticket for `pty_session.py` + `PTYSession`.

**Downstream actions needed (flag for PM):**
- Submodule bump needed in: shellframe, shellql, seed (pick up v1.4.0)

**Next steps:**
1. Implement `pty_session.py` per approved spec and plan — issue [#20](https://github.com/fissible/ptyunit/issues/20), effort S (1–2h), plan at `docs/superpowers/plans/2026-03-25-pty-session-engine.md`
2. After first `.py` test exists: add `run.sh` `.py` test discovery (separate XS issue)
3. run.sh coverage improvement (71%, 105 missed lines) — next major opportunity
4. Optional: trailing-incomplete-sequence mitigation (ticket stub in #18)

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
