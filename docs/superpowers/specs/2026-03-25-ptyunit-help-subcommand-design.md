# ptyunit help subcommand — Design Spec

**Date:** 2026-03-25
**Status:** Approved

---

## Problem

ptyunit has features (coverage, PTY testing, mocking, parameterised tests, describe
blocks, Docker matrix, etc.) that are not discoverable from `ptyunit --help`. Users
who install via brew or bpkg have no obvious path to learn about `coverage.sh`,
`pty_run.py`, or setUp/tearDown hooks. The `--help` output documents CLI flags but
nothing else.

---

## Goal

`ptyunit help [topic]` makes every major feature discoverable. Running `ptyunit help`
with no topic shows an auto-generated index of all topics plus a "where to start"
note. Running `ptyunit help coverage` (for example) shows a focused reference page
for that feature, including install-method-aware invocation examples.

---

## Non-goals

- Not a full tutorial or man page for each feature
- Not interactive (no pager, no fuzzy search)
- Not a replacement for the README — topics are short references, not prose guides

---

## Files changed

| File | Change |
|---|---|
| `help.sh` | **New.** Lives alongside `run.sh` in `PTYUNIT_DIR`. Contains the registry, all topic functions, index generator, and dispatch logic. |
| `run.sh` | **Modified.** `_main()` intercepts `help` before arg parsing and delegates to `help.sh`. `_usage()` gains one footer line mentioning `help [TOPIC]`. |
| `self-tests/unit/test-help.sh` | **New.** Unit tests for `help.sh` internals. |

The Homebrew formula installs a `ptyunit` binary that forwards `$@` to `run.sh`. No
formula change is needed — `ptyunit help coverage` already works via that forwarding.

---

## Architecture

### `help.sh` preamble

`help.sh` sets its own `PTYUNIT_DIR` via `BASH_SOURCE[0]` (same pattern as
`run.sh`) so it works regardless of CWD:

```bash
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
```

The dispatch at the bottom is guarded so sourcing the file for tests does not
auto-execute:

```bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _dispatch "${1:-}"
```

### Entry point (`run.sh`)

At the top of `_main()`, before the arg-parsing `while` loop:

```bash
if [[ "${1:-}" == "help" ]]; then
    bash "$PTYUNIT_DIR/help.sh" "${@:2}"; exit $?
fi
```

`_usage()` gains one new line in the options footer:

```
  help [TOPIC]        Topic help  (run 'ptyunit help' to list topics)
```

### Topics registry (`help.sh`)

A flat array of name/description pairs drives the index and validates dispatch:

```bash
_TOPICS=(
    "coverage"       "Run a code coverage report"
    "pty"            "Test interactive PTY/TUI programs"
    "mocking"        "Mock commands and functions"
    "params"         "Run one test with multiple inputs"
    "describe"       "Group tests with describe blocks"
    "setup-teardown" "Per-test setUp.sh / tearDown.sh hooks"
    "filters"        "Run a subset of tests by file or name"
    "formats"        "TAP, JUnit XML, and pretty output"
    "install"        "How ptyunit is installed (submodule, brew, bpkg)"
    "skip"           "Skip a file or test at runtime"
    "matrix"         "Run tests across bash versions via Docker"
)
```

Adding a topic = add one pair here + write one `_help_<name>()` function. Nothing
else changes.

### Index (`ptyunit help` with no topic)

`_help_index()` walks `_TOPICS` in pairs and prints a formatted table, then appends
a short "where to start" paragraph:

```
ptyunit help topics

  coverage         Run a code coverage report
  pty              Test interactive PTY/TUI programs
  mocking          Mock commands and functions
  params           Run one test with multiple inputs
  describe         Group tests with describe blocks
  setup-teardown   Per-test setUp.sh / tearDown.sh hooks
  filters          Run a subset of tests by file or name
  formats          TAP, JUnit XML, and pretty output
  install          How ptyunit is installed (submodule, brew, bpkg)
  skip             Skip a file or test at runtime
  matrix           Run tests across bash versions via Docker

Where to start: source assert.sh in a test file, write test_that / assert_*
sections, call ptyunit_test_summary at the end, then run with 'bash run.sh --unit'.
See 'ptyunit help filters' to run a single file while iterating.
```

### Dispatch

Topic name → function name via `${topic//-/_}` (hyphens become underscores).
Empty topic (bare `ptyunit help`) calls `_help_index` directly — it must not fall
through to the error path:

```bash
_dispatch() {
    local topic="${1:-}"
    [[ -z "$topic" ]] && { _help_index; return; }
    local fn="_help_${topic//-/_}"
    if declare -f "$fn" >/dev/null 2>&1; then
        "$fn"
    else
        printf 'ptyunit: unknown help topic "%s"\n' "$topic" >&2
        printf 'Run "ptyunit help" to see available topics.\n' >&2
        exit 1
    fi
}
```

The dispatch never needs updating — adding a function `_help_new_topic()` and a row
in `_TOPICS` is the complete workflow.

### Color setup

`_help_color_setup()` runs once at the top of `help.sh` using the same
`FORCE_COLOR` / `NO_COLOR` / tty logic as `run.sh`. It sets variables:
`_BOLD`, `_GREEN`, `_RESET`, `_DIM` — all empty strings when color is off.
This keeps CI output clean while being useful in interactive terminals.

### Install detection (`_detect_install`)

Inspects `$PTYUNIT_DIR` to infer the install method:

```bash
_detect_install() {
    if [[ "$PTYUNIT_DIR" == */Cellar/* || "$PTYUNIT_DIR" == */opt/homebrew/* \
       || "$PTYUNIT_DIR" == */homebrew/* ]]; then
        printf 'brew'
    elif [[ "$PTYUNIT_DIR" == */deps/* ]]; then
        # Heuristic: assumes deps/ means bpkg. A git submodule placed under
        # deps/ would also match. Impact is cosmetic only (annotation in
        # coverage output).
        printf 'bpkg'
    else
        printf 'submodule'
    fi
}
```

Returns one of: `brew`, `bpkg`, `submodule`.

---

## Topic content

Each topic is a `_help_<name>()` function that prints to stdout. Content is a short
focused reference — not a tutorial. Target length: 20–50 lines of output.

### `coverage`

Shows all three install variants. The detected variant gets a bold green
`← detected` annotation; the others render plain. Includes a flags table and
mentions `.coverageignore` and `# @pty_skip`.

Example output (submodule detected):

```
Code coverage — measure which lines of your source ran during tests.

# git submodule  ← detected
bash tests/ptyunit/coverage.sh --unit --src=src

# bpkg
bash deps/bpkg/ptyunit/coverage.sh --unit --src=src

# Homebrew
bash "$(brew --prefix ptyunit)/libexec/coverage.sh" --unit --src=src

Flags:
  --unit / --all       Which suites to run (default: --all)
  --src=<dir>          Directory to measure  (default: src/ or .)
  --report=text|json|html
  --min=N              Exit 1 if coverage < N%  (CI gate)

Exclude files:  add glob patterns to .coverageignore at project root
Exclude lines:  annotate with  # @pty_skip
```

### `pty`

Two-part: `pty_run.py` for one-shot PTY commands; `pty_session.py` for stateful
multi-step interaction. One usage example each.

### `mocking`

`ptyunit_mock` inline and heredoc forms, `assert_called`, `assert_called_with`,
`assert_called_times`. Note that mocks are cleaned up automatically at the next
`test_that` boundary.

### `params`

`test_each` heredoc syntax with `|` delimiter, comment lines (`#`), and how the
fields map to `$1`, `$2`, `$3` in the callback.

### `describe`

`describe "label"` / `end_describe` nesting, how labels appear in output, that
`test_that` sections inside a describe inherit the label prefix.

### `setup-teardown`

`setUp.sh` and `tearDown.sh` placed alongside test files. `PTYUNIT_TEST_TMPDIR`
per-test temp dir. Behaviour when setUp exits non-zero (file counts as failure,
tearDown still runs).

### `filters`

`--filter PATTERN` matches against file names; `--name PATTERN` matches against
`test_that` section names. Both can be combined. Examples showing partial matches.

### `formats`

`--format pretty` (default, human), `tap` (TAP version 13, for TAP consumers),
`junit` (JUnit XML, for CI reporters). `--verbose` adds per-file timing. When to use
each.

### `install`

**Rule of thumb:**
- Submodule: own both sides, want version pinning, explicit per-repo upgrades
- Brew: distributing to others, convenience over pinning, one global version
- bpkg: like npm for bash, lock-file reproducibility with `deps/` local copy

**Makefile recommendation:** whatever the install method, add `make test` to the
project so developers don't need to know the path:

```makefile
test:
    bash tests/ptyunit/run.sh --unit
```

Notes the `which ptyunit` / `ptyunit --version` drift risk with brew.

### `skip`

`ptyunit_skip "reason"` exits the file with rc=3 (skip). `ptyunit_require_bash 4`
is a convenience wrapper. Both appear in the summary as SKIP. Neither counts as a
failure.

### `matrix`

`bash docker/run-matrix.sh` runs the full test suite against bash 3.2, 4.x, 5.x
in Docker containers. Requires Docker. When to use: before a release, or when
writing code that must be compatible across bash versions.

---

## Testing (`test-help.sh`)

`self-tests/unit/test-help.sh` sources `help.sh` directly (same pattern as
`test-run-internals.sh`) and covers:

- `_help_index` output contains every topic name in `_TOPICS`
- `_help_index` output contains the "Where to start" note
- `_dispatch` with no argument calls `_help_index` (does not error)
- Unknown topic exits 1 and prints a useful message
- `_detect_install` returns one of `submodule`, `brew`, or `bpkg`
- Each `_help_<topic>` function exits 0
- Registry/function sync: iterate `_TOPICS` in pairs and assert `declare -f "_help_${name//-/_}"` for each entry — one test that catches any topic listed in the registry without a corresponding function

---

## Compatibility

`help.sh` must work on bash 3.2+ (same constraint as all ptyunit files).
`declare -f` for function existence checking is available in bash 3.2. No
associative arrays. No `[[ =~ ]]` capture groups needed.
