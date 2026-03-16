# ptyunit Integration Guide

How to add ptyunit to an existing bash project.

---

## Directory layout

ptyunit works as a git submodule checked out inside your project's `tests/` directory:

```
your-project/
├── src/
│   └── mylib.sh
└── tests/
    ├── ptyunit/            ← git submodule
    │   ├── assert.sh
    │   ├── run.sh
    │   ├── pty_run.py
    │   └── docker/
    ├── unit/
    │   └── test-mylib.sh
    └── integration/
        └── test-myprompt.sh
```

Add the submodule:

```bash
git submodule add https://github.com/fissible/ptyunit tests/ptyunit
```

---

## Writing unit tests

Unit tests cover pure bash logic — functions, string manipulation, output formatting.
No PTY or Python required.

```bash
#!/usr/bin/env bash
# tests/unit/test-mylib.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/ptyunit/assert.sh"
source "$(cd "$TESTS_DIR/.." && pwd)/src/mylib.sh"

ptyunit_test_begin "greet: returns correct string"
assert_output "Hello, world" greet "world"

ptyunit_test_begin "greet: handles empty name"
assert_output "Hello, " greet ""

ptyunit_test_summary
```

**Rules for unit tests:**
- Source `assert.sh` before any assertions.
- Call `ptyunit_test_begin` before each logical group (sets the label on failures).
- Always end with `ptyunit_test_summary` — it exits 1 if anything failed.
- Keep each test file focused on one component.

---

## Writing PTY integration tests

Integration tests drive TUI scripts through a real pseudoterminal. They require
Python 3. `run.sh` silently skips them when `python3` is absent.

```bash
#!/usr/bin/env bash
# tests/integration/test-myprompt.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$(cd "$TESTS_DIR/.." && pwd)/src/myprompt.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "confirm: y key — confirmed"
out=$(_pty y)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: ESC — cancelled"
out=$(_pty ESC)
assert_contains "$out" "Cancelled"

ptyunit_test_summary
```

**Named keys** accepted by `pty_run.py`:
`UP` `DOWN` `LEFT` `RIGHT` `ENTER` `SPACE` `ESC` `TAB` `SHIFT_TAB`
`BACKSPACE` `DELETE` `HOME` `END` `PAGE_UP` `PAGE_DOWN`

Literal characters (`y`, `q`, `1`) and hex escapes (`\x1b`) are also accepted.

**Tuning PTY timing** (set as env vars before calling `_pty`):

| Variable | Default | When to change |
|----------|---------|----------------|
| `PTY_INIT` | `0.30` | Slow-starting scripts need more init time |
| `PTY_DELAY` | `0.15` | Slow keystroke processing needs larger delay |
| `PTY_TIMEOUT` | `10` | Long-running scripts need more timeout |

---

## Running tests

```bash
# Run all suites (unit + integration if python3 present)
bash tests/ptyunit/run.sh

# Unit tests only (no Python needed)
bash tests/ptyunit/run.sh --unit

# Integration tests only
bash tests/ptyunit/run.sh --integration
```

`run.sh` auto-detects context: when invoked from your project root it discovers
`tests/unit/test-*.sh` and `tests/integration/test-*.sh` there. No wrapper needed.

---

## Docker cross-version matrix

To verify your tests pass on bash 3.2 (macOS default), 4.4, and 5.x:

```bash
bash tests/ptyunit/docker/run-matrix.sh
```

This builds three Alpine-based images (each with Python 3 installed) and runs
your full test suite in each. A failure in any version is a bug.

**Prerequisites:** Docker must be running.

**Force rebuild** (e.g., after updating a Dockerfile):

```bash
bash tests/ptyunit/docker/run-matrix.sh --no-cache
```

The matrix run command (`bash tests/ptyunit/run.sh`) is the same command used
locally — no special Docker configuration needed.

---

## Requirements for your TUI scripts

For PTY integration tests to work, your script must:

1. **Read input from stdin** (or `/dev/tty`) — `pty_run.py` injects keystrokes there.
2. **Render output to stdout or `/dev/tty`** — both are the PTY in the test context.
3. **Print the result to stdout** — `assert_contains` checks the full PTY output,
   which includes both the rendered UI and the final result string.

Scripts that render via `printf` or `echo` to stdout work without modification.
Scripts that use `/dev/tty` for display (the recommended pattern) also work because
`pty.fork()` makes `/dev/tty` point to the PTY slave.

---

## Asserting on TUI output

`pty_run.py` strips ANSI escape codes before returning output. You get plain text.
Use `assert_contains` rather than `assert_eq` for TUI output — the exact whitespace
and layout may vary, but key words ("Confirmed", "apple", "Error:") are stable.

```bash
# Good — checks for the meaningful string
assert_contains "$out" "Confirmed"

# Fragile — checks exact output including whitespace
assert_eq "Confirmed" "$out"
```
