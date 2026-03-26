# ptyunit

[![tests](https://github.com/fissible/ptyunit/actions/workflows/test.yml/badge.svg)](https://github.com/fissible/ptyunit/actions/workflows/test.yml)

Test your bash scripts. Even the interactive ones that take over the terminal.

```bash
source tests/ptyunit/assert.sh

test_that "math still works"
assert_eq "4" "$(( 2 + 2 ))"

greet() {
  echo "Hello, $1"
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
# Git submodule (recommended for projects)
git submodule add https://github.com/fissible/ptyunit tests/ptyunit

# Homebrew
brew tap fissible/tap && brew install ptyunit

# bpkg
bpkg install fissible/ptyunit
```

That's it. One file to source (`assert.sh`), one runner to call (`run.sh`), zero build steps.

> **Other install options:** You can also `curl` the individual files or copy the directory directly. There are no compiled artifacts. The Homebrew formula installs a `ptyunit` command in your PATH that wraps `run.sh`.

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
deploy_to_staging() {
    git push origin staging || { echo "deploy failed"; return 1; }
    curl -s https://hooks.example.com/deployed
}

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
str_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }
str_trim()  { echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

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

> **Describe is also a scope.** Pass optional setup/teardown functions:
> `describe "name" setup_fn teardown_fn`. Nested describes accumulate — inner
> tests get all outer setups (outermost first) and all teardowns (innermost first).
> See "Set up and tear down" below.

### Set up and tear down per test

Define `ptyunit_setup` and `ptyunit_teardown` in your test file. They run automatically before and after each `test_that` section.

```bash
source tests/ptyunit/assert.sh

my_init() {
    mkdir -p "$1"
    touch "$1/config.ini"
    touch "$1/app.log"
}

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

### Capture a command's output in one line

Instead of manually juggling `$()` and `$?`:

```bash
deploy_to_staging() { echo "deployed to staging"; }

test_that "deploy succeeds"
run deploy_to_staging
assert_eq "0" "$status"
assert_contains "$output" "deployed"
assert_eq "deployed to staging" "${lines[0]}"
```

`run` captures everything at once: `$output` (stdout+stderr), `$status` (exit code), and `$lines` (array, one element per line).

> **Why this helps:** Without `run`, you'd write `out=$(cmd 2>&1); rc=$?` and manually split lines. With `run`, it's one call. The `$lines` array lets you check specific lines by index: `${lines[0]}` is the first line, `${lines[1]}` the second, etc.

### Write your own assertions

If the built-in assertions don't cover your case, make your own using `ptyunit_pass` and `ptyunit_fail`:

```bash
assert_valid_json() {
    if echo "$1" | python3 -m json.tool > /dev/null 2>&1; then
        ptyunit_pass
    else
        ptyunit_fail "expected valid JSON, got: $1"
    fi
}

my_api_call() { echo '{"status": "ok"}'; }

test_that "API returns JSON"
run my_api_call
assert_valid_json "$output"
```

These integrate with ptyunit's counters, skip flag, and failure reporting — your custom assertion behaves exactly like a built-in one.

> **How it works:** `ptyunit_pass` increments the pass counter. `ptyunit_fail "message"` increments the fail counter and prints a formatted FAIL line with the current test name. Both respect `ptyunit_skip_test`.

### Scoped setup with describe

Describe blocks can carry their own setup and teardown functions. Nesting accumulates — inner tests get all outer setups.

```bash
_start_db()  { db_connect "test.db"; }
_stop_db()   { db_disconnect; }
_seed_users(){ db_exec "INSERT INTO users VALUES ('alice')"; }

describe "database" _start_db _stop_db
    describe "users" _seed_users
        test_that "finds alice"
        run db_query "SELECT name FROM users"
        assert_contains "$output" "alice"
    end_describe
end_describe
# _start_db ran before the test, then _seed_users.
# After the test: _stop_db ran.
```

> **Setup order:** outermost first, then innermost. **Teardown order:** innermost first, then outermost (like stack unwinding). Describe-level setups run before each `test_that` inside the block — not once for the whole block.

---

## Help

Every feature has a built-in reference page:

```bash
ptyunit help              # list all topics
ptyunit help coverage     # coverage flags and install-method examples
ptyunit help pty          # PTY/TUI testing
ptyunit help mocking      # mock commands and functions
ptyunit help params       # parameterised tests
ptyunit help filters      # run a subset by file or name
ptyunit help formats      # TAP, JUnit XML, pretty output
ptyunit help install      # submodule vs brew vs bpkg tradeoffs
```

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
| `--unit` | Unit tests only (`test-*.sh` + `test_*.py`) |
| `--integration` | Integration tests only (`test-*.sh` + `test_*.py`) |
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
| `--version` | Print version and exit |

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
| `--report=html` | Timestamped HTML report in `coverage/`; `coverage/index.html` is a scrollable nav that links all runs |
| `--min=N` | Fail if coverage is below N% (for CI gates) |

**PTY integration tests contribute to coverage automatically.** When `coverage.sh` runs your integration tests, it sets `PTYUNIT_COVERAGE_FILE` in the environment. Any test that calls `pty_run.py` will instrument the child bash process and trace its execution to the same coverage file — so TUI scripts exercised by PTY tests appear in the coverage report with no extra configuration. This requires bash 4.1+ in the child (for `BASH_XTRACEFD`).

To exclude files or directories from measurement (e.g. release scripts), create a `.coverageignore` file at your project root:

```
# .coverageignore — one glob pattern per line
release.sh
scripts/
examples/
```

To exclude specific lines or blocks that are structurally untestable (e.g. error handlers that require infrastructure failure, or assertion failure branches only reachable via subshells), annotate with `# @pty_skip`:

```bash
# Single-line skip (inline on a code line):
mkdir -p "$dir" || return 1  # @pty_skip

# Block skip (standalone comment — skips until the next block-closer at
# the same or lower indent: fi / done / esac / } / ) / ;;):
if (( count == 0 )); then
    # @pty_skip — only reachable when assertion fails; tested via subshells
    printf 'FAIL\n'
    ...
fi
```

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

## How does it compare?

| Capability | ptyunit | [bats-core](https://github.com/bats-core/bats-core) | [shellspec](https://github.com/shellspec/shellspec) | [shunit2](https://github.com/kward/shunit2) |
|---|---|---|---|---|
| PTY / TUI testing | **Yes** | No | No | No |
| Built-in mocking | **Yes** | No (external) | No | No |
| Parameterized tests | **Yes** (`test_each`) | No | Yes | No |
| Nestable describe | **Yes** | No | Yes | No |
| Parallel execution | Yes | Yes (GNU parallel) | Yes | No |
| Code coverage | Yes (built-in PS4) | No (kcov only) | No (kcov only) | No |
| TAP output | Yes | Yes | Yes | No |
| JUnit XML | Yes | Yes | Yes | No |
| Test name filter | Yes (`--name`) | Yes | Yes | Yes |
| Fail-fast | Yes | Yes | Yes | No |
| Numeric assertions | Yes (`assert_gt/lt/ge/le`) | Manual | Matchers | No |
| macOS coverage | **Yes** | No (kcov is Linux-only) | No | No |
| Zero dependencies | **Yes** | No | No | No |

**Speed:** ptyunit is ~15x faster than bats-core on equivalent test suites. See [`bench/showdown/`](bench/showdown/) for the methodology and raw numbers.

The main differentiator is PTY testing — if your scripts render to `/dev/tty` (menus, prompts, progress bars), no other framework listed here can test them. For pure unit testing of bash functions, all four are reasonable choices; ptyunit's advantages are speed, built-in mocking, and working coverage on macOS without external tools.

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
