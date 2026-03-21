# Changelog

All notable changes to ptyunit are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-21

First public release.

### Core

- **assert.sh** — 22 assertion functions with skip guard, per-test lifecycle, and
  custom matcher support (`ptyunit_pass`/`ptyunit_fail`)
- **mock.sh** — command and function mocking with auto-cleanup, call recording,
  heredoc bodies, and 5 verification assertions
- **run.sh** — parallel test runner with streaming worker pool, TAP/JUnit/pretty
  output, `--filter`, `--name`, `--fail-fast`, `--help`, `--version`
- **pty_run.py** — PTY driver for testing interactive terminal programs
- **coverage.sh** — line-level code coverage via PS4 trace with text/json/html reports

### Assertions

`assert_eq`, `assert_not_eq`, `assert_output`, `assert_contains`,
`assert_not_contains`, `assert_true`, `assert_false`, `assert_null`,
`assert_not_null`, `assert_match`, `assert_file_exists`, `assert_line`,
`assert_gt`, `assert_lt`, `assert_ge`, `assert_le`, `assert_called`,
`assert_not_called`, `assert_called_times`, `assert_called_with`

### Test Organization

- `test_that` / `test_it` / `test_they` — readable aliases for test sections
- `describe` / `end_describe` — nestable scope with optional setup/teardown functions
- `test_each` — parameterized tests via pipe-delimited heredoc
- `ptyunit_skip` — skip entire file; `ptyunit_skip_test` — skip one section
- `ptyunit_require_bash MAJOR [MINOR]` — version gating
- `ptyunit_setup` / `ptyunit_teardown` — per-test lifecycle hooks
- `run` — capture stdout+stderr, exit code, and lines array in one call

### Runner Features

- Streaming worker pool (bash 3.2 compatible, no GNU parallel)
- `--format tap` (TAP version 13) and `--format junit` (JUnit XML)
- `--filter PATTERN` (filename) and `--name PATTERN` (test section name)
- `--fail-fast`, `--debug`, `--verbose`
- File-level `setUp.sh` / `tearDown.sh` with `$PTYUNIT_TEST_TMPDIR`
- Color output (auto-detect TTY, `NO_COLOR`, `FORCE_COLOR`)

### Mocking

- `ptyunit_mock <name> [--output STR] [--exit N]` — auto-detects function vs command
- Heredoc bodies for conditional mock behavior
- `assert_called`, `assert_not_called`, `assert_called_times`, `assert_called_with`
- `mock_args`, `mock_call_count` query helpers
- Auto-cleanup at `test_that` boundaries

### Compatibility

- Bash 3.2, 4.x, 5.x
- Python 3.6+ (for PTY driver and coverage reports)
- macOS and Linux
- Docker cross-version matrix (bash 3.2, 4.4, 5.x on Alpine)

[1.0.0]: https://github.com/fissible/ptyunit/releases/tag/v1.0.0
