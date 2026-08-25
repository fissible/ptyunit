"""Tests for pty_run --expect: a per-key checkpoint for bash-only suites (#51).

An ("expect", text) item in the key list — or `--expect text` on the CLI —
requires *text* to be in the cumulative stripped output after the preceding
key settles. On a miss, no further keys are sent and the exit code is 65
(EX_DATAERR) with a diagnostic on stderr.
"""
import os
import subprocess
import sys

import pytest

from pty_run import run

PTY_RUN = os.path.join(os.path.dirname(os.path.abspath(run.__code__.co_filename)), "pty_run.py")


@pytest.fixture
def script(tmp_path):
    s = tmp_path / "two-keys.sh"
    s.write_text(
        'printf "MENU\\n"\n'
        'read -r -n1 k; printf "got=%s\\n" "$k"\n'
        'read -r -n1 k; printf "got2=%s\\n" "$k"\n'
    )
    return str(s)


def test_expect_passes_when_text_is_present(script):
    out, rc = run(script, ["a", ("expect", "got=a"), "b"], timeout=5)
    assert rc == 0
    assert "got2=b" in out


def test_expect_failure_stops_sending_and_exits_65(script):
    out, rc = run(script, ["a", ("expect", "MISSING"), "b"], timeout=5)
    assert rc == 65
    assert "got=a" in out
    assert "got2=" not in out, "keys after a failed --expect must not be sent"


def test_expect_before_any_key_checks_initial_render(script):
    out, rc = run(script, [("expect", "MENU"), "a", "b"], timeout=5)
    assert rc == 0


def test_cli_expect_syntax(script):
    ok = subprocess.run(
        [sys.executable, PTY_RUN, script, "a", "--expect", "got=a", "b"],
        capture_output=True, text=True, timeout=20,
    )
    assert ok.returncode == 0, ok.stderr
    assert "got2=b" in ok.stdout

    bad = subprocess.run(
        [sys.executable, PTY_RUN, script, "a", "--expect", "MISSING", "b"],
        capture_output=True, text=True, timeout=20,
    )
    assert bad.returncode == 65
    assert "--expect" in bad.stderr
    assert "MISSING" in bad.stderr
    assert "got2=" not in bad.stdout


def test_cli_expect_without_argument_is_a_usage_error(script):
    r = subprocess.run(
        [sys.executable, PTY_RUN, script, "a", "--expect"],
        capture_output=True, text=True, timeout=20,
    )
    assert r.returncode == 64  # EX_USAGE
    assert "--expect" in r.stderr
