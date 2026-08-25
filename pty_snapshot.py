#!/usr/bin/env python3
"""pty_snapshot.py — Screen snapshot assertion for bash-only test suites (#50).

Runs a bash script in a PTY (via PTYSession), sends keys, then compares the
rendered screen against a stored fixture.

Usage:
    python3 pty_snapshot.py [--update] <script> <name> [KEY ...]

    KEY tokens are the same as pty_run.py (UP, DOWN, ENTER, q, \\x1b, ...).

Fixture location:
    $PTYUNIT_SNAPSHOT_DIR/<name>.txt if set, else ./__snapshots__/<name>.txt
    (relative to the current directory — run your suite from a fixed root).

Behavior:
    no fixture   → written, notice on stderr, exit 0
    match        → exit 0
    mismatch     → unified diff on stderr, exit 1
    --update / PTYUNIT_UPDATE_SNAPSHOTS=1 → fixture rewritten, exit 0
    usage/error  → message on stderr, exit 2

Terminal size: PTY_COLS / PTY_ROWS env vars (default 80x24), as pty_run.py.

Typical bash use:
    assert_true python3 "$PTYUNIT_HOME/pty_snapshot.py" menu.sh main-menu DOWN DOWN

Requires: Python 3.9+, pyte (pip install -r requirements-screen.txt)
"""

import os
import sys

from pty_session import PTYSession


def main() -> int:
    args = sys.argv[1:]
    update = False
    if args and args[0] == "--update":
        update = True
        args = args[1:]
    if len(args) < 2 or args[0] in ("-h", "--help"):
        sys.stderr.write(__doc__)
        return 2

    script, name, keys = args[0], args[1], args[2:]
    snapshot_dir = os.environ.get("PTYUNIT_SNAPSHOT_DIR") or os.path.join(os.getcwd(), "__snapshots__")
    cols = int(os.environ.get("PTY_COLS", 80))
    rows = int(os.environ.get("PTY_ROWS", 24))

    try:
        with PTYSession(script, cols=cols, rows=rows) as session:
            for key in keys:
                session.send(key)
            try:
                session.assert_snapshot(name, snapshot_dir=snapshot_dir, update=update)
            except AssertionError as exc:
                sys.stderr.write(f"{exc}\n")
                return 1
    except (OSError, TimeoutError) as exc:
        sys.stderr.write(f"pty_snapshot: {exc}\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
