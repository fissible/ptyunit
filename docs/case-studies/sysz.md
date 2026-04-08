# Case Study: fzf-based systemctl TUI

**Tool evaluated:** An open-source fzf-based interactive frontend for systemctl — browse, filter, and manage systemd units (services, timers, sockets) with fuzzy search, multi-selection, state-aware command suggestions, and automatic sudo elevation. ~575 lines, no existing tests.

---

## What ptyunit found

Claude Code evaluated the tool against ptyunit. Six bugs were identified. Four were surfaced through
ptyunit-driven tests; one was found by code review and disclosed privately; one is a minor
documentation gap.

### How this tool differs from a typical TUI target

Unlike tools with a self-contained TUI (custom `read -n1` key loops, direct terminal rendering),
this tool delegates its interactive interface entirely to fzf. The script's own logic is in the bash
plumbing around fzf: argument parsing, function dispatch, unit sorting, and systemctl orchestration.

This makes **mocking** the primary ptyunit value here rather than PTY keystroke testing. The tool can't
be tested without faking `fzf` and `systemctl`, and ptyunit's mock system handles both cleanly.

---

## Bugs ptyunit is relevant for

### Bug 1 — `r` documented as restart alias but code handles `re`

**Severity:** Medium (broken user-facing feature)

The help text says:
```
  r, restart             systemctl restart <unit>
```

But the case statement only handles `re`:
```bash
re)
  CMD=restart
  ;;
```

Running with `r` as the command falls through to the `*` catch-all and sets `CMD=r`, which systemctl doesn't recognize.

**ptyunit test:**
```bash
test_that "'r' alias for restart is broken (documented but not handled)"
run "$SYSZ" r
# Falls through to catch-all — CMD becomes literal "r"
assert_eq "1" "$status"
```

---

### Bug 2 — Error redirect is backwards on unknown option

**Severity:** Low (error goes to wrong stream)

```bash
echo "ERROR: Unknown option: $1" 2>&1
```

`2>&1` redirects stderr to stdout — the opposite of the intended `>&2`. Every other error in the
script uses `>&2` correctly. The error message goes to stdout, so piping output would swallow the error silently.

**ptyunit test:**
```bash
test_that "unknown option error goes to stdout (bug: should be stderr)"
stdout=$(bash "$SYSZ" --bogus 2>/dev/null) || true
stderr=$(bash "$SYSZ" --bogus 2>&1 1>/dev/null) || true

assert_contains "$stdout" "Unknown option"
assert_null "$stderr" "error message should be on stderr but isn't"
```

---

### Bug 3 — `j` and `f` command aliases are undocumented

**Severity:** Low (hidden feature)

```bash
j)
  CMD=journal
  ;;
f)
  CMD=follow
  ;;
```

Both work but don't appear in `--help`. Either they should be documented or they were left in
by accident.

**ptyunit test:**
```bash
test_that "'j' alias for journal is accepted but undocumented"
run "$SYSZ" j
assert_eq "1" "$status"   # fzf mock exits 1 (no selection)

test_that "help text does not mention 'j' alias"
run "$SYSZ" --help
assert_not_contains "$output" "  j "
```

---

### Bug 4 — State validation uses regex instead of literal match

**Severity:** Low (edge case in input validation)

```bash
! systemctl --state=help | grep -q "^${STATE}$"
```

`$STATE` is treated as a regex pattern. `--state=a.` would match `ab`, `ac`, etc. and pass
validation. Should be `grep -qxF "$STATE"` for a literal whole-line match.

**ptyunit test (with mock):**
```bash
test_that "state validation rejects regex metacharacters"
ptyunit_mock systemctl << 'MOCK'
if [[ "$1" == "--state=help" ]]; then
    printf 'active\ninactive\nfailed\n'
    exit 0
fi
MOCK
run "$SYSZ" -s "a."
assert_not_eq "0" "$status"
```

---

## Bugs outside ptyunit's scope

### Security: `eval "$@"` in command runner

*Disclosed privately to the author. Not included in the PR or public test suite.*

This is a code-review-only finding. The fix is straightforward and was communicated directly.

---

## What the mocking approach looks like

Since the tool requires both fzf and systemctl, every test mocks them:

```bash
ptyunit_setup() {
    ptyunit_mock fzf --exit 1          # "no selection" — prevents blocking
    ptyunit_mock systemctl --output ""  # stub systemctl calls
}
```

This lets the test suite run on any machine (including macOS, CI runners without systemd) and
exercise the tool's bash logic in isolation.

---

## Summary

| Bug | ptyunit relevant? | How found |
|-----|-------------------|-----------|
| `r` alias broken (code handles `re`) | Yes | CLI assertion with mock |
| Error redirect backwards (`2>&1` vs `>&2`) | Yes | Stderr capture test |
| `j`/`f` aliases undocumented | Yes | Help output assertion |
| State validation uses regex not literal | Yes | Mock + assertion |
| `eval "$@"` command injection | No | Code review (disclosed privately) |

The key ptyunit differentiator for this class of tool: **mocking external dependencies** (fzf,
systemctl, sudo) so the bash logic can be tested anywhere. Without mocking, the tool is untestable
outside a live systemd environment. The mock system is what makes the test suite portable and
useful in CI.
