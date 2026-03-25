"""pty_session.py — PTY screen inspection engine for visual TUI testing.

Provides PTYSession — a context manager that runs a bash script in a PTY
with pyte as the terminal emulator.  Test authors write .py files that
assert on rendered screen state between keystrokes.

Requires: pyte>=0.8.0  (pip install -r requirements-screen.txt)

Usage:
    from pty_session import PTYSession

    with PTYSession("examples/confirm.sh", cols=80, rows=24) as session:
        assert session.screen.find_row("[ Yes ]") is not None
        session.send("RIGHT")
        assert session.screen.find_row("[ No ]") is not None
"""

import fcntl
import os
import pty
import select
import signal
import struct
import termios
import time

import pyte

from pty_run import ANSI_RE, NAMED_KEYS, parse_key  # noqa: F401 (re-exported)


class Screen:
    """Thin wrapper over pyte.Screen that insulates tests from pyte internals.

    Column coordinates in cell() and cell_bold() are pyte grid coordinates
    (0-indexed absolute column) — not offsets into the string returned by row().
    """

    def __init__(self, screen: pyte.Screen):
        self._screen = screen

    def row(self, n: int) -> str:
        """Full rendered text of row n (0-indexed), trailing spaces stripped."""
        return self._screen.display[n].rstrip()

    def cell(self, row: int, col: int) -> str:
        """Single character at pyte grid coordinate (row, col)."""
        return self._screen.buffer[row][col].data

    def cell_bold(self, row: int, col: int) -> bool:
        """True if the cell at pyte grid coordinate (row, col) has bold set."""
        return self._screen.buffer[row][col].bold

    def find_row(self, text: str) -> "int | None":
        """Index of the first row whose full content contains text, or None.

        Searches pyte.Screen.display (full-width rows, not stripped) so that
        leading/trailing spaces in the rendered output are included in the match.
        """
        for i, line in enumerate(self._screen.display):
            if text in line:
                return i
        return None
