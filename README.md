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

**`run.sh`** — the test runner. Auto-detects context: when called from a consumer
project root it discovers that project's `tests/unit/test-*.sh` and
`tests/integration/test-*.sh`; when called from ptyunit's own root it runs ptyunit's
self-tests. Runs all files through a streaming worker pool, aggregates results, exits
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
bash tests/ptyunit/run.sh                    # all suites
bash tests/ptyunit/run.sh --unit             # unit tests only
bash tests/ptyunit/run.sh --integration      # integration tests only
bash tests/ptyunit/run.sh --jobs 8           # override worker count
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

### Test lifecycle

#### `ptyunit_test_begin "section name"`

Sets the current test section label. All subsequent assertion failures print this label.

#### `ptyunit_test_summary`

Prints `OK  N/M tests passed` or `FAIL  N/M tests passed (F failed)`.
**Exits 0** if all assertions passed; **exits 1** if any failed.
Always call this as the last line of every test file.

#### `ptyunit_skip ["reason"]`

Skips the remainder of the test file with an optional reason message. The runner
displays the file as `SKIP` and does not count it as a failure. Useful for
platform-conditional tests.

```bash
[[ "$(uname)" == "Darwin" ]] || ptyunit_skip "macOS only"
```

#### `ptyunit_require_bash MAJOR [MINOR]`

Skips the test file if the running bash version is older than `MAJOR.MINOR`. Place at
the top of any test file that uses features not available in older bash versions.

```bash
ptyunit_require_bash 4 3   # skip on bash < 4.3
```

In the Docker cross-version matrix, test files with version requirements automatically
skip in containers where bash is too old — no manual filtering needed.

---

### Equality

#### `assert_eq "$expected" "$actual" ["$msg"]`

Fails if the two strings differ.

```
FAIL [section] — msg
  expected: 'hello'
  actual:   'world'
```

#### `assert_not_eq "$unexpected" "$actual" ["$msg"]`

Fails if the two strings are equal.

---

### Substrings

#### `assert_contains "$haystack" "$needle" ["$msg"]`

Fails if `$needle` is not a substring of `$haystack`. The primary assertion for PTY
integration tests — assert on a word that appears in stripped terminal output.

#### `assert_not_contains "$haystack" "$needle" ["$msg"]`

Fails if `$needle` is found in `$haystack`.

---

### Commands

#### `assert_output "$expected" command [args...]`

Runs `command [args...]` in a subshell, captures stdout, compares with `assert_eq`.
stderr is discarded.

#### `assert_true command [args...]`

Fails if `command` exits non-zero.

```bash
assert_true test -f "$config_file"
assert_true grep -q "pattern" "$file"
```

#### `assert_false command [args...]`

Fails if `command` exits zero.

```bash
assert_false test -f "$should_not_exist"
```

---

### Values

#### `assert_null "$value" ["$msg"]`

Fails if `$value` is non-empty.

#### `assert_not_null "$value" ["$msg"]`

Fails if `$value` is empty.

---

## run.sh

```
bash run.sh [--unit | --integration | --all] [--jobs N]
```

Discovers test files by glob (`tests/unit/test-*.sh`, `tests/integration/test-*.sh`).
Runs them through a streaming worker pool and aggregates pass/fail/skip counts.
Exits 0 only if all non-skipped files pass.

Integration tests are silently skipped if `python3` is not in PATH.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--unit` | — | Run unit tests only |
| `--integration` | — | Run integration tests only |
| `--all` | ✓ | Run all suites (default) |
| `--jobs N` | `nproc \|\| 4` | Max concurrent test files |

### Concurrency

Tests run in a streaming worker pool: each file starts as soon as a slot is free rather
than waiting for the full list to be collected first. `--jobs 1` gives sequential
execution, useful for debugging failures.

### setUp and tearDown

Place `setUp.sh` and/or `tearDown.sh` alongside your test files in the suite directory.

- `setUp.sh` runs before each test file. If it exits non-zero, that file is skipped and
  counted as a failure.
- `tearDown.sh` runs after each test file, even if the test failed.
- Both scripts receive `PTYUNIT_TEST_TMPDIR` — a per-test temporary directory created
  by the runner and automatically cleaned up after tearDown. Use it to share state
  between setUp, the test, and tearDown without hardcoding paths.

```
tests/
└── unit/
    ├── setUp.sh          # runs before each test-*.sh
    ├── tearDown.sh       # runs after each test-*.sh
    ├── test-foo.sh
    └── test-bar.sh
```

```bash
# tests/unit/setUp.sh
cp fixture.db "$PTYUNIT_TEST_TMPDIR/test.db"

# tests/unit/test-foo.sh
source "$TESTS_DIR/ptyunit/assert.sh"
assert_true test -f "$PTYUNIT_TEST_TMPDIR/test.db"
ptyunit_test_summary

# tests/unit/tearDown.sh
rm -f "$PTYUNIT_TEST_TMPDIR/test.db"
```

### Skip handling

Test files that call `ptyunit_skip` or `ptyunit_require_bash` exit with code 3. The
runner displays them as `SKIP`, lists them under "Skipped: N file(s)" in the summary,
and does not count them as failures.

### Color

Output is colorized (green OK / yellow SKIP / red FAIL) when stdout is a TTY.

| Variable | Effect |
|----------|--------|
| `NO_COLOR=1` | Suppress all color |
| `FORCE_COLOR=1` | Enable color even when stdout is not a TTY (e.g. CI) |

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

All images include Python 3. A failure in any version fails the matrix. Test files that
call `ptyunit_require_bash` skip automatically in containers where bash is too old.

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
