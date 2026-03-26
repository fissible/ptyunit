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
    printf 'output and in --name filtering. Outer labels are prepended to inner\n'
    printf 'test names, so a test inside nested describes appears as\n'
    printf '"string utils > upper > converts lowercase" in output.\n'
    printf 'Nesting is supported; close each block with end_describe.\n'
}

_help_setup_teardown() {
    printf 'setUp / tearDown hooks — run code before and after every test section.\n\n'
    printf 'Place hook files alongside your test files:\n\n'
    printf '  tests/\n'
    printf '    setUp.sh      # runs before each test_that block\n'
    printf '    tearDown.sh   # runs after each test_that block (even on failure)\n'
    printf '    test-foo.sh\n\n'
    printf 'Per-test temp directory:\n\n'
    printf '  PTYUNIT_TEST_TMPDIR is set to a fresh directory before each test section\n'
    printf '  and removed automatically after tearDown.sh completes.\n\n'
    printf '  setUp.sh example:\n'
    printf '    mkdir -p "$PTYUNIT_TEST_TMPDIR/fixtures"\n'
    printf '    cp tests/fixtures/* "$PTYUNIT_TEST_TMPDIR/fixtures/"\n\n'
    printf '  tearDown.sh example:\n'
    printf '    rm -rf "$PTYUNIT_TEST_TMPDIR"\n\n'
    printf 'Failure behaviour:\n\n'
    printf '  If setUp.sh exits non-zero, the test file is counted as a failure\n'
    printf '  and tearDown.sh still runs — so cleanup always happens.\n\n'
    printf '  If tearDown.sh exits non-zero, it is logged but does not override a\n'
    printf '  passing test result.\n\n'
    printf 'Passing state between hooks:\n\n'
    printf '  setUp.sh and tearDown.sh run as subprocesses (bash), not sourced.\n'
    printf '  They do not share the shell environment with the test file.\n'
    printf '  Use exported variables or files in PTYUNIT_TEST_TMPDIR to pass state.\n'
}

_help_filters() {
    printf 'Filters — run a subset of tests without editing files.\n\n'
    printf 'Filter by file name:\n\n'
    printf '  bash run.sh --unit --filter auth\n'
    printf '    # runs any test file whose path contains "auth"\n'
    printf '    # e.g. tests/unit/test-auth.sh, tests/unit/test-oauth.sh\n\n'
    printf 'Filter by test section name:\n\n'
    printf '  bash run.sh --unit --name "rejects bad input"\n'
    printf '    # runs only test_that sections whose label contains "rejects bad input"\n\n'
    printf 'Combine both:\n\n'
    printf '  bash run.sh --unit --filter auth --name "rejects"\n'
    printf '    # files matching "auth" AND sections matching "rejects"\n\n'
    printf 'Partial matches are fine — patterns are substrings, not regex:\n\n'
    printf '  --filter tok    matches test-token.sh, test-tokenizer.sh, ...\n'
    printf '  --name  "exits" matches "exits 0", "exits with code 1", ...\n\n'
    printf 'Describe-block labels are included in the section name for --name matching.\n'
    printf 'A section inside describe "auth" test_that "rejects bad input" is matched\n'
    printf 'as "auth > rejects bad input".\n'
}

_help_formats() {
    printf 'Output formats — choose how test results are reported.\n\n'
    printf 'Pretty (default, human-readable):\n\n'
    printf '  bash run.sh --unit\n'
    printf '  bash run.sh --unit --format pretty\n\n'
    printf '  Coloured pass/fail lines, summary counts, and elapsed time.\n'
    printf '  Best for local development.\n\n'
    printf 'TAP (Test Anything Protocol, version 13):\n\n'
    printf '  bash run.sh --unit --format tap\n\n'
    printf '  Produces structured TAP output readable by prove, tap-reporter,\n'
    printf '  and most CI systems that accept TAP streams.\n'
    printf '  Use this when piping results to a TAP consumer.\n\n'
    printf 'JUnit XML:\n\n'
    printf '  bash run.sh --unit --format junit\n\n'
    printf '  Produces JUnit-compatible XML. Consumed by GitHub Actions, Jenkins,\n'
    printf '  GitLab CI, and most CI reporters that parse test results.\n'
    printf '  Redirect to a file: bash run.sh --unit --format junit > results.xml\n\n'
    printf 'Verbose timing:\n\n'
    printf '  bash run.sh --unit --verbose\n\n'
    printf '  Adds per-file elapsed time to pretty and TAP output.\n'
    printf '  Useful for spotting unexpectedly slow test files.\n\n'
    printf 'When to use each:\n\n'
    printf '  pretty   Local iteration — fast feedback while writing code\n'
    printf '  tap      Feeding results to a TAP-aware tool or aggregator\n'
    printf '  junit    CI pipelines that publish test reports (GitHub, Jenkins)\n'
}

_help_install() {
    printf 'Installation methods — submodule, Homebrew, or bpkg.\n\n'
    printf 'git submodule (recommended when you own both sides):\n\n'
    printf '  git submodule add https://github.com/fissible/ptyunit tests/ptyunit\n\n'
    printf '  Best when: you control the consumer repo, want version pinning, and\n'
    printf '  prefer explicit per-repo upgrades (git submodule update --remote).\n\n'
    printf 'Homebrew (distributing to others / convenience):\n\n'
    printf '  brew install fissible/tap/ptyunit\n\n'
    printf '  Best when: distributing a CLI tool where consumers run your tests\n'
    printf '  locally without cloning your repo, or convenience matters more than\n'
    printf '  version pinning. Note: "which ptyunit" / "ptyunit --version" can drift\n'
    printf '  if the consumer upgrades brew independently of your project.\n\n'
    printf 'bpkg (lock-file reproducibility):\n\n'
    printf '  bpkg install fissible/ptyunit\n\n'
    printf '  Best when: you want npm-style lock-file reproducibility with a local\n'
    printf '  copy under deps/. bpkg pins the exact version in bpkg.json and copies\n'
    printf '  source into deps/fissible/ptyunit.\n\n'
    printf 'Makefile recommendation (all install methods):\n\n'
    printf '  Whatever install method you choose, wire up a make test target:\n\n'
    printf '    test:\n'
    printf '        bash tests/ptyunit/run.sh --unit\n\n'
    printf '  This gives contributors a single entry point regardless of CI system.\n'
}

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
        if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
            exit 1
        else
            return 1
        fi
    fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && _dispatch "${1:-}"
