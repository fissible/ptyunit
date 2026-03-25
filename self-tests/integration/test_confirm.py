"""Integration tests for PTYSession using examples/confirm.sh."""
import os
import pytest
from pty_session import PTYSession

# Resolve path relative to this file so tests run from any working directory.
_HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.normpath(os.path.join(_HERE, "..", "..", "examples", "confirm.sh"))


def test_initial_render_shows_yes():
    with PTYSession(SCRIPT) as session:
        assert session.screen.find_row("[ Yes ]") is not None


def test_right_moves_to_no():
    with PTYSession(SCRIPT) as session:
        session.send("RIGHT")
        row = session.screen.find_row("[ No ]")
        assert row is not None
        assert "[ No ]" in session.screen.row(row)


def test_right_then_enter_cancels():
    with PTYSession(SCRIPT) as session:
        session.send("RIGHT")
        session.send("ENTER")
        # ENTER on "No" causes confirm.sh to exit — exit_code set by send()
        assert session.exit_code == 0
