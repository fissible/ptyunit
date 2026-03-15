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

1. **Assertion library** (`assert.sh`) — `assert_eq`, `assert_contains`, `assert_output`,
   section labeling, pass/fail counters, and a summary function with a meaningful exit code.
   Zero dependencies; source it and write tests.

2. **PTY integration driver** (`pty_run.py`) — runs a bash script inside a real
   pseudoterminal (`pty.fork()`), scripts keystroke sequences into it, strips ANSI escapes,
   and returns plain text output. This is what makes it possible to test TUI applications
   that render to `/dev/tty` — something no other bash test framework supports.

3. **Test runner** (`run.sh`) — discovers `tests/unit/test-*.sh` and
   `tests/integration/test-*.sh`, runs each in a subshell, aggregates pass/fail counts,
   and exits non-zero on any failure. Silently skips integration tests if `python3` is
   absent.

4. **Docker cross-version matrix** (`tests/docker/`) — runs the full suite against bash
   3.2 (simulates macOS), bash 4.4, and bash 5.x in isolated Alpine containers with
   Python installed. A failure in any version is a bug.

---

## Effort key

| Symbol | Size | Time estimate |
|--------|------|---------------|
| XS     | Tiny | < 1 hour      |
| S      | Small | 1–2 hours    |
| M      | Medium | ~half day   |
| L      | Large | ~1 day       |
| XL     | X-Large | 2–3 days  |

---

## Dependency graph

```
Phase 1 (core extraction — decouple from shellframe)
    │
    ├── Phase 2 (ptyunit's own unit tests — test assert.sh itself)
    │
    ├── Phase 3 (example fixture scripts — minimal bash scripts to drive via PTY)
    │       │
    │       └── Phase 4 (integration tests — drive examples with pty_run.py)
    │
    └── Phase 5 (documentation — README, API ref, integration guide)
```

---

## Phase 1 — Core Extraction
> Decouple every component from shellframe naming. No new features — pure rename/extract.
> These tasks are independent of each other and can be done in any order.

| # | Task | Effort | GH Issue | Status |
|---|------|--------|----------|--------|
| 1 | Extract `assert.sh`: rename `shellframe_test_begin` → `ptyunit_test_begin`, `shellframe_test_summary` → `ptyunit_test_summary`, globals `_SHELLFRAME_TEST_*` → `_PTYUNIT_TEST_*` | XS | [#1](https://github.com/fissible/ptyunit/issues/1) | open |
| 2 | Extract `run.sh`: rename header text, `SHELLFRAME_DIR` → `PTYUNIT_DIR`, update suite paths | XS | [#2](https://github.com/fissible/ptyunit/issues/2) | open |
| 3 | Extract `pty_run.py`: update module docstring and project references only; no logic changes | XS | [#3](https://github.com/fissible/ptyunit/issues/3) | open |
| 4 | Extract Docker matrix: rename image tags `shellframe-test-bash*` → `ptyunit-bash*`, `SHELLFRAME_DIR` → `PTYUNIT_DIR`, `WORKDIR /clui` → `WORKDIR /ptyunit` in all three Dockerfiles | S | [#4](https://github.com/fissible/ptyunit/issues/4) | open |

**Coupling inventory — what changes in Phase 1:**

| File | Coupling | Fix |
|------|----------|-----|
| `assert.sh` | `_SHELLFRAME_TEST_PASS/FAIL/NAME` globals; `shellframe_test_begin`; `shellframe_test_summary` | Rename to `_PTYUNIT_TEST_*`, `ptyunit_test_begin`, `ptyunit_test_summary` |
| `run.sh` | Header prints `shellframe test runner`; internal var `SHELLFRAME_DIR` | Rename both |
| `run-matrix.sh` | Image tags `shellframe-test-bash{3,4,5}`; var `SHELLFRAME_DIR` | Rename both |
| `Dockerfile.bash{3,4,5}` | `WORKDIR /clui` | Change to `WORKDIR /ptyunit` |
| `pty_run.py` | Docstring mentions shellframe | Update text only |

**What does NOT change in Phase 1:**
- `pty_run.py` logic — it is already fully generic (runs any bash script, knows nothing about shellframe)
- All assertion logic in `assert.sh`
- All runner logic in `run.sh`
- All Docker build logic

---

## Phase 2 — ptyunit Native Unit Tests
> Test assert.sh's own behavior. These are the framework's self-tests.
> Depends on: Phase 1 (renamed assert.sh)

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| 5 | Write `tests/unit/test-assert.sh`: test `assert_eq` pass/fail output, `assert_contains` pass/fail, `assert_output` captures stdout, `ptyunit_test_summary` exit codes, counter accumulation across sections | S | [#5](https://github.com/fissible/ptyunit/issues/5) | open | 1 |

---

## Phase 3 — Example Fixture Scripts
> Minimal bash scripts that serve as both demos and PTY integration test fixtures.
> These live in `examples/` and must work in bash 3.2+.
> Depends on: Phase 1 (renamed pty_run.py, run.sh)

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| 6 | Write `examples/confirm.sh`: yes/no prompt, prints `Confirmed` or `Cancelled` to stdout, renders to `/dev/tty` | XS | [#6](https://github.com/fissible/ptyunit/issues/6) | open | 1,2,3 |
| 7 | Write `examples/menu.sh`: arrow-key navigable list, prints selected item to stdout, renders to `/dev/tty` | S | [#7](https://github.com/fissible/ptyunit/issues/7) | open | 1,2,3 |

These examples must be self-contained (no shellframe dependency). They exist to
demonstrate what ptyunit can test and to give integration tests something to drive.

---

## Phase 4 — Integration Tests
> Drive examples with `pty_run.py`, assert on stdout using `assert_contains`.
> Depends on: Phase 2 (assert.sh), Phase 3 (example scripts)

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| 8 | Write `tests/integration/test-confirm.sh`: drive `examples/confirm.sh` with `y`, `n`, `ENTER`, `ESC`; assert on `Confirmed`/`Cancelled` | XS | [#8](https://github.com/fissible/ptyunit/issues/8) | open | 5,6 |
| 9 | Write `tests/integration/test-menu.sh`: drive `examples/menu.sh` with `ENTER`, `DOWN ENTER`, `q`; assert on selection output | S | [#9](https://github.com/fissible/ptyunit/issues/9) | open | 5,7 |

---

## Phase 5 — Documentation
> Depends on: Phase 4 (all components working end-to-end)

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| 10 | Write `README.md`: what ptyunit is, install/usage quick start, `assert.sh` API reference, `pty_run.py` CLI reference (args, env vars, named keys, exit codes), link to examples | M | [#10](https://github.com/fissible/ptyunit/issues/10) | open | 8,9 |
| 11 | Write `docs/integration-guide.md`: how to add ptyunit to an existing bash project (directory layout, sourcing assert.sh, writing unit vs integration tests, running the docker matrix) | S | [#11](https://github.com/fissible/ptyunit/issues/11) | open | 10 |

---

## Milestones

| Milestone | Condition | Status |
|-----------|-----------|--------|
| **M1: Standalone** | Phase 1 complete; all tests pass with ptyunit naming, no shellframe refs | open |
| **M2: Self-tested** | Phase 2+3+4 complete; ptyunit tests its own components | open |
| **M3: Public launch** | Phase 5 complete; README + guide published; Docker matrix green | open |

---

## File layout (target)

```
ptyunit/
├── assert.sh                        # assertion library
├── run.sh                           # test runner
├── pty_run.py                       # PTY driver
├── examples/
│   ├── confirm.sh                   # minimal yes/no prompt demo
│   └── menu.sh                      # minimal arrow-key menu demo
├── tests/
│   ├── unit/
│   │   └── test-assert.sh           # self-tests for assert.sh
│   └── integration/
│       ├── test-confirm.sh          # PTY-driven test of examples/confirm.sh
│       └── test-menu.sh             # PTY-driven test of examples/menu.sh
└── docker/
    ├── run-matrix.sh                # orchestrates bash 3.2/4.4/5.x matrix
    ├── Dockerfile.bash3             # bash 3.2 on Alpine 3.18
    ├── Dockerfile.bash4             # bash 4.4 on Alpine 3.18
    └── Dockerfile.bash5             # bash 5.2 (Alpine native)
```

---

## pty_run.py reference (preserve exactly — do not alter logic in Phase 1)

```
python3 pty_run.py <script> [KEY ...]
```

Named key tokens: `UP DOWN LEFT RIGHT ENTER SPACE ESC TAB SHIFT_TAB BACKSPACE DELETE HOME END PAGE_UP PAGE_DOWN`
Hex literals: `\xNN`
Literal characters: passed as-is

Environment variables:
| Variable    | Default | Description                        |
|-------------|---------|-------------------------------------|
| PTY_COLS    | 80      | Terminal width                     |
| PTY_ROWS    | 24      | Terminal height                    |
| PTY_DELAY   | 0.15    | Seconds between keystrokes         |
| PTY_INIT    | 0.30    | Seconds before first key           |
| PTY_TIMEOUT | 10      | Seconds to wait for child exit     |

Exit codes: script's own exit code, or `124` on timeout.

---

## Session handoff notes
> Update this section at the end of each session.

_Last updated: 2026-03-15_
- `fissible/ptyunit` repository created on GitHub (https://github.com/fissible/ptyunit)
- This PROJECT.md drafted; not yet committed to ptyunit repo
- Phase 1 extraction work not started — shellframe tests still use shellframe prefixes
- **Next session: create GitHub issues for tasks 1–11, then begin Phase 1 (tasks 1–4 are independent, do in any order)**
