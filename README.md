# ptyunit

Test your bash scripts. Even the interactive ones that take over the terminal.

```bash
source tests/ptyunit/assert.sh

test_that "math still works"
assert_eq "4" "$(( 2 + 2 ))"

greet() {
  echo "Hello, " "$1"
}
test_that "my function greets people"
assert_output "Hello, world" greet "world"

ptyunit_test_summary
```

```
$ bash tests/unit/test-math.sh
OK  2/2 tests passed
```

---

## Install

```bash
git submodule add https://github.com/fissible/ptyunit tests/ptyunit
```

That's it. One file to source (`assert.sh`), one runner to call (`run.sh`), zero build steps.

> **Other install options:** You can also `curl` the individual files, or copy the directory directly. There are no compiled artifacts or package manager dependencies. If you want to add Homebrew/bpkg/etc. support, PRs are welcome.

---

## What can it do?

### Test regular bash functions

Write your functions. Write tests. Get a pass/fail count.

```bash
source tests/ptyunit/assert.sh
source src/mylib.sh

test_that "greet says hello"
assert_output "Hello, world" greet "world"

test_that "add does addition"
result=$(add 3 4)
assert_eq "7" "$result"
assert_gt "$result" 0

ptyunit_test_summary
```

### Test interactive terminal programs

Most test frameworks can only capture stdout. If your script opens `/dev/tty` for a menu, a prompt, or a TUI — they can't touch it. ptyunit can.

```bash
# Drive a TUI with keystrokes, get back plain text
out=$(python3 tests/ptyunit/pty_run.py my_menu.sh DOWN DOWN ENTER)
assert_contains "$out" "You selected: cherry"
```

> **How it works:** `pty_run.py` runs your script inside a real pseudoterminal (PTY), sends keystrokes like `UP`, `DOWN`, `ENTER`, `ESC`, strips all ANSI escape codes, and returns clean text. It supports any program that renders to a terminal — shellframe, dialog, fzf, whiptail, or your own.

### Mock external commands

Replace any command with a fake. Record calls. Verify what happened. Mocks clean up automatically when the next test starts.

```bash
test_that "deploy pushes to staging"
ptyunit_mock git --output "pushed"
ptyunit_mock curl --exit 0

deploy_to_staging

assert_called git
assert_called_with git "push" "origin" "staging"
assert_called_times curl 1
```

Need the mock to do something smarter? Use a heredoc body:

```bash
test_that "handles git errors gracefully"
ptyunit_mock git << 'MOCK'
case "$1" in
    push)   echo "error: rejected"; exit 1 ;;
    status) echo "On branch main" ;;
esac
MOCK

result=$(deploy_to_staging 2>&1)
assert_contains "$result" "deploy failed"
```

> **Under the hood:** Command mocks create tiny executable scripts in a temp directory prepended to `$PATH`. Function mocks use `eval` to replace the function with a recording wrapper. Both record every call's arguments to files, which the `assert_called*` assertions read. Everything is cleaned up at the next `test_that` boundary — no manual teardown needed.

### Run the same test with different inputs

```bash
_verify_add() {
    assert_eq "$3" "$(( $1 + $2 ))"
}

test_each _verify_add << 'PARAMS'
1|2|3
10|20|30
-1|1|0
0|0|0
PARAMS
```

Each row becomes its own test section. Fields are split on `|` and passed as `$1`, `$2`, `$3`, etc. to your callback.

> **Details:** Lines starting with `#` are skipped (comments). Empty lines are skipped. If any row's callback fails an assertion, it's reported against that specific row.

### Group tests with describe blocks

```bash
describe "string utils"
    describe "upper"
        test_that "converts lowercase"
        assert_output "HELLO" str_upper "hello"

        test_that "handles empty string"
        assert_output "" str_upper ""
    end_describe

    describe "trim"
        test_that "removes whitespace"
        assert_output "hi" str_trim "  hi  "
    end_describe
end_describe
```

Failure output includes the full path:

```
FAIL [string utils > upper > converts lowercase]
  expected: 'HELLO'
  actual:   'hello'
```

> **What describe does and doesn't do:** `describe` is purely organizational — it prefixes test names for better output. It does not create variable isolation (no subshells). If you need isolated state per section, use `ptyunit_setup`/`ptyunit_teardown`.

### Set up and tear down per test

Define `ptyunit_setup` and `ptyunit_teardown` in your test file. They run automatically before and after each `test_that` section.

```bash
source tests/ptyunit/assert.sh

_tmpdir=""
ptyunit_setup()    { _tmpdir=$(mktemp -d); }
ptyunit_teardown() { rm -rf "$_tmpdir"; }

test_that "creates config file"
my_init "$_tmpdir"
assert_file_exists "$_tmpdir/config.ini"

test_that "starts with empty log"
my_init "$_tmpdir"
assert_true test -f "$_tmpdir/app.log"
result=$(cat "$_tmpdir/app.log")
assert_null "$result"

ptyunit_test_summary
```

> **Lifecycle order:** At each `test_that` boundary: teardown previous section, clean up mocks, restore working directory, then run setup for the new section. At `ptyunit_test_summary`: teardown the final section.

### Skip tests conditionally

Skip the whole file:

```bash
[[ "$(uname)" == "Darwin" ]] || ptyunit_skip "macOS only"
ptyunit_require_bash 4 3   # skip if bash < 4.3
```

Skip one section:

```bash
test_that "feature X (linux only)"
[[ "$(uname)" == "Linux" ]] || { ptyunit_skip_test "linux only"; }

assert_true check_cgroups   # silently skipped
```

> **How it works:** `ptyunit_skip` exits the whole file with code 3 (the runner shows it as SKIP). `ptyunit_skip_test` sets a flag that makes assertions silently pass-through until the next `test_that`.

---

## Running tests

```bash
bash tests/ptyunit/run.sh                          # everything
bash tests/ptyunit/run.sh --unit                   # unit tests only
bash tests/ptyunit/run.sh --filter auth            # only files matching "auth"
bash tests/ptyunit/run.sh --name "login"           # only test sections matching "login"
bash tests/ptyunit/run.sh --fail-fast              # stop on first failure
bash tests/ptyunit/run.sh --format tap             # TAP output for CI
bash tests/ptyunit/run.sh --format junit           # JUnit XML for CI
bash tests/ptyunit/run.sh --debug                  # sequential + verbose
```

Sample output:

```
ptyunit test runner (4 workers)

Unit tests:
  test-auth.sh    ... OK (12/12)
  test-config.sh  ... OK (8/8)
  test-deploy.sh  ... FAIL
    FAIL [deploy > push] — unexpected branch
      expected: 'staging'
      actual:   'main'
  test-utils.sh   ... OK (15/15) in 1.2 secs

─────────────────────────────────
35/36 assertions passed across 4 file(s)
Failed files:
  test-deploy.sh
```

### Runner options

| Flag | What it does |
|------|--------------|
| `--unit` | Unit tests only (`tests/unit/test-*.sh`) |
| `--integration` | Integration tests only (`tests/integration/test-*.sh`) |
| `--all` | Both (default) |
| `--jobs N` | Max parallel test files (default: number of CPU cores) |
| `--filter PATTERN` | Only run files whose name contains PATTERN |
| `--name PATTERN` | Only run test sections whose name contains PATTERN |
| `--fail-fast` | Stop after the first failure |
| `--format pretty` | Human-readable output (default) |
| `--format tap` | TAP version 13 — for CI tools that speak TAP |
| `--format junit` | JUnit XML — for Jenkins, GitHub Actions, etc. |
| `--debug` | Same as `--jobs 1 --verbose` — runs tests one by one |
| `-v` / `--verbose` | Show timing for every file |

> **How parallelism works:** Tests run in a streaming worker pool using an fd-based semaphore. This is compatible with bash 3.2 — no `wait -n` or GNU `parallel` required. Files start as soon as a slot opens rather than waiting for all files to be discovered first.

### File-level setUp / tearDown

Place `setUp.sh` and/or `tearDown.sh` alongside your `test-*.sh` files:

```
tests/unit/
  setUp.sh         # runs before each test-*.sh
  tearDown.sh      # runs after each test-*.sh (even on failure)
  test-foo.sh
  test-bar.sh
```

Both receive `$PTYUNIT_TEST_TMPDIR` — a temporary directory created and cleaned up by the runner.

> **If setUp fails** (non-zero exit), that test file is skipped and shown as SKIP in the output.

### Color

Green OK, yellow SKIP, red FAIL — automatically when stdout is a terminal.

| Variable | Effect |
|----------|--------|
| `NO_COLOR=1` | Turn off all color |
| `FORCE_COLOR=1` | Force color even in CI (non-TTY) |

---

## Assertions

All assertions accept an optional trailing message: `assert_eq "a" "b" "should match"`.

### Equality

```bash
assert_eq "expected" "$actual"          # strings must be equal
assert_not_eq "wrong" "$actual"         # strings must differ
```

### Substrings

```bash
assert_contains "$text" "needle"        # text must include needle
assert_not_contains "$text" "secret"    # text must NOT include secret
```

### Patterns

```bash
assert_match "^v[0-9]+\.[0-9]+" "$version"   # regex must match
```

### Commands

```bash
assert_output "Hello" greet "world"     # stdout of greet("world") must equal "Hello"
assert_true  test -f "$config"          # command must exit 0
assert_false test -d "$nonexistent"     # command must exit non-zero
```

### Values

```bash
assert_null "$result"                   # must be empty string
assert_not_null "$result"               # must be non-empty
```

### Files

```bash
assert_file_exists "$path"              # regular file must exist
```

### Lines

```bash
output=$'line1\nline2\nline3'
assert_line "line2" 2 "$output"         # 2nd line must equal "line2"
```

> **Lines are 1-indexed**, matching `sed`, `awk`, and human intuition.

### Numbers

```bash
assert_gt "$count" 5                    # count > 5
assert_lt "$count" 100                  # count < 100
assert_ge "$count" 1                    # count >= 1
assert_le "$count" 99                   # count <= 99
```

> **These are integer comparisons** using bash arithmetic. They don't handle floats.

### Mocks

```bash
assert_called "curl"                    # curl was called at least once
assert_not_called "docker"              # docker was never called
assert_called_times "curl" 3            # curl was called exactly 3 times
assert_called_with "curl" "-s" "url"    # last curl call had these args
```

Use `mock_args <name> [N]` and `mock_call_count <name>` for custom checks.

---

## PTY driver

```bash
python3 pty_run.py <script> [KEY ...]
```

Runs `bash <script>` inside a real pseudoterminal, sends each KEY as a keystroke, and prints ANSI-stripped text to stdout.

### Keys

`UP` `DOWN` `LEFT` `RIGHT` `ENTER` `SPACE` `ESC` `TAB` `SHIFT_TAB` `BACKSPACE` `DELETE` `HOME` `END` `PAGE_UP` `PAGE_DOWN`

Single characters (`a`, `q`, `1`) and hex escapes (`\x1b`) also work.

### Tuning

| Variable | Default | What it controls |
|----------|---------|-----------------|
| `PTY_COLS` | 80 | Terminal width |
| `PTY_ROWS` | 24 | Terminal height |
| `PTY_DELAY` | 0.15 | Seconds between keystrokes |
| `PTY_INIT` | 0.30 | Seconds before first keystroke (let the UI render) |
| `PTY_TIMEOUT` | 10 | Max seconds to wait for the script to exit |

> **Exit codes:** The script's own exit code is returned. 124 means timeout (matching GNU `timeout`).

### Python API

```python
from pty_run import run
output, exit_code = run("my_menu.sh", ["DOWN", "ENTER"], key_delay=0.1)
```

---

## Code coverage

```bash
bash tests/ptyunit/coverage.sh --unit --src=src
```

Measures which lines of your source code actually ran during tests.

```
────────────────────────────────────────────────────────────
File                        Lines    Hit   Miss    Cov
────────────────────────────────────────────────────────────
auth.sh                        85     72     13    85%
config.sh                      64     64      0   100%
deploy.sh                     120     45     75    38%
────────────────────────────────────────────────────────────
TOTAL                         269    181     88    67%
────────────────────────────────────────────────────────────
```

| Flag | What it does |
|------|--------------|
| `--src=<dir>` | Which directory to measure (default: `src/` or `.`) |
| `--report=text` | Table to stdout (default) |
| `--report=json` | JSON to stdout |
| `--report=html` | Browsable HTML report at `coverage/index.html` |
| `--min=N` | Fail if coverage is below N% (for CI gates) |

> **How it works:** Each test file runs with `set -x` and a custom `PS4` that logs `file:line` to a trace file. A Python script then cross-references the trace against your source files. Works on bash 3.2 — no special tools needed.

---

## Docker cross-version matrix

```bash
bash docker/run-matrix.sh [--no-cache]
```

Runs your full test suite on bash 3.2, 4.4, and 5.x in Alpine containers. Tests that call `ptyunit_require_bash` skip automatically in containers where bash is too old.

> **Why this matters:** bash 3.2 ships on macOS. If you write `declare -A` (associative arrays, bash 4+), your script breaks for every Mac user who hasn't installed a newer bash. The matrix catches this before they do.

---

## Project layout

```
your-project/
  src/
    mylib.sh
  tests/
    ptyunit/           # git submodule
    unit/
      test-mylib.sh
    integration/
      test-myui.sh
```

---

## Compatibility

| | Supported |
|---|---|
| **Bash** | 3.2, 4.x, 5.x |
| **Python** | 3.6+ (for PTY driver and coverage reports) |
| **OS** | Linux, macOS |
| **Dependencies** | None |

---

## License

MIT
