import pyte
import pytest
from pty_session import Screen


def _make_screen(text: bytes, cols: int = 80, rows: int = 24) -> Screen:
    s = pyte.Screen(cols, rows)
    stream = pyte.ByteStream(s)
    stream.feed(text)
    return Screen(s)


def test_row_returns_text():
    screen = _make_screen(b"Hello")
    assert screen.row(0) == "Hello"


def test_row_strips_trailing_spaces():
    screen = _make_screen(b"Hi")
    assert screen.row(0) == "Hi"
    assert not screen.row(0).endswith(" ")


def test_row_empty_row_returns_empty_string():
    screen = _make_screen(b"")
    assert screen.row(0) == ""


def test_cell_returns_character():
    screen = _make_screen(b"Hello")
    assert screen.cell(0, 0) == "H"
    assert screen.cell(0, 4) == "o"


def test_cell_bold_false_for_plain_text():
    screen = _make_screen(b"Hello")
    assert screen.cell_bold(0, 0) is False


def test_cell_bold_true_for_bold_sequence():
    # ESC[1m = bold on; ESC[0m = reset
    screen = _make_screen(b"\x1b[1mBold\x1b[0m Normal")
    assert screen.cell_bold(0, 0) is True
    # Characters after reset are plain — verify a cell well into "Normal"
    assert screen.cell_bold(0, 7) is False


def test_find_row_returns_row_index():
    screen = _make_screen(b"Line one\r\nLine two")
    assert screen.find_row("one") == 0
    assert screen.find_row("two") == 1


def test_find_row_returns_none_when_absent():
    screen = _make_screen(b"Hello")
    assert screen.find_row("xyz") is None


def test_find_row_matches_substring():
    screen = _make_screen(b"[ Yes ]   No  ")
    assert screen.find_row("Yes") is not None


def test_screen_exposes_raw_pyte_screen():
    s = pyte.Screen(80, 24)
    wrapped = Screen(s)
    assert wrapped._screen is s
