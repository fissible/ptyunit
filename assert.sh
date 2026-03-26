#!/usr/bin/env bash
# ptyunit/assert.sh — Lightweight test assertion helpers
#
# Usage:
#   source assert.sh
#   test_that "my test name"
#   assert_eq "expected" "actual"
#   assert_output "expected output" my_command arg1 arg2
#   ptyunit_test_summary   # prints pass/fail counts; exits 1 if any failed
#
# Per-test lifecycle:
#   Define ptyunit_setup and/or ptyunit_teardown functions in your test file.
#   They run automatically before/after each test section (test_that block).
#
# Per-test skip:
#   Call ptyunit_skip_test [reason] to skip remaining assertions in the
#   current section. The next test_that/test_it/test_they resets the flag.

# Auto-source mock.sh if present
_ptyunit_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$_ptyunit_self_dir/mock.sh" ]]; then
    source "$_ptyunit_self_dir/mock.sh"
fi

_PTYUNIT_TEST_PASS=0
_PTYUNIT_TEST_FAIL=0
_PTYUNIT_TEST_SKIP=0
_PTYUNIT_TEST_NAME=""
_PTYUNIT_SKIP_CURRENT=0
_PTYUNIT_SAVED_PWD=""
_PTYUNIT_SECTION_FILTERED=0
_PTYUNIT_DESCRIBE_STACK=()   # indexed array of describe names (safe with any name content)
_PTYUNIT_DESCRIBE_DEPTH=0
_PTYUNIT_DESCRIBE_SETUPS=()
_PTYUNIT_DESCRIBE_TEARDOWNS=()

# Variables set by run() — available after calling run <command>
output=""
status=0
lines=()

# ── Internal fail reporter (shared by all assertions) ────────────────────────

_ptyunit_report_fail() {
    # @pty_skip — only reachable when an assertion fails; tested via bash -c subshells
    local msg="${1:-}" details="${2:-}"
    (( _PTYUNIT_TEST_FAIL++ )) || true
    printf 'FAIL'
    [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
    [[ -n "$msg" ]] && printf ' — %s' "$msg"
    [[ -n "$details" ]] && printf '\n%s' "$details"
    printf '\n'
}

# ── Section teardown helper (shared by test_begin, end_describe, summary) ───

_ptyunit_teardown_section() {
    if declare -f ptyunit_teardown > /dev/null 2>&1; then
        ptyunit_teardown
    fi
    if declare -f _ptyunit_mock_cleanup_all > /dev/null 2>&1; then
        _ptyunit_mock_cleanup_all
    fi
    # Describe-level teardowns (innermost first)
    local _di
    for (( _di=_PTYUNIT_DESCRIBE_DEPTH-1; _di >= 0; _di-- )); do
        local _dt="${_PTYUNIT_DESCRIBE_TEARDOWNS[$_di]:-}"
        [[ -n "$_dt" ]] && "$_dt"
    done
    if [[ -n "$_PTYUNIT_SAVED_PWD" ]]; then
        cd "$_PTYUNIT_SAVED_PWD" 2>/dev/null || true
    fi
}

# Begin a named test section. Manages per-test lifecycle:
#   1. Teardown previous section (per-test, then describe-level innermost-first)
#   2. Clean up mocks, restore PWD
#   3. Set name (with describe prefix if applicable)
#   4. Check name filter (PTYUNIT_FILTER_NAME)
#   5. Save PWD
#   6. Run describe-level setups (outermost first)
#   7. Run per-test setup (if ptyunit_setup is defined)
ptyunit_test_begin() {
    if [[ -n "$_PTYUNIT_TEST_NAME" ]] && (( ! _PTYUNIT_SECTION_FILTERED )); then
        _ptyunit_teardown_section
    fi

    # Build the full test name (with describe prefix)
    if (( _PTYUNIT_DESCRIBE_DEPTH > 0 )); then
        local _ptyunit_prefix="" _di
        for (( _di=0; _di < _PTYUNIT_DESCRIBE_DEPTH; _di++ )); do
            if [[ -n "$_ptyunit_prefix" ]]; then
                _ptyunit_prefix+=" > ${_PTYUNIT_DESCRIBE_STACK[$_di]}"
            else
                _ptyunit_prefix="${_PTYUNIT_DESCRIBE_STACK[$_di]}"
            fi
        done
        _PTYUNIT_TEST_NAME="$_ptyunit_prefix > $1"
    else
        _PTYUNIT_TEST_NAME="$1"
    fi
    _PTYUNIT_SKIP_CURRENT=0
    _PTYUNIT_SECTION_FILTERED=0

    # Name filter: silently skip non-matching sections
    if [[ -n "${PTYUNIT_FILTER_NAME:-}" ]] && [[ "$_PTYUNIT_TEST_NAME" != *"$PTYUNIT_FILTER_NAME"* ]]; then
        _PTYUNIT_SKIP_CURRENT=1
        _PTYUNIT_SECTION_FILTERED=1
        return
    fi

    _PTYUNIT_SAVED_PWD="$PWD"
    # Describe-level setups (outermost first)
    local _di
    for (( _di=0; _di < _PTYUNIT_DESCRIBE_DEPTH; _di++ )); do
        local _ds="${_PTYUNIT_DESCRIBE_SETUPS[$_di]:-}"
        [[ -n "$_ds" ]] && "$_ds"
    done
    # Per-test setup
    if declare -f ptyunit_setup > /dev/null 2>&1; then
        ptyunit_setup
    fi
}
# Readable aliases — use whichever reads most naturally for your test.
test_that() { ptyunit_test_begin "$@"; }
test_it()   { ptyunit_test_begin "$@"; }
test_they() { ptyunit_test_begin "$@"; }

# ── Describe blocks (nestable scope) ─────────────────────────────────────────
# Group tests under a label with optional per-describe setup/teardown.
# Nests arbitrarily. Setup functions accumulate (outer runs first).
# Teardown functions unwind (inner runs first).
#
# Usage:
#   describe "name" [setup_fn] [teardown_fn]
#     test_that "..."
#   end_describe

describe() {
    local name="$1"
    local setup_fn="${2:-}"
    local teardown_fn="${3:-}"

    _PTYUNIT_DESCRIBE_STACK[$_PTYUNIT_DESCRIBE_DEPTH]="$name"
    _PTYUNIT_DESCRIBE_SETUPS[$_PTYUNIT_DESCRIBE_DEPTH]="$setup_fn"
    _PTYUNIT_DESCRIBE_TEARDOWNS[$_PTYUNIT_DESCRIBE_DEPTH]="$teardown_fn"
    (( _PTYUNIT_DESCRIBE_DEPTH++ )) || true
}

end_describe() {
    # Teardown the active test section before popping (ensures describe-level
    # teardowns run while the depth is still correct)
    if [[ -n "$_PTYUNIT_TEST_NAME" ]] && (( ! _PTYUNIT_SECTION_FILTERED )); then
        _ptyunit_teardown_section
        _PTYUNIT_TEST_NAME=""
    fi

    if (( _PTYUNIT_DESCRIBE_DEPTH > 0 )); then
        (( _PTYUNIT_DESCRIBE_DEPTH-- )) || true
        _PTYUNIT_DESCRIBE_STACK[$_PTYUNIT_DESCRIBE_DEPTH]=""
        _PTYUNIT_DESCRIBE_SETUPS[$_PTYUNIT_DESCRIBE_DEPTH]=""
        _PTYUNIT_DESCRIBE_TEARDOWNS[$_PTYUNIT_DESCRIBE_DEPTH]=""
    fi
}

# ── Parameterized tests ─────────────────────────────────────────────────────
# Run a callback once per line from stdin. Fields are split on |.
#
# Usage:
#   test_each <callback> << 'PARAMS'
#   input1|input2|expected
#   input3|input4|expected
#   PARAMS
#
# The callback receives each field as $1, $2, $3, etc.
# A test_that section is created for each row, named after the callback
# and the raw parameter line.
# Lines starting with # are skipped.

test_each() {
    local callback="$1"
    local _ptyunit_pline
    while IFS= read -r _ptyunit_pline || [[ -n "$_ptyunit_pline" ]]; do
        [[ -z "$_ptyunit_pline" || "$_ptyunit_pline" == \#* ]] && continue
        local _ptyunit_params=()
        IFS='|' read -ra _ptyunit_params <<< "$_ptyunit_pline"
        ptyunit_test_begin "$callback (${_ptyunit_pline})"
        "$callback" "${_ptyunit_params[@]}"
    done
}

# Skip the current test section. Assertions are silently skipped until the
# next test_that / test_it / test_they call.
# Usage: ptyunit_skip_test [reason]
ptyunit_skip_test() {
    (( _PTYUNIT_SKIP_CURRENT )) && return   # already skipped — don't double-count
    local reason="${1:-}"
    _PTYUNIT_SKIP_CURRENT=1
    (( _PTYUNIT_TEST_SKIP++ )) || true
    printf 'SKIP [%s]' "${_PTYUNIT_TEST_NAME:-unnamed}"
    [[ -n "$reason" ]] && printf ' (%s)' "$reason"
    printf '\n'
}

# Skip this test file with an optional reason. Exits with code 3 (skip signal).
# Usage: ptyunit_skip [reason]
ptyunit_skip() {
    local reason="${1:-}"
    if [[ -n "$reason" ]]; then
        printf 'SKIP (%s)\n' "$reason"
    else
        printf 'SKIP\n'
    fi
    exit 3
}

# Skip this test file if the running bash is older than MAJOR[.MINOR].
# Usage: ptyunit_require_bash MAJOR [MINOR]
ptyunit_require_bash() {
    local major="$1" minor="${2:-0}"
    if (( BASH_VERSINFO[0] < major )) ||
       (( BASH_VERSINFO[0] == major && BASH_VERSINFO[1] < minor )); then
        ptyunit_skip "requires bash ${major}.${minor}, running ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    fi
}

# ── Assertions ──────────────────────────────────────────────────────────────

# Assert two strings are equal.
assert_eq() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected: %q\n  actual:   %q' "$expected" "$actual")"
    fi
}

# Assert two strings are NOT equal.
assert_not_eq() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected not equal to: %q' "$expected")"
    fi
}

# Assert a command's stdout equals the expected string.
# Usage: assert_output "expected" command [args...]
assert_output() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local expected="$1"
    shift
    local actual
    actual=$("$@" 2>/dev/null)
    assert_eq "$expected" "$actual" "$*"
}

# Assert a string contains a substring.
assert_contains() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected to contain: %q\n  actual: %q' "$needle" "$haystack")"
    fi
}

# Assert a string does NOT contain a substring.
assert_not_contains() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected NOT to contain: %q\n  actual: %q' "$needle" "$haystack")"
    fi
}

# Assert a command exits 0 (true).
# Usage: assert_true command [args...]
assert_true() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local msg="$*"
    if "$@" 2>/dev/null; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "expected true: $msg"
    fi
}

# Assert a command exits non-zero (false).
# Usage: assert_false command [args...]
assert_false() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local msg="$*"
    if ! "$@" 2>/dev/null; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "expected false: $msg"
    fi
}

# Assert a string is empty (null).
assert_null() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local value="$1" msg="${2:-}"
    if [[ -z "$value" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected empty, got: %q' "$value")"
    fi
}

# Assert a string is non-empty (not null).
assert_not_null() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local value="$1" msg="${2:-}"
    if [[ -n "$value" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "  expected non-empty string"
    fi
}

# Assert a string matches a regex pattern (bash =~ operator).
# Usage: assert_match "pattern" "string" [msg]
assert_match() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local pattern="$1" string="$2" msg="${3:-}"
    if [[ "$string" =~ $pattern ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected match: %s\n  actual:         %q' "$pattern" "$string")"
    fi
}

# Assert a regular file exists at the given path.
# Usage: assert_file_exists "path" [msg]
assert_file_exists() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local path="$1" msg="${2:-}"
    if [[ -f "$path" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  file does not exist: %s' "$path")"
    fi
}

# Assert the Nth line (1-indexed) of a multi-line string equals expected.
# Usage: assert_line "expected" line_number "output" [msg]
assert_line() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local expected="$1" line_number="$2" output="$3" msg="${4:-}"
    # Validate line_number is a positive integer
    if ! [[ "$line_number" =~ ^[1-9][0-9]*$ ]]; then
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  line_number must be a positive integer, got: %s' "$line_number")"
        return
    fi
    local actual="" _ptyunit_i=0
    while IFS= read -r _ptyunit_line || [[ -n "$_ptyunit_line" ]]; do
        (( _ptyunit_i++ )) || true
        if (( _ptyunit_i == line_number )); then
            actual="$_ptyunit_line"
            break
        fi
    done <<< "$output"
    if (( _ptyunit_i < line_number )); then
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  output has %d lines, requested line %d' "$_ptyunit_i" "$line_number")"
        return
    fi
    assert_eq "$expected" "$actual" "$msg"
}

# Assert that a substring appears exactly N times in a string.
# Usage: assert_count "haystack" "needle" expected_count [msg]
assert_count() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local haystack="$1" needle="$2" expected="$3" msg="${4:-}"
    if [[ -z "$needle" ]]; then
        # @pty_skip
        _ptyunit_report_fail "$msg" "  needle must be non-empty"
        return
    fi
    local count=0 tmp="$haystack"
    while [[ "$tmp" == *"$needle"* ]]; do
        (( count++ ))
        tmp="${tmp#*"$needle"}"
    done
    if (( count == expected )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected %d occurrence(s) of: %q\n  actual count: %d' "$expected" "$needle" "$count")"
    fi
}

# Assert actual > threshold (integer comparison).
# Usage: assert_gt actual threshold [msg]
assert_gt() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local actual="$1" threshold="$2" msg="${3:-}"
    if (( actual > threshold )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected: %s > %s' "$actual" "$threshold")"
    fi
}

# Assert actual < threshold (integer comparison).
# Usage: assert_lt actual threshold [msg]
assert_lt() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local actual="$1" threshold="$2" msg="${3:-}"
    if (( actual < threshold )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected: %s < %s' "$actual" "$threshold")"
    fi
}

# Assert actual >= threshold (integer comparison).
# Usage: assert_ge actual threshold [msg]
assert_ge() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local actual="$1" threshold="$2" msg="${3:-}"
    if (( actual >= threshold )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected: %s >= %s' "$actual" "$threshold")"
    fi
}

# Assert actual <= threshold (integer comparison).
# Usage: assert_le actual threshold [msg]
assert_le() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local actual="$1" threshold="$2" msg="${3:-}"
    if (( actual <= threshold )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip
        _ptyunit_report_fail "$msg" "$(printf '  expected: %s <= %s' "$actual" "$threshold")"
    fi
}

# ── run helper ───────────────────────────────────────────────────────────────
# Capture a command's stdout+stderr and exit code in one call.
# Sets: $output (string), $status (integer), $lines (array).
#
# Usage:
#   run my_command arg1 arg2
#   assert_eq "0" "$status"
#   assert_contains "$output" "success"
#   assert_eq "first line" "${lines[0]}"

run() {
    local _rc=0
    output=$("$@" 2>&1) || _rc=$?
    status=$_rc
    lines=()
    if [[ -n "$output" ]]; then
        while IFS= read -r _ptyunit_run_line; do
            lines+=("$_ptyunit_run_line")
        done <<< "$output"
    fi
}

# ── Custom matcher primitives ────────────────────────────────────────────────
# Building blocks for user-defined assertions. Use these to write your own
# assert_* functions that integrate with ptyunit's pass/fail counters.
#
# Usage:
#   assert_valid_json() {
#       local value="$1"
#       if echo "$value" | python3 -m json.tool > /dev/null 2>&1; then
#           ptyunit_pass
#       else
#           ptyunit_fail "expected valid JSON, got: $value"
#       fi
#   }

ptyunit_pass() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    (( _PTYUNIT_TEST_PASS++ )) || true
}

ptyunit_fail() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    # @pty_skip — rest of body only reachable when a custom assertion fails inline
    local msg="${1:-assertion failed}"
    (( _PTYUNIT_TEST_FAIL++ )) || true
    printf 'FAIL'
    [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
    printf ' — %s\n' "$msg"
}

# Print a summary line and exit 1 if any tests failed.
ptyunit_test_summary() {
    # Teardown the final test section (skip if it was filtered out)
    if [[ -n "$_PTYUNIT_TEST_NAME" ]] && (( ! _PTYUNIT_SECTION_FILTERED )); then
        _ptyunit_teardown_section
    fi
    local total=$(( _PTYUNIT_TEST_PASS + _PTYUNIT_TEST_FAIL ))
    local skip_msg=""
    if (( _PTYUNIT_TEST_SKIP > 0 )); then
        skip_msg=" ($_PTYUNIT_TEST_SKIP skipped)"
    fi
    if (( _PTYUNIT_TEST_FAIL == 0 )); then
        printf 'OK  %d/%d tests passed%s\n' "$_PTYUNIT_TEST_PASS" "$total" "$skip_msg"
        return 0
    else
        # @pty_skip — only reached when inline tests fail; covered via subshell tests
        printf 'FAIL  %d/%d tests passed (%d failed)%s\n' \
            "$_PTYUNIT_TEST_PASS" "$total" "$_PTYUNIT_TEST_FAIL" "$skip_msg"
        return 1
    fi
}
