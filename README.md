# ptyunit

**Most bash test frameworks stop at stdout. That falls apart for interactive programs.**

ptyunit tests what appears on screen. It runs your script inside a real pseudoterminal, 
drives it with keystrokes, and returns clean text you can assert against. If your code 
uses `/dev/tty`, menus, or TUIs, this is the layer you actually care about.

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

ptyunit is a handful of files you source or invoke directly. The simplest install
is a plain copy — no tooling required:

```bash
curl -fsSL https://github.com/fissible/ptyunit/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 -C tests/ptyunit/ --wildcards \
      '*/assert.sh' '*/pty_run.py' '*/run.sh'
```

To pin a version and pull updates with git, use a submodule:

```bash
git submodule add https://github.com/fissible/ptyunit tests/ptyunit
```

Package manager support (Homebrew, bpkg, Composer, etc.) is welcome via pull
request — the library has no required build steps, so adding metadata files is
straightforward.

### Write a unit test

The function under test:

```bash
# mylib.sh
greet() { printf 'Hello, %s' "$1"; }
```

The test file:

```bash
#!/usr/bin/env bash
# tests/unit/test-mylib.sh

TESTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$TESTS_DIR/ptyunit/assert.sh"
source "mylib.sh"

test_that "greet returns correct string"
assert_output "Hello, world" greet "world"

test_that "greet handles empty name"
assert_output "Hello, " greet ""

ptyunit_test_summary
```

### Write a PTY integration test

`myprompt.sh` is an interactive confirm dialog that renders directly to the
terminal via `/dev/tty`. It looks like this when it runs:

```
Confirm? [ Yes ]   No      ← initial state; Yes is highlighted
Confirm?   Yes    [ No  ]  ← after pressing RIGHT arrow
```

`pty_run.py` drives it inside a real pseudoterminal — injecting keystrokes,
capturing everything that appears on screen, and returning stripped text. The
test then asserts on keywords in that output:

```bash
#!/usr/bin/env bash
# tests/integration/test-myprompt.sh

TESTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$TESTS_DIR/../examples/myprompt.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

test_it "confirms when y is pressed"
assert_contains "$(_pty y)" "Confirmed"

test_it "cancels when ESC is pressed"
assert_contains "$(_pty ESC)" "Cancelled"

test_it "navigates right then confirms"
assert_contains "$(_pty RIGHT ENTER)" "Cancelled"   # RIGHT moves to No

ptyunit_test_summary
```

### Run your tests

```bash
bash tests/ptyunit/run.sh                    # all suites
bash tests/ptyunit/run.sh --unit             # unit tests only
bash tests/ptyunit/run.sh --integration      # integration tests only
bash tests/ptyunit/run.sh --jobs 8           # override worker count
bash tests/ptyunit/run.sh --debug            # sequential + verbose (isolate failures)
```

### Benchmark worker concurrency

```bash
bash tests/ptyunit/bench/concurrency.sh      # 6 synthetic files, 1–nproc workers
bash tests/ptyunit/bench/concurrency.sh 10   # use 10 files instead
```

Generates N test files that each sleep 1 second, runs the suite at every worker
count from 1 to `nproc`, and prints wall-clock time and speedup. Not part of the
regular test suite — run it manually when you want to measure parallelism.

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

#### `ptyunit_test_begin "description"` / `test_that` / `test_it` / `test_they`

Sets the current test section label. All subsequent assertion failures print this label.
`test_that`, `test_it`, and `test_they` are aliases — use whichever reads most naturally:

```bash
test_that "greet returns correct string"
test_it "handles an empty name"
test_they "all return the correct prefix"
```

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
| `--debug` | — | Sets `--jobs 1` and enables verbose; sequential execution for isolating failures |
| `-v`, `--verbose` | — | Show elapsed time for all files; add `tests/second` rate when elapsed ≥ 0.1s |

### Timing

Elapsed time is shown only when it matters — when a file takes ≥ 1 second, or
verbose mode is active. Fast tests stay clean:

```
  test-assert.sh ... OK (20/20)
  test-confirm.sh ... OK (8/8) in 6.0 secs
```

Pass `-v` / `--verbose` to show timing for all files, plus throughput when
elapsed time is measurable:

```
  test-assert.sh  ... OK (20/20) in < 0.1 secs
  test-confirm.sh ... OK (8/8) in 6.0 secs (1.33 tests/second)
```

### Concurrency

Tests run in a streaming worker pool: each file starts as soon as a slot is free rather
than waiting for the full list to be collected first. `--debug` (or `--jobs 1`) gives
sequential execution, useful for isolating failures.

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
