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
    printf '  --min=N              Exit 1 if coverage < N%%%%  (CI gate)\n\n'
    printf 'Exclude files:  add glob patterns to .coverageignore at project root\n'
    printf 'Exclude lines:  annotate with  # @pty_skip\n'
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
