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

        try:
            self.wait_for_stable()
        except BaseException:
            self.__exit__(None, None, None)
            raise
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
        # Close master fd before waitpid: on macOS, the child may be blocked
        # in a PTY read/write and will not exit until the master side is closed.
        try:
            os.close(self._master_fd)
        except OSError:
            pass
        if self._exit_code is None and self._pid is not None:
            try:
                os.waitpid(self._pid, 0)
            except OSError:
                pass

    def _read_available(self, timeout: float) -> bytes:
        """Read all currently available bytes from the master fd.

        Waits up to *timeout* seconds for the first byte; subsequent reads
        are non-blocking (timeout=0) to drain whatever arrived.
        Returns b"" if nothing arrives within timeout.
        Sets self._eof = True on OSError — on macOS, child exit raises
        OSError(EIO) on the master fd rather than returning b"".
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
        elif self._eof:
            # EOF means child closed the slave — process exit is imminent.
            # Block to catch it rather than leaving exit_code as None.
            try:
                result = os.waitpid(self._pid, 0)
                self._exit_code = os.waitstatus_to_exitcode(result[1])
            except OSError:
                pass

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
