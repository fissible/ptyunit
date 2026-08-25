"""Tests for pty_run.strip_ansi — the output-cleaning path used by run().

A child killed mid-escape-sequence (timeout) leaves a truncated prefix such
as b"\\x1b[3" at the end of the buffer. ANSI_RE alone cannot match it (no
final byte), so the raw ESC would leak into "stripped" output (#45).
"""
import pytest

from pty_run import strip_ansi


@pytest.mark.parametrize("raw, expected", [
    (b"plain", b"plain"),
    (b"\x1b[1mbold\x1b[0m", b"bold"),
    (b"a\r\nb\rc", b"a\nb\nc"),
])
def test_strips_complete_sequences_and_normalizes_newlines(raw, expected):
    assert strip_ansi(raw) == expected


@pytest.mark.parametrize("raw, expected", [
    (b"ok\x1b[3", b"ok"),          # truncated CSI
    (b"ok\x1b[", b"ok"),           # bare CSI opener
    (b"ok\x1b", b"ok"),            # bare ESC
    (b"ok\x1b]0;title", b"ok"),    # truncated OSC
    (b"ok\x1bP1$r", b"ok"),        # truncated DCS
])
def test_drops_trailing_incomplete_sequence(raw, expected):
    assert strip_ansi(raw) == expected


def test_incomplete_sequence_only_dropped_at_end():
    # An ESC in the middle followed by a real sequence must still strip
    # normally; nothing before the tail is touched.
    assert strip_ansi(b"a\x1b[1mb\x1b[") == b"ab"
