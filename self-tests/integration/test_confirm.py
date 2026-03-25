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


def test_stdout_contains_result_after_confirm():
    with PTYSession(SCRIPT) as session:
        session.send("ENTER")  # ENTER on "Yes" → confirm.sh prints "Confirmed"
    assert "Confirmed" in session.stdout


def test_stdout_is_ansi_stripped():
    from pty_session import ANSI_RE
    with PTYSession(SCRIPT) as session:
        pass
    # Use production ANSI_RE (bytes domain) — covers OSC, DCS, CSI, Fe, nF arms
    assert not ANSI_RE.search(session.stdout.encode("utf-8"))


def test_button_uses_reverse_video_not_bold():
    """confirm.sh uses ESC[7m (reverse video) for button highlight, not ESC[1m (bold).
    cell_bold() returns False; the highlight is a reverse attribute, not bold.
    """
    with PTYSession(SCRIPT) as session:
        row = session.screen.find_row("[ Yes ]")
        assert row is not None
        col = next(
            (c for c, char in session.screen._screen.buffer[row].items()
             if char.data == "["),
            None,
        )
        assert col is not None, f"No '[' found in buffer row {row}"
        assert not session.screen.cell_bold(row, col)
