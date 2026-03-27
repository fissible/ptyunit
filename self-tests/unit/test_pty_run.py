"""Tests for pty_run._drain_until_stable.

Each test exercises one behavior. The two Evidence Mode adversarial tests
(first-byte gate, hard deadline) are marked with their Evidence Mode requirement.
"""
import os
import threading
import time

import pytest

from pty_run import _drain_until_stable


# ── Helpers ──────────────────────────────────────────────────────────────────

def _write_after_delay(write_fd, data, delay):
    """Thread helper: sleep delay seconds, write data, close fd."""
    time.sleep(delay)
    try:
        os.write(write_fd, data)
    except OSError:
        pass
    try:
        os.close(write_fd)
    except OSError:
        pass


def _write_continuously(write_fd, duration, chunk_interval=0.01):
    """Thread helper: write single bytes for duration seconds, then close."""
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        try:
            os.write(write_fd, b"x")
        except OSError:
            break
        time.sleep(chunk_interval)
    try:
        os.close(write_fd)
    except OSError:
        pass


# ── Unit tests ────────────────────────────────────────────────────────────────

def test_drain_until_stable_returns_bytes_when_output_then_quiet():
    """Output arrives immediately, then quiet — returns the bytes."""
    r, w = os.pipe()
    os.write(w, b"hello")
    os.close(w)
    result = _drain_until_stable(r, window=0.05, timeout=2.0)
    os.close(r)
    assert result == b"hello"


def test_drain_until_stable_returns_empty_on_immediate_eof():
    """Write end closed before any data — returns empty bytes without hanging."""
    r, w = os.pipe()
    os.close(w)
    result = _drain_until_stable(r, window=0.05, timeout=1.0)
    os.close(r)
    assert result == b""


def test_drain_until_stable_collects_multiple_bursts():
    """Multiple bursts separated by gaps shorter than window — returns all bytes."""
    r, w = os.pipe()

    def write_bursts(write_fd):
        os.write(write_fd, b"first")
        time.sleep(0.02)
        os.write(write_fd, b"second")
        time.sleep(0.02)
        os.write(write_fd, b"third")
        os.close(write_fd)

    t = threading.Thread(target=write_bursts, args=(w,))
    t.start()
    result = _drain_until_stable(r, window=0.05, timeout=2.0)
    t.join()
    os.close(r)
    assert result == b"firstsecondthird"


# ── Evidence Mode: first-byte gate ───────────────────────────────────────────
# Claim: stability clock does not start until first byte arrives.
# Without this gate, a 50ms window would expire before the 200ms-delayed
# output arrives and the function would return b"" — blank screen false-positive.

def test_drain_until_stable_waits_for_first_byte_before_starting_window():
    """Output delayed 200ms — function waits and returns the bytes, not empty."""
    r, w = os.pipe()
    t = threading.Thread(target=_write_after_delay, args=(w, b"delayed", 0.2))
    t.start()

    start = time.monotonic()
    result = _drain_until_stable(r, window=0.05, timeout=2.0)
    elapsed = time.monotonic() - start

    t.join()
    os.close(r)

    assert result == b"delayed", f"expected b'delayed', got {result!r}"
    assert elapsed >= 0.2, f"returned too early ({elapsed:.3f}s) — stability clock started before first byte"


# ── Evidence Mode: hard deadline ─────────────────────────────────────────────
# Claim: a continuously-outputting process never hits the quiet window,
# but the hard timeout ceiling ensures the function returns without hanging.

def test_drain_until_stable_returns_at_timeout_for_continuous_output():
    """Continuously-outputting fd — returns near timeout, not hanging."""
    r, w = os.pipe()
    t = threading.Thread(target=_write_continuously, args=(w, 5.0))
    t.start()

    start = time.monotonic()
    result = _drain_until_stable(r, window=0.05, timeout=0.3)
    elapsed = time.monotonic() - start

    # Close our end to unblock the writer thread
    try:
        os.close(r)
    except OSError:
        pass
    t.join(timeout=1.0)

    assert elapsed < 0.6, f"took too long ({elapsed:.3f}s) — hard deadline not enforced"
    assert len(result) > 0, "expected some bytes from continuous output"
