# ptyunit

**Most bash test frameworks test what goes to stdout. ptyunit tests what appears on screen.**

If your script renders to `/dev/tty`, navigates menus with arrow keys, or drives an
interactive TUI — no existing bash test framework can touch it. ptyunit can. It opens a
real pseudoterminal, scripts keystrokes into your program, strips the ANSI noise, and
lets you write plain assertions against what a user would actually see. No tmux. No
screen scraping hacks. A real PTY — the same mechanism your terminal emulator uses.

```bash
# Drive a TUI confirm dialog with keystrokes, assert on its output
out=$(python3 pty_run.py examples/confirm.sh RIGHT ENTER)
assert_contains "$out" "Cancelled"
```

---

## What ptyunit provides

**`assert.sh`** — a minimal bash assertion library. Source it, write tests, call
`ptyunit_test_summary` at the end. No dependencies beyond bash itself.

**`pty_run.py`** — the PTY driver. Runs any bash script inside a real pseudoterminal,
injects named keystrokes (`UP`, `DOWN`, `ENTER`, `ESC`, `SPACE`, ...), drains and
ANSI-strips the output, and returns it as plain text. Works with any TUI — shellframe,
dialog, fzf, whiptail, or one you wrote yourself.

**`run.sh`** — the test runner. Discovers `tests/unit/test-*.sh` and
`tests/integration/test-*.sh`, runs each in a subshell, aggregates results, exits
non-zero on any failure. Silently skips integration tests if Python 3 is absent.

**`docker/`** — a Docker cross-version matrix. Runs your full test suite against bash
3.2 (the macOS default), bash 4.4, and bash 5.x in clean Alpine containers — all with
Python installed. A failure in any version is a bug.

---

## Quick start

### Install

ptyunit is a set of files you source or invoke directly. Copy them into your project's
`tests/` directory, or add ptyunit as a git submodule.

```bash
git submodule add https://github.com/fissible/ptyunit tests/ptyunit
```

### Write a unit test

```bash
#!/usr/bin/env bash
# tests/unit/test-mylib.sh

TESTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$TESTS_DIR/ptyunit/assert.sh"

ptyunit_test_begin "greet: returns correct string"
assert_output "Hello, world" greet "world"

ptyunit_test_begin "greet: handles empty name"
assert_output "Hello, " greet ""

ptyunit_test_summary
```

### Write a PTY integration test

```bash
#!/usr/bin/env bash
# tests/integration/test-myprompt.sh

TESTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$TESTS_DIR/../examples/myprompt.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "confirm: y key"
assert_contains "$(_pty y)" "Confirmed"

ptyunit_test_begin "confirm: ESC cancels"
assert_contains "$(_pty ESC)" "Cancelled"

ptyunit_test_summary
```

### Run your tests

```bash
bash tests/ptyunit/run.sh           # all suites
bash tests/ptyunit/run.sh --unit    # unit tests only
bash tests/ptyunit/run.sh --integration  # integration tests only
```

### Run the Docker cross-version matrix

```bash
bash tests/ptyunit/docker/run-matrix.sh
```

---

## assert.sh API

```bash
source path/to/assert.sh
```

#### `ptyunit_test_begin "section name"`

Sets the current test section label. All subsequent assertion failures print this label.
No return value.

#### `assert_eq "$expected" "$actual" ["$msg"]`

Fails if the two strings differ. Failure output:
```
FAIL [section] — msg
  expected: 'hello'
  actual:   'world'
```

#### `assert_output "$expected" command [args...]`

Runs `command [args...]` in a subshell, captures stdout, compares with `assert_eq`.
stderr is discarded.

#### `assert_contains "$haystack" "$needle" ["$msg"]`

Fails if `$needle` is not a substring of `$haystack`. The primary assertion for PTY
integration tests — assert on a word that appears in stripped terminal output.

#### `ptyunit_test_summary`

Prints `OK  N/M tests passed` or `FAIL  N/M tests passed (F failed)`.
**Exits 0** if all assertions passed; **exits 1** if any failed.
Always call this as the last line of every test file.

---

## pty_run.py CLI

```
python3 pty_run.py <script> [KEY ...]
```

Runs `bash <script>` inside a real pseudoterminal. Sends each `KEY` as a keystroke
after the init delay. Prints ANSI-stripped output to stdout.

### Named key tokens

| Token | Meaning |
|-------|---------|
| `UP` `DOWN` `LEFT` `RIGHT` | Arrow keys |
| `ENTER` | Return / confirm |
| `SPACE` | Space bar |
| `ESC` | Escape |
| `TAB` | Tab |
| `SHIFT_TAB` | Shift+Tab |
| `BACKSPACE` | Delete before cursor |
| `DELETE` | Delete at cursor |
| `HOME` `END` | Line start / end |
| `PAGE_UP` `PAGE_DOWN` | Page navigation |

Hex literals (`\x01`) and literal characters (`a`, `q`) are also accepted.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PTY_COLS` | `80` | Terminal width |
| `PTY_ROWS` | `24` | Terminal height |
| `PTY_DELAY` | `0.15` | Seconds between keystrokes |
| `PTY_INIT` | `0.30` | Seconds before first keystroke |
| `PTY_TIMEOUT` | `10` | Seconds to wait for child to exit |

### Exit codes

The exit code of the script itself is propagated. `124` is returned on timeout
(matches GNU `timeout` convention).

### Python API

`pty_run.py` is also importable:

```python
from pty_run import run, parse_key

output, exit_code = run("examples/confirm.sh", ["y"], key_delay=0.1)
```

---

## run.sh

```
bash run.sh [--unit | --integration | --all]
```

Discovers test files by glob (`tests/unit/test-*.sh`, `tests/integration/test-*.sh`).
Runs each in a subshell. Accumulates pass/fail counts. Exits 0 only if all files pass.

Integration tests are silently skipped if `python3` is not in PATH — safe to run in
minimal environments.

---

## Docker cross-version matrix

```
bash docker/run-matrix.sh [--no-cache]
```

Builds and runs three images:

| Image | Bash version | Notes |
|-------|-------------|-------|
| `ptyunit-bash3` | 3.2 | Simulates macOS default shell; multi-stage build |
| `ptyunit-bash4` | 4.4 | Bash 4.x feature set |
| `ptyunit-bash5` | 5.2 | Alpine native |

All images include Python 3. A failure in any version fails the matrix.

---

## Compatibility

- **Bash:** 3.2, 4.x, 5.x
- **Python:** 3.6+ (for `pty_run.py`)
- **OS:** Linux, macOS
- **Dependencies:** none beyond bash and python3

---

## Examples

See [`examples/`](examples/) for minimal self-contained bash scripts that demonstrate
PTY-testable TUI patterns.

---

## License

MIT
