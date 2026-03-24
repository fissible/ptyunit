#!/usr/bin/env bash
# self-tests/integration/test-pty-ansi-strip.sh
# Regression tests for ANSI_RE stripping in pty_run.py.
#
# Guards against the ordering bug where the Fe catch-all ([@-Z\-_]) matched
# single-byte openers for OSC/DCS/SOS/PM/APC, leaving their payloads in output.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_DIR/pty_run.py"

source "$PTYUNIT_DIR/assert.sh"

# Write a fixture script to a temp file so we can emit raw escape sequences
FIXTURE="$(mktemp /tmp/ptyunit-ansi-strip-XXXXXX.sh)"
trap 'rm -f "$FIXTURE"' EXIT

cat > "$FIXTURE" <<'FIXTURE_EOF'
#!/usr/bin/env bash
printf '\033]0;window-title\007'        # OSC BEL-terminated
printf 'osc-bel\n'
printf '\033]0;window-title\033\\'     # OSC ST-terminated
printf 'osc-st\n'
printf '\033Pdcs payload\033\\'        # DCS
printf 'dcs\n'
printf '\033Xsos payload\033\\'        # SOS
printf 'sos\n'
printf '\033^pm payload\033\\'         # PM
printf 'pm\n'
printf '\033_apc payload\033\\'        # APC
printf 'apc\n'
FIXTURE_EOF
chmod +x "$FIXTURE"

_pty() { python3 "$PTY_RUN" "$FIXTURE" "$@" 2>/dev/null; }

# ── OSC ───────────────────────────────────────────────────────────────────────

ptyunit_test_begin "ANSI strip: OSC BEL-terminated sequence is removed"
out=$(_pty)
assert_contains "$out" "osc-bel"
assert_not_contains "$out" "window-title"

ptyunit_test_begin "ANSI strip: OSC ST-terminated sequence is removed"
out=$(_pty)
assert_contains "$out" "osc-st"
assert_not_contains "$out" "window-title"

# ── DCS / SOS / PM / APC ─────────────────────────────────────────────────────

ptyunit_test_begin "ANSI strip: DCS payload is removed"
out=$(_pty)
assert_contains "$out" "dcs"
assert_not_contains "$out" "dcs payload"

ptyunit_test_begin "ANSI strip: SOS payload is removed"
out=$(_pty)
assert_contains "$out" "sos"
assert_not_contains "$out" "sos payload"

ptyunit_test_begin "ANSI strip: PM payload is removed"
out=$(_pty)
assert_contains "$out" "pm"
assert_not_contains "$out" "pm payload"

ptyunit_test_begin "ANSI strip: APC payload is removed"
out=$(_pty)
assert_contains "$out" "apc"
assert_not_contains "$out" "apc payload"

# ── No raw ESC bytes in output ────────────────────────────────────────────────

ptyunit_test_begin "ANSI strip: no raw ESC bytes remain in output"
out=$(_pty)
assert_not_contains "$out" $'\033'

ptyunit_test_summary
