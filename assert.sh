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
_PTYUNIT_DESCRIBE_STACK=""

# Begin a named test section. Manages per-test lifecycle:
#   1. Teardown previous section (if not filtered out)
#   2. Clean up mocks
#   3. Restore working directory
#   4. Set name (with describe prefix if applicable)
#   5. Check name filter (PTYUNIT_FILTER_NAME)
#   6. Save working directory
#   7. Setup new section (if ptyunit_setup is defined)
ptyunit_test_begin() {
    # Lifecycle for previous section (skip if it was filtered out)
    if [[ -n "$_PTYUNIT_TEST_NAME" ]] && (( ! _PTYUNIT_SECTION_FILTERED )); then
        if declare -f ptyunit_teardown > /dev/null 2>&1; then
            ptyunit_teardown
        fi
        if declare -f _ptyunit_mock_cleanup_all > /dev/null 2>&1; then
            _ptyunit_mock_cleanup_all
        fi
        if [[ -n "$_PTYUNIT_SAVED_PWD" ]]; then
            cd "$_PTYUNIT_SAVED_PWD" 2>/dev/null || true
        fi
    fi

    # Build the full test name (with describe prefix)
    if [[ -n "$_PTYUNIT_DESCRIBE_STACK" ]]; then
        _PTYUNIT_TEST_NAME="$_PTYUNIT_DESCRIBE_STACK > $1"
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
    if declare -f ptyunit_setup > /dev/null 2>&1; then
        ptyunit_setup
    fi
}
# Readable aliases — use whichever reads most naturally for your test.
test_that() { ptyunit_test_begin "$@"; }
test_it()   { ptyunit_test_begin "$@"; }
test_they() { ptyunit_test_begin "$@"; }

# ── Describe blocks (nestable naming) ───────────────────────────────────────
# Group tests under a label. Nests arbitrarily. Test names become:
#   [outer > inner > test name]

describe() {
    if [[ -n "$_PTYUNIT_DESCRIBE_STACK" ]]; then
        _PTYUNIT_DESCRIBE_STACK+=" > $1"
    else
        _PTYUNIT_DESCRIBE_STACK="$1"
    fi
}

end_describe() {
    if [[ "$_PTYUNIT_DESCRIBE_STACK" == *" > "* ]]; then
        _PTYUNIT_DESCRIBE_STACK="${_PTYUNIT_DESCRIBE_STACK% > *}"
    else
        _PTYUNIT_DESCRIBE_STACK=""
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected: %q\n  actual:   %q\n' "$expected" "$actual"
    fi
}

# Assert two strings are NOT equal.
assert_not_eq() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected not equal to: %q\n' "$expected"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected to contain: %q\n  actual: %q\n' "$needle" "$haystack"
    fi
}

# Assert a string does NOT contain a substring.
assert_not_contains() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected NOT to contain: %q\n  actual: %q\n' "$needle" "$haystack"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        printf ' — expected true: %s\n' "$msg"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        printf ' — expected false: %s\n' "$msg"
    fi
}

# Assert a string is empty (null).
assert_null() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local value="$1" msg="${2:-}"
    if [[ -z "$value" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected empty, got: %q\n' "$value"
    fi
}

# Assert a string is non-empty (not null).
assert_not_null() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local value="$1" msg="${2:-}"
    if [[ -n "$value" ]]; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected non-empty string\n'
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected match: %s\n  actual:         %q\n' "$pattern" "$string"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  file does not exist: %s\n' "$path"
    fi
}

# Assert the Nth line (1-indexed) of a multi-line string equals expected.
# Usage: assert_line "expected" line_number "output" [msg]
assert_line() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local expected="$1" line_number="$2" output="$3" msg="${4:-}"
    local actual="" _ptyunit_i=0
    while IFS= read -r _ptyunit_line || [[ -n "$_ptyunit_line" ]]; do
        (( _ptyunit_i++ )) || true
        if (( _ptyunit_i == line_number )); then
            actual="$_ptyunit_line"
            break
        fi
    done <<< "$output"
    if (( _ptyunit_i < line_number )); then
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  output has %d lines, requested line %d\n' "$_ptyunit_i" "$line_number"
        return
    fi
    assert_eq "$expected" "$actual" "$msg"
}

# Assert actual > threshold (integer comparison).
# Usage: assert_gt actual threshold [msg]
assert_gt() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local actual="$1" threshold="$2" msg="${3:-}"
    if (( actual > threshold )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected: %s > %s\n' "$actual" "$threshold"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected: %s < %s\n' "$actual" "$threshold"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected: %s >= %s\n' "$actual" "$threshold"
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
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  expected: %s <= %s\n' "$actual" "$threshold"
    fi
}

# Print a summary line and exit 1 if any tests failed.
ptyunit_test_summary() {
    # Teardown the final test section (skip if it was filtered out)
    if [[ -n "$_PTYUNIT_TEST_NAME" ]] && (( ! _PTYUNIT_SECTION_FILTERED )); then
        if declare -f ptyunit_teardown > /dev/null 2>&1; then
            ptyunit_teardown
        fi
        if declare -f _ptyunit_mock_cleanup_all > /dev/null 2>&1; then
            _ptyunit_mock_cleanup_all
        fi
        if [[ -n "$_PTYUNIT_SAVED_PWD" ]]; then
            cd "$_PTYUNIT_SAVED_PWD" 2>/dev/null || true
        fi
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
        printf 'FAIL  %d/%d tests passed (%d failed)%s\n' \
            "$_PTYUNIT_TEST_PASS" "$total" "$_PTYUNIT_TEST_FAIL" "$skip_msg"
        return 1
    fi
}
