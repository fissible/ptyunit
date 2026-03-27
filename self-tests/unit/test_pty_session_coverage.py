"""Tests for PTYSession BASH_ENV coverage injection (#34).

Verifies that:
- BASH_ENV is set in the parent process when PTYUNIT_COVERAGE_FILE is set
- BASH_ENV is restored after the session exits (cleanup correctness)
- BASH_ENV is restored even when tmpfile cleanup raises (ordering safety)
- Nested sessions restore BASH_ENV in LIFO order
- PTYUNIT_COVERAGE_FILE not set → BASH_ENV untouched

Breaker pass items covered:
- (a) nested PTYSession objects restore BASH_ENV correctly
- (b) exception in __exit__ cleanup does not leave BASH_ENV dirty
"""
import os
import tempfile

import pytest

from pty_session import PTYSession


@pytest.fixture
def simple_script(tmp_path):
    """Bash script that prints one line and exits immediately."""
    script = tmp_path / "hello.sh"
    script.write_text("echo hello\n")
    return str(script)


@pytest.fixture
def coverage_file(tmp_path):
    """Temp file path to use as PTYUNIT_COVERAGE_FILE."""
    f = tmp_path / "coverage.trace"
    f.touch()
    return str(f)


# ── No-coverage path ─────────────────────────────────────────────────────────

def test_bash_env_not_touched_when_coverage_file_not_set(simple_script, monkeypatch):
    """PTYUNIT_COVERAGE_FILE unset → BASH_ENV not touched before or after session."""
    monkeypatch.delenv("PTYUNIT_COVERAGE_FILE", raising=False)
    monkeypatch.delenv("BASH_ENV", raising=False)

    with PTYSession(simple_script):
        pass

    assert "BASH_ENV" not in os.environ


# ── Coverage injection ────────────────────────────────────────────────────────

def test_bash_env_set_inside_session_when_coverage_file_set(simple_script, coverage_file, monkeypatch):
    """BASH_ENV is present in os.environ inside the with-block (child will inherit it)."""
    monkeypatch.setenv("PTYUNIT_COVERAGE_FILE", coverage_file)
    monkeypatch.delenv("BASH_ENV", raising=False)

    with PTYSession(simple_script):
        assert "BASH_ENV" in os.environ, "BASH_ENV should be set inside the session"


def test_bash_env_unset_after_session_when_was_not_set_before(simple_script, coverage_file, monkeypatch):
    """After the session exits, BASH_ENV is removed if it was not set before."""
    monkeypatch.setenv("PTYUNIT_COVERAGE_FILE", coverage_file)
    monkeypatch.delenv("BASH_ENV", raising=False)

    with PTYSession(simple_script):
        pass

    assert "BASH_ENV" not in os.environ


def test_bash_env_restored_to_previous_value_after_session(simple_script, coverage_file, monkeypatch):
    """After the session exits, BASH_ENV is restored to its original value."""
    monkeypatch.setenv("PTYUNIT_COVERAGE_FILE", coverage_file)
    monkeypatch.setenv("BASH_ENV", "/original/startup.sh")

    with PTYSession(simple_script):
        pass

    assert os.environ.get("BASH_ENV") == "/original/startup.sh"


# ── Breaker (a): nested sessions ─────────────────────────────────────────────

def test_nested_sessions_restore_bash_env_in_lifo_order(simple_script, coverage_file, monkeypatch):
    """Nested PTYSessions restore BASH_ENV correctly in LIFO order."""
    monkeypatch.setenv("PTYUNIT_COVERAGE_FILE", coverage_file)
    monkeypatch.delenv("BASH_ENV", raising=False)

    with PTYSession(simple_script):
        outer_bash_env = os.environ.get("BASH_ENV")
        assert outer_bash_env is not None  # outer injection happened

        with PTYSession(simple_script):
            assert os.environ.get("BASH_ENV") is not None  # inner injection happened

        # After inner exits: BASH_ENV restored to outer's tmpfile path
        assert os.environ.get("BASH_ENV") == outer_bash_env

    # After outer exits: BASH_ENV removed (was not set before)
    assert "BASH_ENV" not in os.environ


# ── Breaker (b): exception safety ────────────────────────────────────────────

def test_bash_env_restored_even_when_tmpfile_cleanup_raises(simple_script, coverage_file, monkeypatch):
    """BASH_ENV is restored before tmpfile cleanup — survives an OSError in os.unlink."""
    monkeypatch.setenv("PTYUNIT_COVERAGE_FILE", coverage_file)
    monkeypatch.delenv("BASH_ENV", raising=False)

    original_unlink = os.unlink

    def raising_unlink(path):
        raise OSError("simulated unlink failure")

    monkeypatch.setattr(os, "unlink", raising_unlink)

    try:
        with PTYSession(simple_script):
            pass
    except OSError:
        pass  # cleanup raised — but BASH_ENV must still be restored

    assert "BASH_ENV" not in os.environ, (
        "BASH_ENV leaked after OSError in __exit__ cleanup — "
        "restore must happen before tmpfile cleanup"
    )
