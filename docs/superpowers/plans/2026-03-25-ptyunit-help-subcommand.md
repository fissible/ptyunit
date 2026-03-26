# ptyunit help subcommand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ptyunit help [topic]` so all features are discoverable from the CLI, with a topics registry that drives both the index and dispatch, and install-method-aware output for the coverage topic.

**Architecture:** A new `help.sh` in `PTYUNIT_DIR` holds the topics registry (`_TOPICS` flat name/description array), color setup, install detection, all 11 `_help_<topic>()` functions, and a `_dispatch()` that derives function names from topic names. `run.sh` intercepts `help` before arg parsing and delegates to `help.sh`. The `BASH_SOURCE` guard lets `test-help.sh` source `help.sh` and call functions directly.

**Tech Stack:** bash 3.2+, no external dependencies.

---

## File map

| File | Action |
|---|---|
| `help.sh` | Create — registry, color, detection, 11 topic functions, index, dispatch |
| `run.sh` | Modify — help intercept in `_main()`, one line in `_usage()` |
| `self-tests/unit/test-help.sh` | Create — sources help.sh, tests all functions |

---

### Task 1: help.sh skeleton + core infrastructure + tests

Covers: PTYUNIT_DIR preamble, `_help_color_setup`, `_TOPICS` registry, `_detect_install`, `_help_index`, `_dispatch`, BASH_SOURCE guard. Test file covers index, dispatch, and detection.

**Files:**
- Create: `self-tests/unit/test-help.sh`
- Create: `help.sh`

- [ ] **Step 1: Write the failing test file**

Create `self-tests/unit/test-help.sh`:

```bash
#!/usr/bin/env bash
# self-tests/unit/test-help.sh — Tests for help.sh infrastructure
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/help.sh"

# ── _help_index ───────────────────────────────────────────────────────────────

test_that "_help_index lists every topic name from _TOPICS"
_idx=$(_help_index)
for (( _i=0; _i<${#_TOPICS[@]}; _i+=2 )); do
    assert_contains "$_idx" "${_TOPICS[_i]}"
done

test_that "_help_index includes Where to start note"
assert_contains "$(_help_index)" "Where to start"

# ── _dispatch ─────────────────────────────────────────────────────────────────

test_that "_dispatch with no argument shows index (does not error)"
_out=$(_dispatch)
assert_eq "0" "$?"
assert_contains "$_out" "Where to start"

test_that "_dispatch with unknown topic exits 1"
( _dispatch "__no_such_topic__" ) 2>/dev/null
assert_eq "1" "$?"

test_that "_dispatch unknown topic message mentions ptyunit help"
_err=$( ( _dispatch "__bad__" ) 2>&1 )
assert_contains "$_err" "ptyunit help"

# ── _detect_install ───────────────────────────────────────────────────────────

test_that "_detect_install returns a recognised value"
_inst=$(_detect_install)
case "$_inst" in
    submodule|brew|bpkg) assert_eq "0" "0" ;;
    *) assert_eq "submodule|brew|bpkg" "$_inst" ;;
esac

ptyunit_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash self-tests/unit/test-help.sh
```

Expected: error — `help.sh: No such file or directory` (source fails).

- [ ] **Step 3: Create help.sh skeleton**

Create `help.sh`:

```bash
#!/usr/bin/env bash
# ptyunit/help.sh — Topic-specific help for ptyunit features
#
# Usage: bash path/to/ptyunit/help.sh [topic]
#        ptyunit help [topic]
#
# With no topic, lists all available topics.
set -u

PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ── Color setup ───────────────────────────────────────────────────────────────
_help_color_setup() {
    _BOLD="" _GREEN="" _RESET="" _DIM=""
    local _use_color=0
    if [[ -n "${FORCE_COLOR:-}" && -z "${NO_COLOR:-}" ]]; then
        _use_color=1
    elif [[ -z "${NO_COLOR:-}" ]] && [ -t 1 ]; then
        _use_color=1
    fi
    if (( _use_color )); then
        _BOLD=$'\033[1m'
        _GREEN=$'\033[0;32m'
        _RESET=$'\033[0m'
        _DIM=$'\033[2m'
    fi
}

# ── Topics registry ───────────────────────────────────────────────────────────
# Flat array of name/description pairs. Drives _help_index and _dispatch.
# To add a topic: append a pair here and write _help_<name>() below.
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

# ── Install detection ─────────────────────────────────────────────────────────
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

# ── Index ─────────────────────────────────────────────────────────────────────
_help_index() {
    printf 'ptyunit help topics\n\n'
    local i
    for (( i=0; i<${#_TOPICS[@]}; i+=2 )); do
        printf '  %-20s %s\n' "${_TOPICS[i]}" "${_TOPICS[i+1]}"
    done
    printf '\nWhere to start: source assert.sh in a test file, write test_that / assert_*\n'
    printf 'sections, call ptyunit_test_summary at the end, then run with '\''bash run.sh --unit'\''.\n'
    printf 'See '\''ptyunit help filters'\'' to run a single file while iterating.\n'
}

# ── Topic functions ───────────────────────────────────────────────────────────
# Placeholders — filled in by subsequent tasks.
# Each _help_<name>() prints to stdout and exits 0.

# ── Dispatch ──────────────────────────────────────────────────────────────────
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

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _dispatch "${1:-}"
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash self-tests/unit/test-help.sh
```

Expected: `OK (7/7) in ...`

- [ ] **Step 5: Commit**

```bash
git add help.sh self-tests/unit/test-help.sh
git commit -m "feat(help): add help.sh skeleton with registry, index, dispatch, and detect"
```

---

### Task 2: _help_coverage

The most complex topic — shows all three install variants with color annotation on the detected one.

**Files:**
- Modify: `help.sh` (add `_help_coverage` function)
- Modify: `self-tests/unit/test-help.sh` (add coverage topic tests)

- [ ] **Step 1: Add failing tests**

Append to `self-tests/unit/test-help.sh` before `ptyunit_test_summary`:

```bash
# ── _help_coverage ────────────────────────────────────────────────────────────

test_that "_help_coverage exits 0"
_help_coverage >/dev/null
assert_eq "0" "$?"

test_that "_help_coverage output contains all three install variants"
_cov=$(_help_coverage)
assert_contains "$_cov" "tests/ptyunit/coverage.sh"
assert_contains "$_cov" "deps/bpkg/ptyunit/coverage.sh"
assert_contains "$_cov" "brew --prefix ptyunit"

test_that "_help_coverage output contains flags table"
_cov=$(_help_coverage)
assert_contains "$_cov" "--src="
assert_contains "$_cov" "--report="
assert_contains "$_cov" "--min="

test_that "_help_coverage output mentions .coverageignore"
assert_contains "$(_help_coverage)" ".coverageignore"

test_that "_help_coverage output mentions @pty_skip"
assert_contains "$(_help_coverage)" "@pty_skip"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: failures — `_help_coverage: command not found`.

- [ ] **Step 3: Implement _help_coverage**

Add to `help.sh` in the `# ── Topic functions ──` section:

```bash
_help_coverage() {
    _help_color_setup
    local _install
    _install=$(_detect_install)

    printf 'Code coverage — measure which lines of your source ran during tests.\n\n'

    if [[ "$_install" == "submodule" ]]; then
        printf '%s# git submodule  <- detected%s\n' "${_BOLD}${_GREEN}" "${_RESET}"
    else
        printf '# git submodule\n'
    fi
    printf 'bash tests/ptyunit/coverage.sh --unit --src=src\n\n'

    if [[ "$_install" == "bpkg" ]]; then
        printf '%s# bpkg  <- detected%s\n' "${_BOLD}${_GREEN}" "${_RESET}"
    else
        printf '# bpkg\n'
    fi
    printf 'bash deps/bpkg/ptyunit/coverage.sh --unit --src=src\n\n'

    if [[ "$_install" == "brew" ]]; then
        printf '%s# Homebrew  <- detected%s\n' "${_BOLD}${_GREEN}" "${_RESET}"
    else
        printf '# Homebrew\n'
    fi
    printf 'bash "$(brew --prefix ptyunit)/libexec/coverage.sh" --unit --src=src\n\n'

    printf 'Flags:\n'
    printf '  --unit / --all       Which suites to run (default: --all)\n'
    printf '  --src=<dir>          Directory to measure  (default: src/ or .)\n'
    printf '  --report=text|json|html\n'
    printf '  --min=N              Exit 1 if coverage < N%%  (CI gate)\n\n'
    printf 'Exclude files:  add glob patterns to .coverageignore at project root\n'
    printf 'Exclude lines:  annotate with  # @pty_skip\n'
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: all tests passing.

- [ ] **Step 5: Commit**

```bash
git add help.sh self-tests/unit/test-help.sh
git commit -m "feat(help): add coverage topic with install detection and color annotation"
```

---

### Task 3: Topics batch 1 — pty, mocking, params, describe

**Files:**
- Modify: `help.sh`
- Modify: `self-tests/unit/test-help.sh`

- [ ] **Step 1: Add failing tests**

Append to `self-tests/unit/test-help.sh` before `ptyunit_test_summary`:

```bash
# ── pty, mocking, params, describe ───────────────────────────────────────────

test_that "_help_pty exits 0 and mentions pty_run.py and pty_session.py"
_out=$(_help_pty)
assert_eq "0" "$?"
assert_contains "$_out" "pty_run.py"
assert_contains "$_out" "pty_session.py"

test_that "_help_mocking exits 0 and mentions ptyunit_mock and assert_called"
_out=$(_help_mocking)
assert_eq "0" "$?"
assert_contains "$_out" "ptyunit_mock"
assert_contains "$_out" "assert_called"

test_that "_help_params exits 0 and mentions test_each"
_out=$(_help_params)
assert_eq "0" "$?"
assert_contains "$_out" "test_each"

test_that "_help_describe exits 0 and mentions end_describe"
_out=$(_help_describe)
assert_eq "0" "$?"
assert_contains "$_out" "end_describe"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: failures for all four new tests.

- [ ] **Step 3: Implement the four topic functions**

Add to `help.sh` in the topic functions section:

```bash
_help_pty() {
    printf 'PTY testing — drive interactive terminal programs with keystrokes.\n\n'
    printf 'pty_run.py  — one-shot: run a command, send keys, get output\n\n'
    printf '  out=$(python3 tests/ptyunit/pty_run.py my_menu.sh DOWN DOWN ENTER)\n'
    printf '  assert_contains "$out" "You selected: cherry"\n\n'
    printf 'pty_session.py  — stateful: open a session, interact step by step\n\n'
    printf '  session = PTYSession("my_menu.sh")\n'
    printf '  session.send("DOWN")\n'
    printf '  session.send("ENTER")\n'
    printf '  assert "cherry" in session.screen_text()\n'
    printf '  session.close()\n\n'
    printf 'Keys: UP, DOWN, LEFT, RIGHT, ENTER, ESC, BACKSPACE, TAB, or any char.\n'
    printf 'Output has ANSI escape codes stripped automatically.\n'
    printf 'Requires Python 3 and a PTY-capable OS (Linux, macOS).\n'
}

_help_mocking() {
    printf 'Mocking — replace commands or functions for the duration of a test.\n\n'
    printf 'Inline mock (fixed output and exit code):\n\n'
    printf '  ptyunit_mock git --output "pushed" --exit 0\n'
    printf '  deploy_to_staging\n'
    printf '  assert_called git\n'
    printf '  assert_called_with git "push" "origin" "staging"\n\n'
    printf 'Heredoc mock (custom logic):\n\n'
    printf "  ptyunit_mock git << 'MOCK'\n"
    printf '  case "$1" in\n'
    printf '      push)   echo "error: rejected"; exit 1 ;;\n'
    printf '      status) echo "On branch main" ;;\n'
    printf '  esac\n'
    printf '  MOCK\n\n'
    printf 'Assertions:\n'
    printf '  assert_called <cmd>                  was it called at all?\n'
    printf '  assert_called_with <cmd> [args...]   was it called with these args?\n'
    printf '  assert_called_times <cmd> <N>        was it called exactly N times?\n\n'
    printf 'Mocks are cleaned up automatically at the next test_that boundary.\n'
}

_help_params() {
    printf 'Parameterised tests — run one callback with multiple input rows.\n\n'
    printf '  _verify_add() {\n'
    printf '      assert_eq "$3" "$(( $1 + $2 ))"\n'
    printf '  }\n\n'
    printf "  test_each _verify_add << 'PARAMS'\n"
    printf '  1|2|3\n'
    printf '  10|20|30\n'
    printf '  -1|1|0\n'
    printf '  # this line is a comment and is skipped\n'
    printf '  PARAMS\n\n'
    printf 'Fields are split on | and passed as $1 $2 $3 ... to the callback.\n'
    printf 'Each row is an independent test section. A failing row does not stop\n'
    printf 'the others. Lines starting with # are skipped.\n'
}

_help_describe() {
    printf 'Describe blocks — group related tests under a label.\n\n'
    printf '  describe "string utils"\n'
    printf '      describe "upper"\n'
    printf '          test_that "converts lowercase"\n'
    printf '          assert_output "HELLO" str_upper "hello"\n'
    printf '      end_describe\n'
    printf '  end_describe\n\n'
    printf 'describe blocks are purely organisational — they prefix the label in\n'
    printf 'output and in --name filtering. They do not affect test isolation.\n'
    printf 'Nesting is supported; close each block with end_describe.\n'
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: all tests passing.

- [ ] **Step 5: Commit**

```bash
git add help.sh self-tests/unit/test-help.sh
git commit -m "feat(help): add pty, mocking, params, describe topics"
```

---

### Task 4: Topics batch 2 — setup-teardown, filters, formats, install

**Files:**
- Modify: `help.sh`
- Modify: `self-tests/unit/test-help.sh`

- [ ] **Step 1: Add failing tests**

Append to `self-tests/unit/test-help.sh` before `ptyunit_test_summary`:

```bash
# ── setup-teardown, filters, formats, install ─────────────────────────────────

test_that "_help_setup_teardown exits 0 and mentions PTYUNIT_TEST_TMPDIR"
_out=$(_help_setup_teardown)
assert_eq "0" "$?"
assert_contains "$_out" "PTYUNIT_TEST_TMPDIR"

test_that "_help_filters exits 0 and mentions --filter and --name"
_out=$(_help_filters)
assert_eq "0" "$?"
assert_contains "$_out" "--filter"
assert_contains "$_out" "--name"

test_that "_help_formats exits 0 and mentions all three formats"
_out=$(_help_formats)
assert_eq "0" "$?"
assert_contains "$_out" "pretty"
assert_contains "$_out" "tap"
assert_contains "$_out" "junit"

test_that "_help_install exits 0 and mentions submodule brew bpkg and Makefile"
_out=$(_help_install)
assert_eq "0" "$?"
assert_contains "$_out" "submodule"
assert_contains "$_out" "brew"
assert_contains "$_out" "bpkg"
assert_contains "$_out" "Makefile"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: failures for all four new tests.

- [ ] **Step 3: Implement the four topic functions**

Add to `help.sh`:

```bash
_help_setup_teardown() {
    printf 'setUp / tearDown — per-test file hooks.\n\n'
    printf 'Place setUp.sh and/or tearDown.sh alongside your test-*.sh files\n'
    printf 'in the same suite directory (tests/unit/ or tests/integration/).\n\n'
    printf '  setUp.sh    runs before each test file\n'
    printf '  tearDown.sh runs after each test file (even if the test failed)\n\n'
    printf 'Both receive PTYUNIT_TEST_TMPDIR — a per-test temporary directory\n'
    printf 'created by the runner and cleaned up after tearDown.\n\n'
    printf 'If setUp.sh exits non-zero, the test file is skipped and counts\n'
    printf 'as a failure. tearDown.sh still runs.\n\n'
    printf 'Example setUp.sh:\n\n'
    printf '  #!/usr/bin/env bash\n'
    printf '  cp fixtures/config.json "$PTYUNIT_TEST_TMPDIR/"\n'
}

_help_filters() {
    printf 'Filters — run a subset of tests.\n\n'
    printf 'By file name:\n\n'
    printf '  bash run.sh --unit --filter auth\n'
    printf '  # runs only files whose name contains "auth"\n'
    printf '  # e.g. test-auth.sh, test-auth-tokens.sh\n\n'
    printf 'By test section name:\n\n'
    printf '  bash run.sh --unit --name "handles empty"\n'
    printf '  # runs only test_that sections whose label contains "handles empty"\n\n'
    printf 'Combining both:\n\n'
    printf '  bash run.sh --unit --filter auth --name "login"\n\n'
    printf 'Patterns are substring matches (not regex, not glob).\n'
    printf 'With --format tap or --format junit, filtered output is still valid.\n'
}

_help_formats() {
    printf 'Output formats.\n\n'
    printf '  --format pretty    Human-readable (default)\n'
    printf '                     Colored OK / FAIL / SKIP per file, summary at end.\n\n'
    printf '  --format tap       TAP version 13\n'
    printf '                     For TAP consumers (prove, tap-junit, etc.).\n\n'
    printf '  --format junit     JUnit XML\n'
    printf '                     For CI reporters (GitHub Actions, Jenkins, etc.).\n\n'
    printf '  -v / --verbose     Add per-file elapsed time to pretty output.\n'
    printf '                     Also shows tests/second for files taking > 0s.\n\n'
    printf 'Color:\n'
    printf '  NO_COLOR=1         Suppress color in pretty output.\n'
    printf '  FORCE_COLOR=1      Force color even when stdout is not a TTY (CI).\n'
}

_help_install() {
    printf 'Installing ptyunit.\n\n'
    printf '  # git submodule (recommended when you own both sides)\n'
    printf '  git submodule add https://github.com/fissible/ptyunit tests/ptyunit\n\n'
    printf '  # Homebrew\n'
    printf '  brew tap fissible/tap && brew install ptyunit\n\n'
    printf '  # bpkg\n'
    printf '  bpkg install fissible/ptyunit\n\n'
    printf 'Rule of thumb:\n'
    printf '  Submodule  — own both sides; want version pinning per-repo.\n'
    printf '               Update: git submodule update --remote && git commit\n'
    printf '  Homebrew   — distributing to others; one global version shared by all\n'
    printf '               projects on the machine.  brew upgrade ptyunit to update.\n'
    printf '  bpkg       — like npm for bash; local copy in deps/; version-locked.\n\n'
    printf 'Makefile tip — add a test target so no one needs to know the path:\n\n'
    printf '  test:\n'
    printf '\tbash tests/ptyunit/run.sh --unit\n\n'
    printf 'Check your installed version:  ptyunit --version   or   which ptyunit\n'
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: all tests passing.

- [ ] **Step 5: Commit**

```bash
git add help.sh self-tests/unit/test-help.sh
git commit -m "feat(help): add setup-teardown, filters, formats, install topics"
```

---

### Task 5: Topics batch 3 — skip, matrix, registry sync test

**Files:**
- Modify: `help.sh`
- Modify: `self-tests/unit/test-help.sh`

- [ ] **Step 1: Add failing tests**

Append to `self-tests/unit/test-help.sh` before `ptyunit_test_summary`:

```bash
# ── skip, matrix ──────────────────────────────────────────────────────────────

test_that "_help_skip exits 0 and mentions ptyunit_skip and ptyunit_require_bash"
_out=$(_help_skip)
assert_eq "0" "$?"
assert_contains "$_out" "ptyunit_skip"
assert_contains "$_out" "ptyunit_require_bash"

test_that "_help_matrix exits 0 and mentions docker/run-matrix.sh"
_out=$(_help_matrix)
assert_eq "0" "$?"
assert_contains "$_out" "run-matrix.sh"

# ── Registry / function sync ──────────────────────────────────────────────────

test_that "every _TOPICS entry has a corresponding _help_ function"
for (( _i=0; _i<${#_TOPICS[@]}; _i+=2 )); do
    _hn="${_TOPICS[_i]}"
    _fn="_help_${_hn//-/_}"
    assert_true declare -f "$_fn"
done
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: failures for skip, matrix, and the registry sync test.

- [ ] **Step 3: Implement the two topic functions**

Add to `help.sh`:

```bash
_help_skip() {
    printf 'Skipping tests.\n\n'
    printf 'Skip an entire file (place at the top of the test file):\n\n'
    printf '  ptyunit_skip "reason string"\n'
    printf '  # exits the file with rc=3; counted as SKIP, not failure\n\n'
    printf 'Require a minimum bash version:\n\n'
    printf '  ptyunit_require_bash 4\n'
    printf '  # skips automatically on bash 3.x\n\n'
    printf 'Skip a single test section:\n\n'
    printf '  test_that "something"\n'
    printf '  ptyunit_skip_test "not implemented yet"\n\n'
    printf 'Skipped files appear as SKIP in output and are listed separately\n'
    printf 'under "Skipped:" in the summary. They do not count as failures.\n'
}

_help_matrix() {
    printf 'Bash version matrix — run tests across bash 3.2, 4.x, and 5.x.\n\n'
    printf '  bash docker/run-matrix.sh\n\n'
    printf 'Requires Docker. Runs the full test suite in containers for each\n'
    printf 'supported bash version.\n\n'
    printf 'When to use: before a release, or when writing code that must be\n'
    printf 'compatible across bash versions.\n\n'
    printf 'Common bash 3.2 incompatibilities to watch for:\n'
    printf '  declare -A    associative arrays      (bash 4+)\n'
    printf '  readarray     array from stdin        (bash 4+)\n'
    printf '  EPOCHREALTIME high-resolution timer   (bash 5+)\n'
    printf '  BASH_XTRACEFD redirect xtrace fd      (bash 4.1+)\n\n'
    printf 'bash 3.2 ships on macOS by default. Run the matrix before every\n'
    printf 'release if your project targets 3.2.\n'
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: all tests passing (including registry sync test).

- [ ] **Step 5: Run the full test suite to confirm no regressions**

```bash
bash run.sh --unit 2>&1 | tail -10
```

Expected: all files passing, no failures.

- [ ] **Step 6: Commit**

```bash
git add help.sh self-tests/unit/test-help.sh
git commit -m "feat(help): add skip and matrix topics; add registry/function sync test"
```

---

### Task 6: run.sh wiring

Wire `help` into `run.sh` as a first-class subcommand: intercept in `_main()` and add a line to `_usage()`.

**Files:**
- Modify: `run.sh`
- Modify: `self-tests/unit/test-help.sh`

- [ ] **Step 1: Add failing integration tests**

Append to `self-tests/unit/test-help.sh` before `ptyunit_test_summary`:

```bash
# ── run.sh integration ────────────────────────────────────────────────────────

test_that "run.sh help with no topic exits 0 and shows index"
_out=$( bash "$PTYUNIT_DIR/run.sh" help )
assert_eq "0" "$?"
assert_contains "$_out" "ptyunit help topics"

test_that "run.sh help coverage exits 0"
bash "$PTYUNIT_DIR/run.sh" help coverage >/dev/null
assert_eq "0" "$?"

test_that "run.sh help unknown topic exits 1"
( bash "$PTYUNIT_DIR/run.sh" help __no_such_topic__ ) 2>/dev/null
assert_eq "1" "$?"

test_that "run.sh --help output mentions help subcommand"
_out=$( bash "$PTYUNIT_DIR/run.sh" --help )
assert_contains "$_out" "help"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash self-tests/unit/test-help.sh 2>&1 | grep -E "FAIL|fail"
```

Expected: the four new integration tests fail (help subcommand not yet in run.sh).

- [ ] **Step 3: Add help intercept to run.sh**

In `run.sh`, in `_main()`, add the intercept immediately after the `PTYUNIT_VERSION=` line and before the `while [[ $# -gt 0 ]]; do` loop. The current text at that location is:

```bash
    PTYUNIT_VERSION=$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/VERSION" 2>/dev/null || printf '1.0.0')

    # ── Arg parsing ───────────────────────────────────────────────────────────
    while [[ $# -gt 0 ]]; do
```

Replace with:

```bash
    PTYUNIT_VERSION=$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/VERSION" 2>/dev/null || printf '1.0.0')

    # ── Help subcommand ────────────────────────────────────────────────────────
    if [[ "${1:-}" == "help" ]]; then
        bash "$PTYUNIT_DIR/help.sh" "${@:2}"; exit $?
    fi

    # ── Arg parsing ───────────────────────────────────────────────────────────
    while [[ $# -gt 0 ]]; do
```

- [ ] **Step 4: Add help line to _usage() in run.sh**

In `_usage()`, the current last two lines before `USAGE` are:

```
  -h, --help          Show this help
  --version           Show version
USAGE
```

Replace with:

```
  -h, --help          Show this help
  --version           Show version
  help [TOPIC]        Topic help  (run 'ptyunit help' to list topics)
USAGE
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bash self-tests/unit/test-help.sh 2>&1 | tail -5
```

Expected: all tests passing.

- [ ] **Step 6: Run the full test suite**

```bash
bash run.sh --unit 2>&1 | tail -10
```

Expected: all files passing, no failures.

- [ ] **Step 7: Smoke test interactively**

```bash
bash run.sh help
bash run.sh help coverage
bash run.sh help install
bash run.sh help __bad__
echo "exit: $?"
```

Expected: index, coverage page with install detection, install page, error message + exit 1.

- [ ] **Step 8: Commit**

```bash
git add run.sh self-tests/unit/test-help.sh
git commit -m "feat(help): wire help subcommand into run.sh _main and _usage"
```

---

## Self-review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `help.sh` new file with PTYUNIT_DIR preamble | Task 1 |
| BASH_SOURCE guard | Task 1 |
| `_TOPICS` registry (11 topics) | Task 1 |
| `_help_color_setup` (FORCE_COLOR/NO_COLOR/tty) | Task 1 |
| `_detect_install` (brew/bpkg/submodule) | Task 1 |
| `_help_index` auto-generated from registry | Task 1 |
| `_dispatch` empty → index, unknown → exit 1 | Task 1 |
| `_help_coverage` with all 3 install variants + color annotation | Task 2 |
| `_help_pty`, `_help_mocking`, `_help_params`, `_help_describe` | Task 3 |
| `_help_setup_teardown`, `_help_filters`, `_help_formats`, `_help_install` | Task 4 |
| `_help_skip`, `_help_matrix` | Task 5 |
| Registry/function sync test | Task 5 |
| `run.sh` help intercept in `_main()` | Task 6 |
| `run.sh` `_usage()` footer line | Task 6 |
| `test-help.sh` tests all spec items | Tasks 1–6 |

**Placeholder scan:** No TBDs, all code blocks complete.

**Type consistency:** `_dispatch` derives function name via `${topic//-/_}` — used consistently. `_TOPICS` array walked with `i+=2` — consistent in `_help_index` and registry sync test. `_detect_install` returns `submodule|brew|bpkg` — consistent with coverage topic conditionals.
