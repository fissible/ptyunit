"""Tests for pty_run.py BASH_ENV coverage injection guard (#44).

pty_run.run() must not enable xtrace in a child bash that lacks
BASH_XTRACEFD (< 4.1): on those versions `set -x` writes to stderr, which
*is* the PTY, so trace lines pollute the captured output.

The 3.2 test needs an old bash on the host (macOS /bin/bash) and is skipped
elsewhere; the modern-bash test runs everywhere.
"""
import os
import shutil
import subprocess

import pytest

from pty_run import run


def _bash_version(path):
    out = subprocess.run(
        [path, "-c", 'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"'],
        capture_output=True, text=True,
    ).stdout.split()
    return int(out[0]), int(out[1])


def _find_old_bash():
    """Return a path to a bash < 4.1, or None."""
    for cand in ("/bin/bash", shutil.which("bash")):
        if cand and os.path.exists(cand) and _bash_version(cand) < (4, 1):
            return cand
    return None


@pytest.fixture
def script(tmp_path):
    s = tmp_path / "tui.sh"
    s.write_text('printf "MENU\\n"; read -r -n1 k; printf "got=%s\\n" "$k"\n')
    return str(s)


@pytest.fixture
def cov_file(tmp_path):
    f = tmp_path / "cov.trace"
    f.touch()
    return str(f)


def _run_with_bash(bash_path, script, cov_file, monkeypatch, tmp_path):
    """Run pty_run.run() with `bash` resolving to bash_path via PATH."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    os.symlink(bash_path, bindir / "bash")
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")
    return run(script, ["q"], coverage_file=cov_file, timeout=5)


def test_old_bash_child_output_has_no_xtrace_lines(script, cov_file, monkeypatch, tmp_path):
    old = _find_old_bash()
    if old is None:
        pytest.skip("no bash < 4.1 on this host")
    out, rc = _run_with_bash(old, script, cov_file, monkeypatch, tmp_path)
    assert rc == 0
    assert "got=q" in out
    assert "\n+" not in ("\n" + out), f"xtrace leaked into PTY output:\n{out}"


def test_modern_bash_child_still_writes_coverage_trace(script, cov_file, monkeypatch, tmp_path):
    modern = shutil.which("bash")
    if _bash_version(modern) < (4, 1):
        pytest.skip("PATH bash is < 4.1")
    out, rc = _run_with_bash(modern, script, cov_file, monkeypatch, tmp_path)
    assert rc == 0
    assert "\n+" not in ("\n" + out)
    assert os.path.getsize(cov_file) > 0, "coverage trace should be non-empty on bash >= 4.1"
