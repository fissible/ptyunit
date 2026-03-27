"""Hostile-environment tests for the stability algorithm (#36).

Exercises wait_for_stable() (PTYSession) and _drain_until_stable() (pty_run.py)
under conditions that expose timing-dependent failure modes invisible in synthetic
unit tests.

These tests are NOT part of the default test suite. Run with:
    bash run-hostile.sh

Requirements:
    Python 3, pytest, pyte
    Scenario 3 (jittery): Linux only (requires millisecond sleep precision)
    Scenario 4 (throttled CPU): cpulimit  (Linux; apt-get install cpulimit)

Success criteria: all enabled scenarios pass with no changes to production
code defaults (stable_window=0.05s, timeout=10.0s), except where noted.
"""
import os
import shutil
import subprocess
import sys

import pytest

from pty_session import PTYSession

_D = os.path.dirname(os.path.abspath(__file__))
_PTYUNIT_DIR = os.path.normpath(os.path.join(_D, "..", ".."))
_PTY_RUN = os.path.join(_PTYUNIT_DIR, "pty_run.py")

_cpulimit = shutil.which("cpulimit")


# ── Scenario 1: slow start ────────────────────────────────────────────────────
# Script is silent for 1.5s before producing any output.
#
# Failure mode (pre-fix): wait_for_stable() started the stability clock at
# fork time. After 50ms of silence, it declared the blank screen stable.
# The delayed output was never captured.
#
# Fix (#27): clock starts after first byte arrives. 1.5s of silence is safe
# because deadline hasn't started — the algorithm waits the full timeout for
# the first byte before applying the window.

def test_slow_start_output_not_missed():
    """First-byte gate: 1.5s pre-output delay does not trigger blank-screen stable."""
    with PTYSession(os.path.join(_D, "slow-start.sh"), timeout=10.0) as session:
        assert "slow start output" in session.stdout, (
            f"Expected 'slow start output' — got: {session.stdout!r}\n"
            "Possible regression: stability clock started before first byte."
        )


# ── Scenario 2: mid-render pause ─────────────────────────────────────────────
# Script emits half a line, pauses 0.3s, then emits the second half.
#
# The stability window resets when new content arrives. With stable_window=0.4
# (> 0.3s pause), the window does not fire during the pause, so the second half
# resets it and the complete frame is captured.
#
# NOTE: stable_window=0.4 is required here — the default 0.05s fires during the
# pause and yields a partial frame. Callers whose scripts have a mid-render pause
# longer than the stability window should set stable_window accordingly.

def test_mid_render_pause_complete_frame():
    """Window-reset: mid-render pause of 0.3s is bridged with stable_window=0.4."""
    with PTYSession(
        os.path.join(_D, "mid-render-pause.sh"),
        stable_window=0.4,
        timeout=5.0,
    ) as session:
        assert "first half" in session.stdout, (
            f"Missing 'first half': {session.stdout!r}"
        )
        assert "second half" in session.stdout, (
            f"Missing 'second half' — window fired before second burst arrived.\n"
            f"stdout: {session.stdout!r}"
        )


# ── Scenario 3: jittery output ────────────────────────────────────────────────
# 500 bytes arrive one at a time with ~1ms between each.
#
# With the default 50ms window, each byte resets the clock. The window only
# fires after the burst ends (50ms of quiet). All 500 bytes are collected.
# Total duration: ~550ms of wall-clock time.
#
# Linux only: macOS sleep(1ms) has ~10ms actual precision due to timer
# resolution and process-creation overhead, causing sporadic gaps > 50ms.

@pytest.mark.skipif(sys.platform != "linux", reason="requires millisecond sleep precision (Linux)")
def test_jittery_output_all_bytes_received():
    """Jitter: 500 bytes at 1ms/byte — stability window fires only after burst ends."""
    with PTYSession(os.path.join(_D, "jittery.sh"), timeout=15.0) as session:
        x_count = session.stdout.count("x")
        assert x_count == 500, (
            f"Expected 500 'x' bytes, got {x_count}.\n"
            "Possible regression: stability window fired before burst ended."
        )


# ── Scenario 4: throttled CPU ─────────────────────────────────────────────────
# The bash computation script runs under cpulimit -l 10 (10% CPU cap), making
# the process take ~10x longer before producing output. The first-byte gate
# must not declare stable during the computation.
#
# Skipped when cpulimit is not installed (Linux CI installs it via apt-get).

@pytest.mark.skipif(_cpulimit is None, reason="cpulimit not installed")
def test_throttled_cpu_output_not_missed(tmp_path):
    """Throttled CPU: first-byte gate holds while cpu-work.sh runs under cpulimit."""
    cpu_work = os.path.join(_D, "cpu-work.sh")
    wrapper = tmp_path / "throttled.sh"
    wrapper.write_text(f'exec cpulimit -l 10 -q -- bash "{cpu_work}"\n')
    with PTYSession(str(wrapper), timeout=30.0) as session:
        assert "computed:" in session.stdout, (
            f"Expected 'computed:' in output — got: {session.stdout!r}\n"
            "Possible regression: stability clock started before first byte "
            "of throttled output arrived."
        )


# ── Scenario 5: deadline exceeded ─────────────────────────────────────────────
# Script emits output continuously and never exits. The stability window is
# reset on every byte, so only the hard deadline can terminate the wait.
#
# Two assertions:
# (a) PTYSession.wait_for_stable() raises TimeoutError.
# (b) pty_run.py exits with code 124 (conventional timeout code).

def test_neverending_raises_timeout_in_pty_session():
    """Hard deadline: continuously-emitting script causes TimeoutError."""
    with pytest.raises(TimeoutError):
        with PTYSession(os.path.join(_D, "neverending.sh"), timeout=0.5):
            pass


def test_neverending_exits_124_via_pty_run():
    """Hard deadline: pty_run.py exits 124 when script never terminates."""
    env = {**os.environ, "PTY_TIMEOUT": "0.5"}
    result = subprocess.run(
        ["python3", _PTY_RUN, os.path.join(_D, "neverending.sh")],
        env=env,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 124, (
        f"Expected exit code 124 (timeout), got {result.returncode}.\n"
        f"stderr: {result.stderr.decode(errors='replace')!r}"
    )
