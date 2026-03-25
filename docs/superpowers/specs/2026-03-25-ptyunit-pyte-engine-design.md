# PTY Screen Inspection Engine — Design Spec

**Date:** 2026-03-25
**Project:** fissible/ptyunit
**Status:** Approved — ready for implementation

---

## Problem

All ptyunit PTY integration tests follow the pattern:

```bash
out=$(python3 pty_run.py script.sh DOWN ENTER)
assert_contains "$out" "Confirmed"
```

This captures final stdout text only. It cannot verify rendering: borders, button
positions, highlights, layout at specific terminal widths. Visual regressions in TUI
widgets are invisible to behavioral tests.

---

## Solution

A new `pty_session.py` module providing `PTYSession` — a thin Python class that runs a
bash script in a PTY with pyte as the terminal emulator. Test authors write `.py` files
that assert on rendered screen state between keystrokes.

---

## Files

| File | Change |
|------|--------|
| `pty_run.py` | **Unchanged** — stays stdlib-only, zero external deps |
| `pty_session.py` | **New** — `PTYSession` + `Screen` wrapper; requires `pyte` |

`pty_run.py`'s `NAMED_KEYS` and `parse_key` are imported by `pty_session.py` to avoid
duplication. No logic changes to `pty_run.py`.

---

## PTYSession API

### Constructor

```python
PTYSession(
    script: str,
    *,
    cols: int = 80,
    rows: int = 24,
    timeout: float = 10.0,
    stable_window: float = 0.05,
    env: dict = None,
)
```

- `stable_window`: seconds of no content change required to declare screen stable
- `timeout`: maximum seconds a single `wait_for_stable()` call may run before raising
  `TimeoutError`. Guards against scripts that produce continuous output and never settle.
  Applied as an outer deadline in `wait_for_stable()` — distinct from `stable_window`,
  which is the quiescence window.
- `env`: extra environment variables **merged into** the inherited environment (not a
  replacement). Implemented as `{**os.environ, **env}` passed to the child.
- The constructor does not fork — forking happens in `__enter__`.

### Context manager

```python
with PTYSession("examples/confirm.sh", cols=80, rows=24) as session:
    ...
```

**`__enter__` sequence:**
1. `pty.fork()` — parent gets `(pid, master_fd)`
2. **Child branch:** set `TIOCSWINSZ` on slave (`pty.STDOUT_FILENO`) → set `BASH_ENV`
   if env provided → `execvp("bash", ["bash", script])` → `os._exit(1)` (unreachable)
3. **Parent branch:** set `TIOCSWINSZ` on `master_fd` → create `pyte.Screen` +
   `pyte.ByteStream` → call `wait_for_stable()` → return `self`

`session.screen` is fully populated before the test body begins.

**`__exit__` sequence:**
1. If `self._exit_code is None` (child still running): send `SIGTERM` → sleep 0.5s →
   send `SIGKILL` → `os.waitpid(pid, 0)`. Wrap each `os.kill` in `try/except OSError`
   in case the process exits between the check and the signal.
2. `os.close(master_fd)` — wrapped in `try/except OSError`.

The SIGTERM grace period allows TUI scripts to restore terminal state (raw mode off,
cursor visible, alternate screen exit) before being killed. Mirrors `pty_run.py`.

### Methods

```python
session.send(key: str) -> None
```

Send one keystroke, then call `wait_for_stable()`. After draining, call
`os.waitpid(pid, WNOHANG)` to check whether the child exited during or after the
keystroke; if so, update `self._exit_code`. This ensures `session.exit_code` is set
correctly when a keystroke causes the script to exit (e.g. `ENTER` on a confirm dialog).

Accepts the same key names as `pty_run.py`: `UP`, `DOWN`, `LEFT`, `RIGHT`, `ENTER`,
`SPACE`, `ESC`, `TAB`, `SHIFT_TAB`, `BACKSPACE`, `DELETE`, `HOME`, `END`, `PAGE_UP`,
`PAGE_DOWN`, plus `\xNN` hex escapes and literal single characters. `NAMED_KEYS` and
`parse_key` imported directly from `pty_run` — no duplication, all stdlib.

```python
session.wait_for_stable(window: float = None) -> None
```

Block until screen content is stable. Escape hatch for cases where stability is needed
without sending a key. Defaults to `stable_window` from constructor.

### Properties

```python
session.screen     # Screen — current stable screen state (updated after each send)
session.exit_code  # int or None — None until child exits; updated by send() and __exit__
session.stdout     # str — ANSI-stripped accumulated output; valid at any point (partial mid-session)
```

`session.stdout` strips ANSI on read using `pty_run.py`'s `ANSI_RE`. Mid-session reads
return partial data accumulated so far. Full data is available after the child exits.

---

## _read_available (internal)

```python
def _read_available(self, timeout: float) -> bytes
```

Instance method (not module-level). Uses `select.select([self._master_fd], [], [], timeout)`
to wait up to `timeout` seconds for data. Reads in a loop until `select` returns no
ready fds within the timeout. Returns `b""` if no data arrives. On `OSError` (child
closed slave / EOF), returns `b""` and sets `self._eof = True`. Callers check
`self._eof` to detect child exit at the fd level.

---

## wait_for_stable() Implementation

```python
def wait_for_stable(self, window=None):
    window = window if window is not None else self._stable_window
    deadline = time.time() + window
    hard_deadline = time.time() + self._timeout
    while True:
        if time.time() >= hard_deadline:
            raise TimeoutError("screen did not stabilize within timeout")
        self._screen.dirty.clear()
        remaining = max(0.0, deadline - time.time())
        chunk = self._read_available(timeout=remaining)
        if chunk:
            self._stream.feed(chunk)
            self._raw_output += chunk
        if self._screen.dirty:
            deadline = time.time() + window   # content changed — reset window
        elif time.time() >= deadline:
            break
        if self._eof:
            break   # child closed slave — no more output coming
```

Key points:
- `screen.dirty` is a `set` of row indices changed since last `.clear()` — pyte does
  not reset it automatically. Truthiness check (`if self._screen.dirty:`) is the correct
  pyte idiom.
- Clear dirty *before* the read window so arriving bytes are caught immediately.
- Reset the deadline on content change (not just "bytes arrived") — handles
  burst-pause-burst renders correctly.
- Pass `remaining` to `select`, not the full window — prevents stable-time inflation
  on tight read loops.
- Break on EOF (`self._eof`) — child has exited, no more output is coming.
- Pure cursor moves do not set `dirty` in pyte — intentional; we wait for content
  renders, not cursor position changes.
- **Partial ANSI sequences** are handled by pyte's `ByteStream` internally — it buffers
  incomplete escape sequences and only advances the screen on complete sequences. Callers
  do not need to handle split reads.

### Default parameter rationale

**`stable_window=0.05` (50ms):** Chosen as a reasonable lower bound for most interactive
TUI render cycles. Most TUIs flush a complete frame within one event loop tick (~1–16ms),
so a 50ms quiescence window catches burst-pause-burst renders with margin. It is a
*heuristic*, not a guarantee.

When to increase `stable_window`:
- **Slow CI environments** (high load, slow I/O): try 100–200ms if tests flap.
- **Animation-heavy TUIs** that redraw continuously: consider whether `stable_window`
  is the right tool — a TUI with a spinner that redraws every 50ms will never stabilize
  within a 50ms window. Either wait for a specific frame via `find_row()` polling or
  accept a `TimeoutError` as the signal to sample the screen.

**`timeout=10.0` (10 seconds):** The outer hard deadline. Guards against programs that
produce continuous output and never reach quiescence. 10s is generous for interactive
test scripts; reduce to 2–3s for fast unit-style PTY tests.

### Known unhandled edge cases

The following are **out of scope for v1** but should be understood before extending:

- **Programs that never stabilize** (continuous redraws, spinners, `watch`-style loops):
  `wait_for_stable()` will run until `hard_deadline` and raise `TimeoutError`. This is
  correct behavior — callers must handle it. There is no smarter signal available from pyte.
- **Resize events mid-session:** `PTYSession` does not expose a `resize(cols, rows)`
  method. Sending `TIOCSWINSZ` mid-session is possible but the SIGWINCH delivery to the
  child and subsequent redraw are not synchronized with `wait_for_stable()`. Out of scope.
- **Long-running animations between two stable states:** `send("KEY")` waits for
  quiescence after each keystroke. If the keystroke triggers a 2-second animation before
  the final frame, `wait_for_stable()` will correctly wait (up to `timeout`). Increase
  `timeout` for these cases.

### Recommended spike before implementation

Before writing `pty_session.py`, run a 10-line spike confirming:
1. `screen.dirty` behaves as documented after feeding bytes to `pyte.ByteStream`
2. The drain loop does not miss bytes on a burst write to the PTY master

These two assumptions are load-bearing. A spike prevents clean-but-wrong implementation.

---

## Screen Wrapper API

`session.screen` is a `Screen` instance (not raw `pyte.Screen`). The wrapper insulates
tests from pyte's internal `Char` namedtuple, which may shift between pyte versions.

**Column coordinates:** `row`, `col` arguments to `cell()` and `cell_bold()` are
**pyte grid coordinates** (0-indexed absolute column in the terminal grid), not offsets
into the string returned by `row()`. Do not use `str.index()` on `row(n)` to derive a
`col` argument — leading spaces would make the result correct only by coincidence. Use
`row(n).find(text)` as an offset only if you know the row has no leading spaces, or use
`screen._screen.buffer` directly for coordinate-precise lookups.

```python
screen.row(n: int) -> str
```
Full rendered text of row `n` (0-indexed), trailing spaces stripped. Does not affect
pyte grid coordinates.

```python
screen.cell(row: int, col: int) -> str
```
Single character at pyte grid coordinate `(row, col)`.

```python
screen.cell_bold(row: int, col: int) -> bool
```
True if the cell at pyte grid coordinate `(row, col)` has bold attribute set.

```python
screen.find_row(text: str) -> int | None
```
Returns the index of the first row whose rendered content contains `text` as a
substring, or `None`. Searches `pyte.Screen.display` (full-width rows, not stripped).

**Reach-through:** `screen._screen` exposes the raw `pyte.Screen` for exotic queries
not covered by the wrapper.

---

## Example Test

```python
# tests/integration/test_confirm.py
from pty_session import PTYSession

SCRIPT = "examples/confirm.sh"

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
        assert session.exit_code == 0   # exit_code set by send() after child exits

def test_button_label_is_bold():
    with PTYSession(SCRIPT) as session:
        row = session.screen.find_row("[ Yes ]")
        # Use pyte grid column, not str.index() — find col via _screen.buffer if needed
        col = next(
            c for c, char in session.screen._screen.buffer[row].items()
            if char.data == "["
        )
        assert session.screen.cell_bold(row, col)
```

---

## Internal Structure

```
pty_session.py
├── _read_available(self, timeout) -> bytes  # instance method; returns b"" on EOF, sets self._eof
├── class Screen                             # thin wrapper over pyte.Screen
│   ├── row(n) -> str                        # trailing-space stripped; does not affect grid coords
│   ├── cell(row, col) -> str                # pyte grid coordinates
│   ├── cell_bold(row, col) -> bool          # pyte grid coordinates
│   └── find_row(text) -> int | None         # searches full-width display rows
└── class PTYSession
    ├── __init__(script, *, cols, rows, timeout, stable_window, env)
    ├── __enter__() -> PTYSession            # fork → TIOCSWINSZ → wait_for_stable
    ├── __exit__(...)                        # SIGTERM/SIGKILL if alive; close master fd
    ├── send(key) -> None                    # write key → wait_for_stable → check exit
    ├── wait_for_stable(window=None) -> None
    ├── screen: Screen         (property)
    ├── exit_code: int | None  (property — None until child exits)
    └── stdout: str            (property — partial mid-session; full after exit)
```

---

## Dependencies

```
pyte>=0.8.0
```

Added to `ptyunit`'s optional deps or a `requirements-screen.txt`. `pty_run.py` has no
new dependencies.

---

## Out of Scope

- `run.sh` `.py` test discovery — separate XS issue, sequenced after the first real `.py`
  test exists and its output format is known
- Snapshot history / screen diffs — additive later if needed
- Coverage integration via `BASH_XTRACEFD` routing — separate concern
- `resize(cols, rows)` mid-session — SIGWINCH delivery + redraw not synchronized
- Detecting animation-complete vs. quiescent (no pyte signal for this)

---

## Effort

**S** (1–2 hours). ~250 lines. All design questions answered. Implementation is direct
translation of this spec.
