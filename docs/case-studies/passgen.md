# Case Study: passgen

**Tool evaluated:** [passgen](https://github.com/flathead/passgen) by [@flathead](https://github.com/flathead)
*(If author approval is not obtained, anonymize: remove links, replace "passgen" with "a bash TUI password generator", remove GitHub handle)*

**Tool description:** A bash TUI password generator with interactive mode (arrow keys, vim bindings, preset hotkeys), CLI flag mode, i18n (EN/RU), password history, clipboard integration, and DB-safe mode for MySQL/MariaDB compatibility. ~1,060 lines, no existing tests.

---

## What ptyunit found

Claude Code evaluated passgen against ptyunit as a test case for assessing untested bash TUI tools.
Five bugs were identified. Three were found directly through ptyunit-driven analysis; two were found
by code review alone and are outside the scope of any test framework.

---

## Bugs ptyunit is relevant for

### Bug 1 — `shift 2` crash when `-l` flag has no value

**Severity:** High (crash)

With `set -euo pipefail` at the top of the script, passing `-l` without a value causes `shift 2` to
fail because only one positional parameter remains. The script exits with a cryptic shell error
instead of a user-facing message.

```bash
$ bash passgen -l
bash: shift: shift count out of range
```

**ptyunit test:**
```bash
test_that "-l without a value exits non-zero with a helpful message"
run passgen -l
assert_not_eq "0" "$status"
assert_contains "$output" "length"   # should explain the problem
```

---

### Bug 2 — `-d -s` flag ordering silently produces a wrong password

**Severity:** High (silent correctness bug)

The `-d` (DB-safe) flag sets `use_special=1` to include safe DB chars (`_.-`). The `-s` (simple/alphanumeric) flag sets `use_special=0`. Flag order determines the winner: `passgen -d -s` results in `db_safe=1, use_special=0` — the output is labeled "DB-safe" but contains no special characters, defeating the purpose.

```bash
$ passgen -d -s -l 24 -q
# Outputs: alphanumeric only, no _ . - characters
# Label still says: [DB-safe]
```

**ptyunit test:**
```bash
test_that "-d flag wins over -s regardless of order"
run passgen -d -s -l 24 -q
assert_match '[_.\-]' "$output"

run passgen -s -d -l 24 -q
assert_match '[_.\-]' "$output"
```

---

### Bug 5 — `HISTORY[-1]` requires bash 4.3+

**Severity:** Medium (crash on older bash)

```bash
if [[ ${#HISTORY[@]} -eq 0 ]] || [[ "${HISTORY[-1]}" != "$PASSWORD" ]]; then
```

Negative array indices were added in bash 4.3. The script's `declare -A` already requires bash 4+,
but bash 4.0–4.2 would fail here with a cryptic subscript error rather than a clear compatibility
message. This manifests during interactive use after the first password is generated.

**ptyunit test (PTY):**
```bash
test_that "generates a password in interactive mode without crashing"
out=$(python3 pty_run.py passgen r q)
assert_contains "$out" "Password"
# Catches the HISTORY[-1] crash on bash < 4.3
```

---

### PTY-only tests (interactive TUI behavior)

These behaviors are invisible to any non-PTY test framework:

```bash
test_that "r key regenerates password"
out=$(python3 pty_run.py passgen r q)
assert_contains "$out" "Password"

test_that "+ key increases length by 4"
out=$(python3 pty_run.py passgen + + q)
assert_contains "$out" "32"   # default 24 + 4 + 4

test_that "R key enables DB-safe mode"
out=$(python3 pty_run.py passgen R q)
assert_contains "$out" "DB-safe"

test_that "history navigation shows correct position"
out=$(python3 pty_run.py passgen r r r '<' q)
assert_contains "$out" "2/3"

test_that "? key shows help screen"
out=$(python3 pty_run.py passgen '?' q)
assert_contains "$out" "Controls:"

test_that "language selection menu responds to arrow keys"
out=$(python3 pty_run.py passgen DOWN ENTER q)
assert_contains "$out" "Пароль"   # Russian label
```

---

## Bugs outside ptyunit's scope (code review only)

These were found by reading the source. No test framework can reliably catch them.

### Bug 3 — `grep -oP` not available on macOS default grep

`load_lang()` uses `grep -oP` (Perl regex) to read the saved language preference. BSD grep on
macOS doesn't support `-P`. The `2>/dev/null || echo ""` silently swallows the error, so the saved
language is lost on every startup on macOS. Requires a CI matrix (Linux + macOS) to surface, not
a test framework.

### Bug 4 — SIGPIPE under `set -o pipefail` in `random_chars`

```bash
tr -dc "$charset" < /dev/urandom 2>/dev/null | head -c "$count"
```

When `head` reads enough bytes and exits, it sends SIGPIPE to `tr`, which exits 141. Under
`set -o pipefail`, the pipeline exit status is 141, and `set -e` aborts the script. This is
nondeterministic and environment-dependent (varies by bash version and OS). Fix: add `|| true`
to the pipeline. No test can reliably reproduce the condition.

---

## Summary

| Bug | ptyunit relevant? | How found |
|-----|-------------------|-----------|
| `shift 2` crash on missing `-l` value | Yes | CLI assertion |
| `-d -s` flag ordering silent bug | Yes | CLI assertion |
| `grep -oP` macOS incompatibility | No | Code review |
| SIGPIPE under `pipefail` | No | Code review |
| `HISTORY[-1]` bash 4.3 requirement | Yes | PTY integration test |
| All interactive TUI behavior | Yes (only ptyunit can) | PTY keystroke sequences |

The key ptyunit differentiator for this class of tool: **any behavior in the interactive TUI loop
is completely untestable without PTY support.** That covers the majority of passgen's code path.
