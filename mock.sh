#!/usr/bin/env bash
# ptyunit/mock.sh — Mocking and stubbing for bash tests
#
# Usage:
#   source assert.sh   # auto-sources mock.sh
#
#   ptyunit_mock <name> [--output <string>] [--exit <code>]
#   ptyunit_mock <name> << 'BODY'
#     echo "custom mock: $*"
#   BODY
#
# Mocks are auto-cleaned at test section boundaries (test_that / test_it /
# test_they). No manual cleanup needed.
#
# Auto-detection: if <name> is a currently defined function, creates a
# function mock (in-process). Otherwise creates a command mock (PATH-based
# executable script). Command mocks work across subshells and with
# `command <name>`.
#
# Verification assertions:
#   assert_called <name>                 — called at least once
#   assert_not_called <name>             — never called
#   assert_called_times <name> <N>       — called exactly N times
#   assert_called_with <name> <args...>  — last call had these args
#
# Query helpers (for custom assertions):
#   mock_args <name> [N]                 — print args of Nth call (default: last)
#   mock_call_count <name>               — print call count
#
# Inside mock bodies (heredoc), these are available:
#   $MOCK_CALL_NUM   — which invocation this is (1-indexed)
#   $@               — the arguments passed to the mock

_PTYUNIT_MOCK_DIR=""

# ── Initialize mock infrastructure ──────────────────────────────────────────

_ptyunit_mock_init() {
    if [[ -z "$_PTYUNIT_MOCK_DIR" ]]; then
        _PTYUNIT_MOCK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ptyunit-mock.XXXXXX") || {
            # @pty_skip — mktemp failure; infrastructure error path, not testable inline
            printf 'ptyunit: mktemp failed for mock directory\n' >&2
            return 1
        }
        mkdir -p "$_PTYUNIT_MOCK_DIR/bin" "$_PTYUNIT_MOCK_DIR/state" || {
            # @pty_skip — mkdir failure; infrastructure error path, not testable inline
            printf 'ptyunit: failed to create mock directories\n' >&2
            rm -rf "$_PTYUNIT_MOCK_DIR"
            _PTYUNIT_MOCK_DIR=""
            return 1
        }
        printf '%s' "$PATH" > "$_PTYUNIT_MOCK_DIR/original_path"
        PATH="$_PTYUNIT_MOCK_DIR/bin:$PATH"
        export PATH
    fi
}

# ── Create a mock ───────────────────────────────────────────────────────────

ptyunit_mock() {
    local name="$1"; shift
    local mock_output="" mock_exit="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) mock_output="$2"; shift 2 ;;
            --exit)   mock_exit="$2"; shift 2 ;;
            *)        break ;;
        esac
    done

    _ptyunit_mock_init

    local state_dir="$_PTYUNIT_MOCK_DIR/state"

    # Reset state for this mock
    rm -f "$state_dir/$name".* 2>/dev/null
    printf '%s' "$mock_exit" > "$state_dir/$name.exit"
    [[ -n "$mock_output" ]] && printf '%s' "$mock_output" > "$state_dir/$name.output"

    # Read body from stdin if heredoc is provided
    if [[ ! -t 0 ]]; then
        local _body=""
        _body=$(cat 2>/dev/null)
        if [[ -n "$_body" ]]; then
            printf '%s\n' "$_body" > "$state_dir/$name.body"
        fi
    fi

    # Determine mock type
    local mock_type="command"
    if declare -f "$name" > /dev/null 2>&1; then
        mock_type="function"
    fi
    printf '%s' "$mock_type" > "$state_dir/$name.type"

    # Register the mock
    printf '%s\n' "$name" >> "$_PTYUNIT_MOCK_DIR/registry"

    if [[ "$mock_type" == "function" ]]; then
        _ptyunit_mock_create_function "$name" "$state_dir"
    else
        _ptyunit_mock_create_command "$name" "$state_dir"
    fi
}

# ── Create a function mock ──────────────────────────────────────────────────

_ptyunit_mock_create_function() {
    local name="$1" state_dir="$2"

    # Save original function definition
    declare -f "$name" > "$_PTYUNIT_MOCK_DIR/_origfunc_$name" 2>/dev/null || true

    # Create mock function that dispatches to _ptyunit_mock_dispatch
    eval "${name}() { _ptyunit_mock_dispatch '${name}' \"\$@\"; }"
}

# ── Create a command mock (PATH-based executable) ───────────────────────────

_ptyunit_mock_create_command() {
    local name="$1" state_dir="$2"
    local script="$_PTYUNIT_MOCK_DIR/bin/$name"

    # Save original command path
    command -v "$name" > "$state_dir/$name.original_path" 2>/dev/null || true

    cat > "$script" << MOCKSCRIPT
#!/usr/bin/env bash
_state="$state_dir/$name"
_n=\$(cat "\$_state.count" 2>/dev/null || echo 0)
(( _n++ )) || true
printf '%d' "\$_n" > "\$_state.count"
printf '%s\0' "\$@" > "\$_state.args.\$_n"
export MOCK_CALL_NUM="\$_n"
if [[ -f "\$_state.body" ]]; then
    bash "\$_state.body" "\$@"
    exit \$?
elif [[ -f "\$_state.output" ]]; then
    cat "\$_state.output"
fi
exit \$(cat "\$_state.exit" 2>/dev/null || echo 0)
MOCKSCRIPT
    chmod +x "$script"
}

# ── Function mock dispatcher (runs in-process) ─────────────────────────────

_ptyunit_mock_dispatch() {
    local _mock_name="$1"; shift
    local _state="$_PTYUNIT_MOCK_DIR/state/$_mock_name"
    local _n
    _n=$(cat "$_state.count" 2>/dev/null || echo 0)
    (( _n++ )) || true
    printf '%d' "$_n" > "$_state.count"
    printf '%s\0' "$@" > "$_state.args.$_n"
    export MOCK_CALL_NUM="$_n"
    if [[ -f "$_state.body" ]]; then
        bash "$_state.body" "$@"
        return $?
    elif [[ -f "$_state.output" ]]; then
        cat "$_state.output"
    fi
    return $(cat "$_state.exit" 2>/dev/null || echo 0)
}

# ── Remove a single mock ───────────────────────────────────────────────────

ptyunit_unmock() {
    local name="$1"
    [[ -z "$_PTYUNIT_MOCK_DIR" ]] && return
    [[ ! -d "$_PTYUNIT_MOCK_DIR" ]] && return

    local state_dir="$_PTYUNIT_MOCK_DIR/state"
    local mock_type
    mock_type=$(cat "$state_dir/$name.type" 2>/dev/null || echo "command")

    if [[ "$mock_type" == "function" ]]; then
        unset -f "$name" 2>/dev/null
        # Restore original function if it was saved
        if [[ -f "$_PTYUNIT_MOCK_DIR/_origfunc_$name" ]]; then
            source "$_PTYUNIT_MOCK_DIR/_origfunc_$name"
        fi
    else
        rm -f "$_PTYUNIT_MOCK_DIR/bin/$name"
    fi

    rm -f "$state_dir/$name".* 2>/dev/null
}

# ── Clean up all mocks (called at test section boundaries) ──────────────────

_ptyunit_mock_cleanup_all() {
    [[ -z "$_PTYUNIT_MOCK_DIR" ]] && return
    [[ ! -d "$_PTYUNIT_MOCK_DIR" ]] && { _PTYUNIT_MOCK_DIR=""; return; }

    # Unmock each registered mock
    if [[ -f "$_PTYUNIT_MOCK_DIR/registry" ]]; then
        while IFS= read -r _name; do
            [[ -n "$_name" ]] && ptyunit_unmock "$_name"
        done < "$_PTYUNIT_MOCK_DIR/registry"  # @pty_skip
    fi

    # Restore original PATH
    if [[ -f "$_PTYUNIT_MOCK_DIR/original_path" ]]; then
        local _saved_path
        _saved_path=$(<"$_PTYUNIT_MOCK_DIR/original_path")
        if [[ -n "$_saved_path" ]]; then
            PATH="$_saved_path"
            export PATH
        fi
    fi

    [[ -n "$_PTYUNIT_MOCK_DIR" ]] && rm -rf "$_PTYUNIT_MOCK_DIR"
    _PTYUNIT_MOCK_DIR=""
}

# ── Query helpers ───────────────────────────────────────────────────────────

# Print args of the Nth mock call (default: last call).
# Usage: mock_args <name> [N]
mock_args() {
    local name="$1" n="${2:-}"
    [[ -z "$_PTYUNIT_MOCK_DIR" ]] && return 1
    if [[ -z "$n" ]]; then
        n=$(cat "$_PTYUNIT_MOCK_DIR/state/$name.count" 2>/dev/null || echo 0)
    fi
    local f="$_PTYUNIT_MOCK_DIR/state/$name.args.$n"
    [[ -f "$f" ]] || return 1
    # Print each NUL-delimited arg on its own line
    local _arg
    while IFS= read -r -d '' _arg; do
        printf '%s\n' "$_arg"
    done < "$f"
}

# Print the number of times a mock was called.
# Usage: mock_call_count <name>
mock_call_count() {
    local name="$1"
    if [[ -n "$_PTYUNIT_MOCK_DIR" ]] && [[ -f "$_PTYUNIT_MOCK_DIR/state/$name.count" ]]; then
        cat "$_PTYUNIT_MOCK_DIR/state/$name.count"
    else
        printf '0'
    fi
}

# ── Verification assertions ─────────────────────────────────────────────────

# Assert a mock was called at least once.
assert_called() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local name="$1" msg="${2:-}"
    local count
    count=$(mock_call_count "$name")
    if (( count > 0 )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip — only reachable when assertion fails; tested via bash -c subshells
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  mock "%s" was never called\n' "$name"
    fi
}

# Assert a mock was NOT called.
assert_not_called() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local name="$1" msg="${2:-}"
    local count
    count=$(mock_call_count "$name")
    if (( count == 0 )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip — only reachable when assertion fails; tested via bash -c subshells
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  mock "%s" was called %d time(s), expected 0\n' "$name" "$count"
    fi
}

# Assert a mock was called exactly N times.
assert_called_times() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local name="$1" expected="$2" msg="${3:-}"
    local count
    count=$(mock_call_count "$name")
    if (( count == expected )); then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip — only reachable when assertion fails; tested via bash -c subshells
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        [[ -n "$msg" ]] && printf ' — %s' "$msg"
        printf '\n  mock "%s" called %d time(s), expected %d\n' "$name" "$count" "$expected"
    fi
}

# Assert the last call to a mock had specific args.
# Usage: assert_called_with <name> <expected_args...>
# Each argument is compared exactly — "foo bar" (one arg) differs from "foo" "bar" (two args).
assert_called_with() {
    (( _PTYUNIT_SKIP_CURRENT )) && return
    local name="$1"; shift
    local count
    count=$(mock_call_count "$name")

    if (( count == 0 )); then
        # @pty_skip — only reachable when assertion fails; tested via bash -c subshells
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        printf '\n  mock "%s" was never called\n' "$name"
        return
    fi

    local stored_f="$_PTYUNIT_MOCK_DIR/state/$name.args.$count"
    local _tmp_expected
    _tmp_expected=$(mktemp) || {
        _ptyunit_report_fail "assert_called_with: mktemp failed"
        return
    }
    printf '%s\0' "$@" > "$_tmp_expected"

    if cmp -s "$stored_f" "$_tmp_expected"; then
        (( _PTYUNIT_TEST_PASS++ )) || true
    else
        # @pty_skip — only reachable when assertion fails; tested via bash -c subshells
        # Build human-readable arg lists for the failure message
        local _actual_display="" _expected_display="" _arg
        while IFS= read -r -d '' _arg; do
            _actual_display+="${_actual_display:+ }$(printf '%q' "$_arg")"
        done < "$stored_f"
        while IFS= read -r -d '' _arg; do
            _expected_display+="${_expected_display:+ }$(printf '%q' "$_arg")"
        done < "$_tmp_expected"
        (( _PTYUNIT_TEST_FAIL++ )) || true
        printf 'FAIL'
        [[ -n "$_PTYUNIT_TEST_NAME" ]] && printf ' [%s]' "$_PTYUNIT_TEST_NAME"
        printf '\n  mock "%s" last called with: %s\n  expected:                 %s\n' \
            "$name" "$_actual_display" "$_expected_display"
    fi
    rm -f "$_tmp_expected"
}
