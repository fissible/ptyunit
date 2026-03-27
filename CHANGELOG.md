# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
## [1.5.2] - 2026-03-27

### Added
- Replace fixed-delay waiting with output-stable waiting (#32)
- BASH_ENV coverage injection in PTYSession.__enter__ (#34)
- Auto-export PTYUNIT_HOME; warn on --unit (#33 #35)
- Warn on stderr when --unit skips integration tests

### Fixed
- Three correctness bugs in assert.sh
- NUL-delimited arg recording in assert_called_with (#24)
- OSError guard in send(), stability clock after first byte, Python 3.9+ note (#26 #27 #23)
- EXIT trap for temp dir cleanup, mkfifo guard, fail-fast between suites (#29 #30 #31)
## [1.5.1] - 2026-03-26

### Fixed
- Thinner nav scrollbar, active item auto-scroll, subtle active style
- Match main page scrollbar style to nav scrollbar
- Case branch labels inherit hit status from first body line
- _run_py_suite filter + bash 3.2 empty array + CI pytest install
## [1.5.0] - 2026-03-26

### Added
- Add Screen wrapper with unit tests
- Add PTYSession core — fork, pyte stream, wait_for_stable
- Add send() with post-keystroke exit_code detection
- Discover and run test_*.py files via pytest (#21)
- Add help.sh skeleton with registry, index, dispatch, and detect
- Add coverage topic with install detection and color annotation
- Add pty, mocking, params, describe topics
- Add setup-teardown, filters, formats, install topics
- Add skip, matrix topics and registry sync test
- Wire help subcommand into run.sh _main and _usage

### Fixed
- Cleanup child process if wait_for_stable raises in __enter__
- Block on waitpid when EOF detected to catch imminent child exit
- Use return 1 in _dispatch when sourced; use pwd -P in test
- Correct %% escaping in coverage flags; tighten --min= assertion
- Explicitly state label inheritance in _help_describe output
- Correct setUp/tearDown scoping claim and section-vs-file language
## [1.4.0] - 2026-03-25

### Added
- Instrument PTY child process for PS4 trace collection

### Fixed
- Use sed for _xml_escape to avoid bash ${//} backreference regression (#19)
## [1.3.0] - 2026-03-25

### Added
- Add .coverageignore support to exclude untestable files
- Add @pty_skip pragma for structurally untestable branches
- Heredoc detection in count_source_lines; mock.sh at 100%

### Fixed
- Use BASH_XTRACEFD to prevent PS4 trace leaking into run() output
- Sync package.json version to 1.2.0; update release.sh to keep it in sync
- Prefer VERSION file over package.json for app version detection
- Anchor N/N pattern to summary line; read VERSION for --version
## [1.2.0] - 2026-03-24

### Added
- Add _main() guard so run.sh can be sourced for unit testing
- V2 HTML report with folder hierarchy, sort, deltas, complexity, and languages bar

### Fixed
- Use 24-hour time in coverage report nav labels
- Restore 12-hour am/pm display in nav labels
- Sync package.json version to 1.1.1 (was stale at 1.0.0)
- Handle DCS/SOS/PM/APC sequences in ANSI stripper
- Address UI feedback on v2 HTML report
- Suppress redundant ptyunit attribution when measuring ptyunit itself; sync package.json to 1.1.1
- Color-coded percentages, skip test files in source scan, delta display polish
## [1.1.1] - 2026-03-23

### Fixed
- Escape %% in --min help string for Python 3.14 argparse
## [1.1.0] - 2026-03-23

### Added
- Add Worker role CLAUDE.md

### Fixed
- Add permissions: contents: write to release workflow caller
- Skip function declaration lines; add version + file links to HTML report
## [1.0.0] - 2026-03-21

