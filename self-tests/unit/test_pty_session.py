"""Behavioral tests for PTYSession (#37).

Covers:
- stdout contains script output after entering the session context
- wait_for_stable() first-byte semantics: stability window starts after first byte
  arrives, not at fork time (#27 regression)
- exit_code captured after send() causes script to exit
- exit_code is None while the script is still running
- __exit__ reaps the child process — no zombie remains
- __exit__ closes the master fd
- send() swallows OSError when master fd returns EIO (#26 regression)
- timeout parameter raises TimeoutError when no output arrives in time
"""
import os

import pytest

from pty_session import PTYSession


@pytest.fixture
def hello_script(tmp_path):
    """Script that prints one line and exits immediately."""
    script = tmp_path / "hello.sh"
    script.write_text("echo hello\n")
    return str(script)


@pytest.fixture
def slow_script(tmp_path):
    """Script that sleeps before printing — validates first-byte semantics."""
    script = tmp_path / "slow.sh"
    script.write_text("sleep 0.3\necho ready\n")
    return str(script)


@pytest.fixture
def blocking_script(tmp_path):
    """Script that prints one line then blocks waiting for PTY input."""
    script = tmp_path / "blocking.sh"
    script.write_text("echo running\nread -r _x </dev/tty\n")
    return str(script)


@pytest.fixture
def confirm_script(tmp_path):
    """Script that reads a single key and exits 0 on 'y', 1 otherwise."""
    script = tmp_path / "confirm.sh"
    script.write_text(
        "echo prompt\n"
        "read -r -n1 _key </dev/tty\n"
        'if [[ "$_key" == "y" ]]; then exit 0; else exit 1; fi\n'
    )
    return str(script)


# ── Screen content and stability ──────────────────────────────────────────────

def test_stdout_contains_output_after_entry(hello_script):
    """Session stdout contains script output after entering the context."""
    with PTYSession(hello_script) as session:
        assert "hello" in session.stdout


def test_wait_for_stable_first_byte_semantics(slow_script):
    """Stability window starts after first byte — blank screen not declared stable.

    Regression for #27: stability clock used to start at fork time, so a script
    with a short delay before output would be declared stable on a blank screen.
    """
    with PTYSession(slow_script, timeout=5.0) as session:
        assert "ready" in session.stdout


# ── exit_code behaviors ────────────────────────────────────────────────────────

def test_exit_code_captured_after_send(confirm_script):
    """exit_code reflects script exit status after a keystroke causes it to exit."""
    with PTYSession(confirm_script) as session:
        session.send("y")
        assert session.exit_code == 0


def test_exit_code_is_none_while_script_running(blocking_script):
    """exit_code is None while the script is still running."""
    with PTYSession(blocking_script) as session:
        assert session.exit_code is None


# ── __exit__ cleanup ───────────────────────────────────────────────────────────

def test_exit_reaps_child_no_zombie(blocking_script):
    """__exit__ reaps the child — further waitpid raises ChildProcessError."""
    with PTYSession(blocking_script) as session:
        pid = session._pid

    with pytest.raises(ChildProcessError):
        os.waitpid(pid, os.WNOHANG)


def test_exit_closes_master_fd(hello_script):
    """__exit__ closes the master fd — further reads raise OSError."""
    with PTYSession(hello_script) as session:
        fd = session._master_fd

    with pytest.raises(OSError):
        os.read(fd, 1)


# ── send() error handling ──────────────────────────────────────────────────────

def test_send_swallows_oserror_when_master_fd_closed(hello_script):
    """send() does not raise when master fd is in EIO state (#26 regression).

    After the child exits, writes to the master fd raise OSError(EIO) on macOS.
    The fix in #26 wraps the write in try/except. This test verifies it holds.
    """
    with PTYSession(hello_script) as session:
        # Force-close the fd to guarantee OSError on write
        try:
            os.close(session._master_fd)
        except OSError:
            pass
        # Must not raise
        session.send("ENTER")


# ── timeout behavior ───────────────────────────────────────────────────────────

def test_timeout_raises_when_script_stalls(tmp_path):
    """TimeoutError is raised when no output arrives within timeout."""
    script = tmp_path / "stall.sh"
    script.write_text("sleep 10\necho done\n")

    with pytest.raises(TimeoutError):
        with PTYSession(str(script), timeout=0.3):
            pass
