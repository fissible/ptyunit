# PTY Screen Inspection Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `pty_session.py` — a `PTYSession` context manager with a `Screen` wrapper that runs bash TUI scripts in a PTY with pyte as the terminal emulator, enabling assertion on rendered screen state between keystrokes.

**Architecture:** Single new file `pty_session.py` with `Screen` (thin pyte.Screen wrapper) and `PTYSession` (fork + pyte stream + stability polling). Imports `NAMED_KEYS`, `parse_key`, and `ANSI_RE` directly from `pty_run.py`. `pty_run.py` is unchanged — stays stdlib-only. Python tests live under `self-tests/` and run with `pytest` directly (run.sh `.py` discovery is a separate issue, out of scope here).

**Tech Stack:** Python 3, `pyte>=0.8.0`, `pytest` (dev)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `pty_session.py` | **Create** | `Screen` wrapper + `PTYSession` context manager |
| `requirements-screen.txt` | **Create** | Optional pyte runtime dep |
| `self-tests/unit/test_screen.py` | **Create** | Screen wrapper unit tests (pyte-level) |
| `self-tests/integration/test_confirm.py` | **Create** | PTYSession integration tests using `examples/confirm.sh` |
| `pty_run.py` | **Unchanged** | stdlib-only; `NAMED_KEYS`/`parse_key`/`ANSI_RE` imported from here |

---

## Out of Scope

- `run.sh` `.py` test discovery — separate XS issue, sequenced after the first real `.py` test exists
- Snapshot history / screen diffs — additive later if needed
- Coverage integration via `BASH_XTRACEFD` routing — separate concern
- `resize(cols, rows)` mid-session — SIGWINCH delivery + redraw not synchronized with `wait_for_stable()`
- Detecting animation-complete vs. quiescent — no pyte signal for this; callers must use `TimeoutError` as the sample trigger

---

## Implementation Notes

### Partial ANSI sequences
`pyte.ByteStream` buffers incomplete escape sequences internally and only advances the screen on complete sequences. `_read_available` does **not** need to handle split reads — feeding partial bytes to the stream on one call and the rest on the next is safe.

### Default parameter rationale

**`stable_window=0.05` (50ms):** A reasonable lower bound for most interactive TUI render cycles. Most TUIs flush a complete frame within one event loop tick (~1–16ms), so 50ms catches burst-pause-burst renders with margin. It is a *heuristic*, not a guarantee.

When to increase `stable_window`:
- **Slow CI environments** (high load, slow I/O): try 100–200ms if tests flap.
- **Animation-heavy TUIs** that redraw continuously: a TUI with a spinner that redraws every 50ms will never stabilize within a 50ms window. Either poll for a specific frame via `find_row()` or accept `TimeoutError` as the signal to sample the screen.

**`timeout=10.0` (10 seconds):** The outer hard deadline. Guards against programs that produce continuous output and never reach quiescence. 10s is generous for interactive test scripts; reduce to 2–3s for fast unit-style PTY tests.

### Known unhandled edge cases (out of scope for v1)

- **Programs that never stabilize** (continuous redraws, spinners, `watch`-style loops): `wait_for_stable()` runs until `hard_deadline` and raises `TimeoutError`. This is correct — there is no smarter signal from pyte.
- **Resize events mid-session:** `PTYSession` does not expose `resize(cols, rows)`. Sending `TIOCSWINSZ` mid-session is possible but SIGWINCH delivery and subsequent redraw are not synchronized with `wait_for_stable()`.
- **Long-running animations between stable states:** `send("KEY")` waits for quiescence after each keystroke. If a keystroke triggers a 2-second animation before the final frame, `wait_for_stable()` correctly waits (up to `timeout`). Increase `timeout` for these cases.

---

## Internal Structure of `pty_session.py`

```
pty_session.py
├── imports: pyte, pty_run.{NAMED_KEYS, parse_key, ANSI_RE}
├── class Screen                             # wraps pyte.Screen
│   ├── __init__(screen: pyte.Screen)
│   ├── row(n) -> str                        # display[n].rstrip()
│   ├── cell(row, col) -> str                # buffer[row][col].data
│   ├── cell_bold(row, col) -> bool          # buffer[row][col].bold
│   └── find_row(text) -> int | None         # searches display (full-width)
└── class PTYSession
    ├── __init__(script, *, cols, rows, timeout, stable_window, env)
    ├── __enter__() -> PTYSession            # fork → TIOCSWINSZ → wait_for_stable
    ├── __exit__(...)                        # SIGTERM + sleep + SIGKILL; close master fd
    ├── _read_available(timeout) -> bytes    # select loop; sets _eof on OSError
    ├── wait_for_stable(window=None) -> None # dirty-set polling with hard deadline
    ├── send(key) -> None                    # write key → wait_for_stable → check exit
    ├── screen: Screen         (property)
    ├── exit_code: int | None  (property)
    └── stdout: str            (property — ANSI-stripped _raw_output)
```

---

## Recommended Spike (Before Task 2)

The spec flags two load-bearing assumptions that should be validated before writing
`pty_session.py`. Run this spike first — it takes ~10 minutes and prevents a clean-but-wrong
implementation:

```python
# spike_pyte.py — run with: python3 spike_pyte.py
import pyte

# Assumption 1: screen.dirty behaves as documented
s = pyte.Screen(80, 24)
stream = pyte.ByteStream(s)
s.dirty.clear()
stream.feed(b"Hello")
assert s.dirty, "dirty should be non-empty after feeding content"
s.dirty.clear()
stream.feed(b"\x1b[5;5H")  # cursor move only — no content change
# Pure cursor moves should NOT set dirty (spec intentional)
print("dirty after cursor move:", s.dirty)  # expect: empty set

# Assumption 2: burst write drain loop does not miss bytes
import os, pty, time
pid, master = pty.fork()
if pid == 0:
    # Child: write a burst
    import sys
    sys.stdout.write("A" * 8192)
    sys.stdout.flush()
    os._exit(0)
# Parent: drain
import select
buf = b""
while True:
    r, _, _ = select.select([master], [], [], 0.2)
    if not r:
        break
    try:
        chunk = os.read(master, 4096)
        buf += chunk
    except OSError:
        break
os.waitpid(pid, 0)
os.close(master)
print(f"drained {len(buf)} bytes (expected ~8192)")
```

Run it: `python3 spike_pyte.py` — both assertions should hold. If dirty does not clear
on cursor moves, the stability detection logic needs adjustment before writing the real code.

---

## Task 1: Add pyte Dependency

**Files:**
- Create: `requirements-screen.txt`

- [ ] **Step 1: Create requirements-screen.txt**

```
pyte>=0.8.0
```

File path: `requirements-screen.txt`

- [ ] **Step 2: Install and verify**

```bash
pip install -r requirements-screen.txt
python3 -c "import pyte; print(pyte.__version__)"
```

Expected: pyte version printed (0.8.x or higher), no errors.

- [ ] **Step 3: Commit**

```bash
git add requirements-screen.txt
git commit -m "chore: add requirements-screen.txt with pyte>=0.8.0"
```

---

## Task 2: Screen Wrapper (Unit Tests First)

**Files:**
- Create: `self-tests/unit/test_screen.py`
- Create: `pty_session.py` (Screen class only — no PTYSession yet)

- [ ] **Step 1: Write the failing tests**

Create `self-tests/unit/test_screen.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /path/to/ptyunit
pytest self-tests/unit/test_screen.py -v
```

Expected: `ModuleNotFoundError: No module named 'pty_session'`

- [ ] **Step 3: Implement Screen class in pty_session.py**

Create `pty_session.py` with just the Screen class:

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pytest self-tests/unit/test_screen.py -v
```

Expected: all 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pty_session.py self-tests/unit/test_screen.py
git commit -m "feat(pty-session): add Screen wrapper with unit tests"
```

---

## Task 3: PTYSession Core (constructor + enter/exit + read + stability)

Implements the fork machinery, `_read_available`, and `wait_for_stable`. The first
integration test — verifying the initial screen is populated on entry — validates all of this.

**Files:**
- Modify: `pty_session.py` (add PTYSession class)
- Create: `self-tests/integration/test_confirm.py` (first test only)

- [ ] **Step 1: Write the failing integration test**

Create `self-tests/integration/test_confirm.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
pytest self-tests/integration/test_confirm.py::test_initial_render_shows_yes -v
```

Expected: `ImportError` or `AttributeError` — `PTYSession` not yet defined.

- [ ] **Step 3: Implement PTYSession constructor, __enter__, __exit__, _read_available, wait_for_stable**

Append the following to `pty_session.py` (after the Screen class):

```python
class PTYSession:
    """Run a bash script in a PTY with pyte as the terminal emulator.

    Usage:
        with PTYSession("script.sh", cols=80, rows=24) as session:
            assert session.screen.find_row("[ Yes ]") is not None
            session.send("RIGHT")
            assert session.screen.find_row("[ No ]") is not None
    """

    def __init__(
        self,
        script: str,
        *,
        cols: int = 80,
        rows: int = 24,
        timeout: float = 10.0,
        stable_window: float = 0.05,
        env: dict = None,
    ):
        """
        Args:
            script:        Path to the bash script to run.
            cols:          Terminal width in columns.
            rows:          Terminal height in rows.
            timeout:       Max seconds wait_for_stable() may run before TimeoutError.
            stable_window: Seconds of no screen change required to declare stable.
            env:           Extra env vars merged into the inherited environment
                           ({**os.environ, **env}). None means no extra vars.
        """
        self._script = script
        self._cols = cols
        self._rows = rows
        self._timeout = timeout
        self._stable_window = stable_window
        self._env = env

        self._pid = None
        self._master_fd = None
        self._pyte_screen = None
        self._stream = None
        self._raw_output = b""
        self._exit_code = None
        self._eof = False

    def __enter__(self) -> "PTYSession":
        self._pyte_screen = pyte.Screen(self._cols, self._rows)
        self._stream = pyte.ByteStream(self._pyte_screen)

        self._pid, self._master_fd = pty.fork()

        if self._pid == 0:
            # ── Child ────────────────────────────────────────────────────
            winsize = struct.pack("HHHH", self._rows, self._cols, 0, 0)
            try:
                fcntl.ioctl(pty.STDOUT_FILENO, termios.TIOCSWINSZ, winsize)
            except OSError:
                pass
            if self._env is not None:
                merged = {**os.environ, **self._env}
                os.execvpe("bash", ["bash", self._script], merged)
            else:
                os.execvp("bash", ["bash", self._script])
            os._exit(1)  # unreachable — execvp replaces the process

        # ── Parent ───────────────────────────────────────────────────────
        winsize = struct.pack("HHHH", self._rows, self._cols, 0, 0)
        try:
            fcntl.ioctl(self._master_fd, termios.TIOCSWINSZ, winsize)
        except OSError:
            pass

        self.wait_for_stable()
        return self

    def __exit__(self, *args) -> None:
        if self._exit_code is None and self._pid is not None:
            try:
                os.kill(self._pid, signal.SIGTERM)
            except OSError:
                pass
            time.sleep(0.5)
            try:
                os.kill(self._pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                os.waitpid(self._pid, 0)
            except OSError:
                pass
        try:
            os.close(self._master_fd)
        except OSError:
            pass

    def _read_available(self, timeout: float) -> bytes:
        """Read all currently available bytes from the master fd.

        Waits up to *timeout* seconds for the first byte; subsequent reads
        are non-blocking (timeout=0) to drain whatever arrived.
        Returns b"" immediately if nothing arrives within timeout.
        Sets self._eof = True on OSError (child closed slave / EOF).
        """
        buf = b""
        t = timeout
        while True:
            try:
                r, _, _ = select.select([self._master_fd], [], [], t)
            except OSError:
                self._eof = True
                return buf
            if not r:
                return buf
            try:
                chunk = os.read(self._master_fd, 4096)
                if not chunk:
                    self._eof = True
                    return buf
                buf += chunk
                t = 0  # drain remaining available bytes without further waiting
            except OSError:
                self._eof = True
                return buf

    def wait_for_stable(self, window: float = None) -> None:
        """Block until screen content is stable for *window* seconds.

        Raises TimeoutError if self._timeout is exceeded.
        Pure cursor moves do not set pyte's dirty set — only content renders
        reset the stability window, which is intentional.
        """
        window = window if window is not None else self._stable_window
        deadline = time.time() + window
        hard_deadline = time.time() + self._timeout
        while True:
            if time.time() >= hard_deadline:
                raise TimeoutError("screen did not stabilize within timeout")
            self._pyte_screen.dirty.clear()
            remaining = max(0.0, deadline - time.time())
            chunk = self._read_available(timeout=remaining)
            if chunk:
                self._stream.feed(chunk)
                self._raw_output += chunk
            if self._pyte_screen.dirty:
                deadline = time.time() + window  # content changed — reset window
            elif time.time() >= deadline:
                break
            if self._eof:
                break  # child closed slave — no more output coming

    @property
    def screen(self) -> Screen:
        """Current stable screen state as a Screen wrapper."""
        return Screen(self._pyte_screen)

    @property
    def exit_code(self) -> "int | None":
        """Child exit code, or None if the child has not yet exited."""
        return self._exit_code

    @property
    def stdout(self) -> str:
        """ANSI-stripped accumulated output. Valid at any point (partial mid-session)."""
        return ANSI_RE.sub(b"", self._raw_output).decode("utf-8", errors="replace")
```

- [ ] **Step 4: Run test to verify it passes**

```bash
pytest self-tests/integration/test_confirm.py::test_initial_render_shows_yes -v
```

Expected: PASS. The context manager forks, confirm.sh renders its initial UI,
`wait_for_stable()` settles, and `find_row("[ Yes ]")` returns a non-None index.

- [ ] **Step 5: Commit**

```bash
git add pty_session.py self-tests/integration/test_confirm.py
git commit -m "feat(pty-session): add PTYSession core — fork, pyte stream, wait_for_stable"
```

---

## Task 4: send() and exit_code

`exit_code` is already a property (returns `self._exit_code`). This task adds `send()`,
which sets it after a keystroke causes the child to exit.

**Files:**
- Modify: `pty_session.py` (add send() method inside PTYSession)
- Modify: `self-tests/integration/test_confirm.py` (add two tests)

- [ ] **Step 1: Write the failing tests**

Append to `self-tests/integration/test_confirm.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest self-tests/integration/test_confirm.py::test_right_moves_to_no \
       self-tests/integration/test_confirm.py::test_right_then_enter_cancels -v
```

Expected: `AttributeError: 'PTYSession' object has no attribute 'send'`

- [ ] **Step 3: Add send() to PTYSession**

Insert inside the `PTYSession` class, after `wait_for_stable` and before the properties:

```python
    def send(self, key: str) -> None:
        """Send one keystroke, wait for screen stability, then check child exit status.

        Sets self._exit_code if the child exited during or after the keystroke.
        This ensures exit_code is correct when a key causes the script to exit
        (e.g. ENTER on a confirm dialog).
        """
        os.write(self._master_fd, parse_key(key))
        self.wait_for_stable()
        result = os.waitpid(self._pid, os.WNOHANG)
        if result[0] != 0:
            self._exit_code = os.waitstatus_to_exitcode(result[1])
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pytest self-tests/integration/test_confirm.py -v
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pty_session.py self-tests/integration/test_confirm.py
git commit -m "feat(pty-session): add send() with post-keystroke exit_code detection"
```

---

## Task 5: stdout Property Tests

`stdout` is already implemented (added in Task 3). This task writes the test that
validates it.

**Files:**
- Modify: `self-tests/integration/test_confirm.py` (add stdout tests)

- [ ] **Step 1: Write the failing tests**

Append to `self-tests/integration/test_confirm.py`:

```python
def test_stdout_contains_result_after_confirm():
    with PTYSession(SCRIPT) as session:
        session.send("ENTER")  # ENTER on "Yes" → confirm.sh prints "Confirmed"
    assert "Confirmed" in session.stdout


def test_stdout_is_ansi_stripped():
    with PTYSession(SCRIPT) as session:
        pass
    import re
    ansi_re = re.compile(r'\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    assert not ansi_re.search(session.stdout)
```

> **Note:** `confirm.sh` writes TUI output to `/dev/tty` (fd 3) but prints the result
> (`Confirmed`/`Cancelled`) to stdout, which routes through the PTY master.
> So `"Confirmed"` should appear in `session.stdout`.

- [ ] **Step 2: Run tests to verify they fail (or already pass)**

```bash
pytest self-tests/integration/test_confirm.py::test_stdout_contains_result_after_confirm \
       self-tests/integration/test_confirm.py::test_stdout_is_ansi_stripped -v
```

- [ ] **Step 3: Run all integration tests**

```bash
pytest self-tests/integration/test_confirm.py -v
```

Expected: all 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add self-tests/integration/test_confirm.py
git commit -m "test(pty-session): add stdout property integration tests"
```

---

## Task 6: Bold Cell Integration Test

`cell_bold()` is already implemented in `Screen` (Task 2). This task adds the
integration test that validates bold rendering through a real PTY session.

**Files:**
- Modify: `self-tests/integration/test_confirm.py` (add bold test)

- [ ] **Step 1: Inspect confirm.sh escape sequences**

Before writing the test, verify what attributes the button uses:

```bash
PTY_RAW=1 python3 pty_run.py examples/confirm.sh | cat -v | head -5
```

Look for `\033[1m` (bold) vs `\033[7m` (reverse video). The test expectation depends
on this — confirm.sh currently uses `\033[7m` (reverse video), not bold.

- [ ] **Step 2: Write the test matching actual rendering**

Append to `self-tests/integration/test_confirm.py`:

```python
def test_button_uses_reverse_video_not_bold():
    """confirm.sh uses ESC[7m (reverse video) for button highlight, not ESC[1m (bold).

    cell_bold() should return False for the highlighted button.
    If confirm.sh is ever updated to use bold, this test documents the change.
    """
    with PTYSession(SCRIPT) as session:
        row = session.screen.find_row("[ Yes ]")
        assert row is not None
        col = next(
            c for c, char in session.screen._screen.buffer[row].items()
            if char.data == "["
        )
        assert not session.screen.cell_bold(row, col)
```

> **If the inspection in Step 1 shows `\033[1m` (bold) is used instead:** swap
> `assert not` to `assert` and rename the test to `test_button_label_is_bold`.

- [ ] **Step 3: Run all tests**

```bash
pytest self-tests/unit/test_screen.py self-tests/integration/test_confirm.py -v
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add self-tests/integration/test_confirm.py
git commit -m "test(pty-session): add bold/reverse-video attribute integration test"
```

---

## Task 7: Regression Check and Handoff

**Files:** none

- [ ] **Step 1: Run the full existing bash test suite**

```bash
bash run.sh
```

Expected: all existing bash tests pass. `pty_session.py` has no `.sh` tests and
is not sourced by `run.sh`, so no changes to the runner are needed.

- [ ] **Step 2: Run all Python tests from repo root**

```bash
pytest self-tests/unit/test_screen.py self-tests/integration/test_confirm.py -v
```

Expected: all Python tests pass.

- [ ] **Step 3: Update PROJECT.md session handoff**

Note in session handoff:
- `pty_session.py` shipped — new optional dep `requirements-screen.txt` (pyte>=0.8.0)
- `run.sh` `.py` discovery is a separate XS issue — open a ticket, sequence after this ships
- Downstream submodule bumps needed: shellframe, shellql, seed
