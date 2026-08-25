"""Tests for screen snapshot assertions (#50).

Screen.text() gives a normalized full-screen string; PTYSession.assert_snapshot()
compares it against a stored fixture (__snapshots__/<name>.txt beside the
calling test file unless snapshot_dir is given), writing the fixture on first
use and rewriting it when update=True or PTYUNIT_UPDATE_SNAPSHOTS=1.
"""
import os
import subprocess
import sys

import pytest

import pty_session
from pty_session import PTYSession

PTYUNIT_DIR = os.path.dirname(os.path.abspath(pty_session.__file__))
PTY_SNAPSHOT = os.path.join(PTYUNIT_DIR, "pty_snapshot.py")


@pytest.fixture
def script(tmp_path):
    s = tmp_path / "box.sh"
    s.write_text(
        'printf "+----+\\n"\n'
        'printf "| hi |   \\n"\n'      # trailing spaces must be stripped
        'printf "+----+\\n"\n'
        'read -r -n1 k\n'
        'printf "bye\\n"\n'
    )
    return str(s)


def test_screen_text_strips_trailing_spaces_and_blank_rows(script):
    with PTYSession(script, cols=20, rows=6) as s:
        text = s.screen.text()
        s.send("q")
    assert text == "+----+\n| hi |\n+----+"


def test_first_run_writes_fixture_and_passes(script, tmp_path, capsys):
    snap_dir = tmp_path / "snaps"
    with PTYSession(script, cols=20, rows=6) as s:
        s.assert_snapshot("box", snapshot_dir=str(snap_dir))
        s.send("q")
    fixture = snap_dir / "box.txt"
    assert fixture.read_text() == "+----+\n| hi |\n+----+\n"
    assert "wrote new snapshot" in capsys.readouterr().err


def test_matching_fixture_passes(script, tmp_path):
    snap_dir = tmp_path / "snaps"
    snap_dir.mkdir()
    (snap_dir / "box.txt").write_text("+----+\n| hi |\n+----+\n")
    with PTYSession(script, cols=20, rows=6) as s:
        s.assert_snapshot("box", snapshot_dir=str(snap_dir))
        s.send("q")


def test_mismatch_raises_with_unified_diff(script, tmp_path):
    snap_dir = tmp_path / "snaps"
    snap_dir.mkdir()
    (snap_dir / "box.txt").write_text("+----+\n| yo |\n+----+\n")
    with PTYSession(script, cols=20, rows=6) as s:
        with pytest.raises(AssertionError) as exc:
            s.assert_snapshot("box", snapshot_dir=str(snap_dir))
        s.send("q")
    msg = str(exc.value)
    assert "-| yo |" in msg
    assert "+| hi |" in msg
    assert "box.txt" in msg


def test_update_flag_rewrites_fixture(script, tmp_path):
    snap_dir = tmp_path / "snaps"
    snap_dir.mkdir()
    (snap_dir / "box.txt").write_text("stale\n")
    with PTYSession(script, cols=20, rows=6) as s:
        s.assert_snapshot("box", snapshot_dir=str(snap_dir), update=True)
        s.send("q")
    assert (snap_dir / "box.txt").read_text() == "+----+\n| hi |\n+----+\n"


def test_update_env_var_rewrites_fixture(script, tmp_path, monkeypatch):
    monkeypatch.setenv("PTYUNIT_UPDATE_SNAPSHOTS", "1")
    snap_dir = tmp_path / "snaps"
    snap_dir.mkdir()
    (snap_dir / "box.txt").write_text("stale\n")
    with PTYSession(script, cols=20, rows=6) as s:
        s.assert_snapshot("box", snapshot_dir=str(snap_dir))
        s.send("q")
    assert (snap_dir / "box.txt").read_text() == "+----+\n| hi |\n+----+\n"


def test_default_snapshot_dir_is_beside_calling_test_file(script, tmp_path):
    # Write a tiny test module in tmp_path and run it with pytest so the
    # "calling file" is that module, not this one.
    mod = tmp_path / "test_caller.py"
    mod.write_text(
        "import sys\n"
        f"sys.path.insert(0, {PTYUNIT_DIR!r})\n"
        "from pty_session import PTYSession\n"
        "def test_it():\n"
        f"    with PTYSession({script!r}, cols=20, rows=6) as s:\n"
        "        s.assert_snapshot('beside')\n"
        "        s.send('q')\n"
    )
    r = subprocess.run([sys.executable, "-m", "pytest", "-q", str(mod)],
                       capture_output=True, text=True, timeout=60, cwd=str(tmp_path))
    assert r.returncode == 0, r.stdout + r.stderr
    assert (tmp_path / "__snapshots__" / "beside.txt").exists()


def test_cli_pass_then_mismatch(script, tmp_path):
    # The CLI snapshots *after* sending keys, so the echoed "q" and the
    # script's "bye" line are part of the expected screen here.
    expected = "+----+\n| hi |\n+----+\nqbye\n"
    env = {**os.environ, "PTYUNIT_SNAPSHOT_DIR": str(tmp_path / "cli")}
    first = subprocess.run([sys.executable, PTY_SNAPSHOT, script, "box", "q"],
                           capture_output=True, text=True, timeout=30, env=env)
    assert first.returncode == 0, first.stderr
    assert (tmp_path / "cli" / "box.txt").read_text() == expected

    (tmp_path / "cli" / "box.txt").write_text("nope\n")
    second = subprocess.run([sys.executable, PTY_SNAPSHOT, script, "box", "q"],
                            capture_output=True, text=True, timeout=30, env=env)
    assert second.returncode == 1
    assert "+| hi |" in second.stderr

    third = subprocess.run([sys.executable, PTY_SNAPSHOT, "--update", script, "box", "q"],
                           capture_output=True, text=True, timeout=30, env=env)
    assert third.returncode == 0, third.stderr
    assert (tmp_path / "cli" / "box.txt").read_text() == expected
