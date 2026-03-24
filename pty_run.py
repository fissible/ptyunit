#!/usr/bin/env python3
"""pty_run.py — Run a bash TUI script in a PTY and capture its output.

Uses pty.fork() so the child has a proper controlling terminal, meaning
/dev/tty works inside TUI scripts (important for scripts that do exec 1>/dev/tty).

Usage:
    python3 pty_run.py <script> [KEY ...]

Keys:
    UP DOWN LEFT RIGHT                    arrow keys
    ENTER SPACE ESC TAB SHIFT_TAB         common keys
    BACKSPACE DELETE HOME END             editing keys
    PAGE_UP PAGE_DOWN                     paging keys
    q, a, v, ...                          literal single characters
    \\x1b, \\r, \\n, ...                  hex escape sequences

Options (set via env vars):
    PTY_COLS=80     terminal width  (default: 80)
    PTY_ROWS=24     terminal height (default: 24)
    PTY_DELAY=0.15  seconds between keys (default: 0.15)
    PTY_INIT=0.30   seconds to wait before first key (default: 0.30)
    PTY_TIMEOUT=10  seconds to wait for process exit (default: 10)
    PTY_RAW=0       set to 1 to preserve ANSI escapes in output (default: 0)
                    WARNING: PTY_RAW=1 bypasses all ANSI stripping. Any escape
                    sequences emitted by the child (including OSC title-sets,
                    cursor moves, charset switches) pass through to stdout and
                    will corrupt the parent terminal. Only use PTY_RAW=1 when
                    stdout is redirected or you are certain the output will not
                    reach a live terminal.

Exit code: the script's own exit code (or 124 on timeout).
"""

import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time

NAMED_KEYS = {
    "UP":        b"\x1b[A",
    "DOWN":      b"\x1b[B",
    "RIGHT":     b"\x1b[C",
    "LEFT":      b"\x1b[D",
    "ENTER":     b"\r",
    "SPACE":     b" ",
    "ESC":       b"\x1b",
    "TAB":       b"\t",
    "SHIFT_TAB": b"\x1b[Z",
    "BACKSPACE": b"\x7f",
    "DELETE":    b"\x1b[3~",
    "HOME":      b"\x1b[H",
    "END":       b"\x1b[F",
    "PAGE_UP":   b"\x1b[5~",
    "PAGE_DOWN": b"\x1b[6~",
}

ANSI_RE = re.compile(
    rb"\x1b(?:"
    # ST-terminated string sequences must come before the Fe catch-all, otherwise
    # the Fe arm ([@-Z\-_]) matches the single opener byte and the payload leaks.
    rb"[PX^_][^\x1b]*\x1b\\"            # DCS / SOS / PM / APC  (ESC P/X/^/_ ... ST)
    rb"|\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC                   (ESC ] ... BEL or ST)
    rb"|[@-Z\\-_]"                       # Fe single-char sequences (after specific arms)
    rb"|[ -/]+[0-~]"                     # nF sequences: ESC + intermediate(s) + final
    rb"|\[[0-?]*[ -/]*[@-~]"             # CSI sequences (ESC [ ... final)
    rb")"
)


def parse_key(token: str) -> bytes:
    if token in NAMED_KEYS:
        return NAMED_KEYS[token]
    # Handle simple \xNN hex escapes
    if re.match(r"^\\x[0-9a-fA-F]{2}$", token):
        return bytes([int(token[2:], 16)])
    return token.encode("utf-8")


def _drain(fd: int, timeout: float = 0.05) -> bytes:
    """Read all currently available bytes from fd within timeout."""
    buf = b""
    while True:
        r, _, _ = select.select([fd], [], [], timeout)
        if not r:
            break
        try:
            chunk = os.read(fd, 4096)
            if not chunk:
                break
            buf += chunk
        except OSError:
            break
    return buf


def run(
    script: str,
    keys: list,
    *,
    key_delay: float = 0.15,
    init_delay: float = 0.30,
    timeout: float = 10.0,
    cols: int = 80,
    rows: int = 24,
    raw: bool = False,
) -> tuple:
    """Run *script* in a PTY with proper controlling terminal.

    Returns (stripped_output, exit_code).
    """
    # pty.fork() creates a PTY pair and forks.
    # The child automatically gets the slave as its controlling terminal,
    # so /dev/tty works correctly inside TUI scripts.
    pid, master = pty.fork()

    if pid == 0:
        # ── Child ────────────────────────────────────────────────────
        # Set terminal size
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        try:
            fcntl.ioctl(pty.STDOUT_FILENO, termios.TIOCSWINSZ, winsize)
        except OSError:
            pass
        os.execvp("bash", ["bash", script])
        # execvp replaces the process; this line is unreachable
        os._exit(1)

    # ── Parent ───────────────────────────────────────────────────────
    # Set terminal size on master side too
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    try:
        fcntl.ioctl(master, termios.TIOCSWINSZ, winsize)
    except OSError:
        pass

    output = b""

    # Let the script start and render its initial UI
    time.sleep(init_delay)
    output += _drain(master)

    # Send keystrokes one at a time
    for key in keys:
        # Check if child already exited
        result = os.waitpid(pid, os.WNOHANG)
        if result[0] != 0:
            break
        try:
            os.write(master, parse_key(key))
        except OSError:
            break
        time.sleep(key_delay)
        output += _drain(master)

    # Wait for the child to exit (up to timeout)
    deadline = time.time() + timeout
    exit_code = None

    while time.time() < deadline:
        result = os.waitpid(pid, os.WNOHANG)
        if result[0] != 0:
            exit_code = os.waitstatus_to_exitcode(result[1])
            break
        r, _, _ = select.select([master], [], [], 0.1)
        if r:
            try:
                chunk = os.read(master, 4096)
                output += chunk
            except OSError:
                # Child closed the slave (exited)
                result = os.waitpid(pid, 0)
                exit_code = os.waitstatus_to_exitcode(result[1])
                break

    if exit_code is None:
        # Timeout — kill the child
        try:
            os.kill(pid, 15)  # SIGTERM
            time.sleep(0.5)
            os.kill(pid, 9)   # SIGKILL
        except OSError:
            pass
        os.waitpid(pid, 0)
        exit_code = 124  # conventional timeout exit code

    # Final drain
    output += _drain(master, timeout=0.2)

    try:
        os.close(master)
    except OSError:
        pass

    if raw:
        result = output.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    else:
        result = ANSI_RE.sub(b"", output)
        result = result.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

    return result.decode("utf-8", errors="replace"), exit_code


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(1)

    script = sys.argv[1]
    keys = sys.argv[2:]

    cols   = int(os.environ.get("PTY_COLS",    80))
    rows   = int(os.environ.get("PTY_ROWS",    24))
    delay  = float(os.environ.get("PTY_DELAY", 0.15))
    init   = float(os.environ.get("PTY_INIT",  0.30))
    tmt    = float(os.environ.get("PTY_TIMEOUT", 10))
    raw    = os.environ.get("PTY_RAW", "0") == "1"

    out, rc = run(script, keys, key_delay=delay, init_delay=init,
                  timeout=tmt, cols=cols, rows=rows, raw=raw)
    sys.stdout.write(out)
    sys.exit(rc)


if __name__ == "__main__":
    main()
