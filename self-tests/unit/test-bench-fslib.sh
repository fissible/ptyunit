#!/usr/bin/env bash
# Note: assert_output/assert_true/assert_false suppress stderr (2>/dev/null),
# which swallows the PS4 trace. Call functions directly — result=$(...) traces
# the function body; direct predicate calls + $? check also trace correctly.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/bench/showdown/lib/fslib.sh"

# ── Per-test setup/teardown: create and clean a temp workspace ───────────────
_ws=""
ptyunit_setup() {
    _ws=$(fs_tmpdir)
}
ptyunit_teardown() {
    [[ -n "$_ws" ]] && rm -rf "$_ws"
}

# ── File and directory creation ──────────────────────────────────────────────

test_that "ensure_file creates a file"
fs_ensure_file "$_ws/sub/dir/test.txt"
assert_file_exists "$_ws/sub/dir/test.txt"

test_that "ensure_dir creates directories"
fs_ensure_dir "$_ws/a/b/c"
fs_is_dir "$_ws/a/b/c"
assert_eq "0" "$?"

test_that "is_file rejects directory"
fs_ensure_dir "$_ws/mydir"
fs_is_file "$_ws/mydir"
assert_not_eq "0" "$?"

test_that "is_file accepts file"
fs_ensure_file "$_ws/myfile"
fs_is_file "$_ws/myfile"
assert_eq "0" "$?"

test_that "is_dir rejects file"
fs_ensure_file "$_ws/notadir"
fs_is_dir "$_ws/notadir"
assert_not_eq "0" "$?"

# ── Read/write ───────────────────────────────────────────────────────────────

test_that "write then read round-trips"
fs_write "$_ws/data.txt" "hello world"
result=$(fs_read "$_ws/data.txt")
assert_eq "hello world" "$result"

test_that "append adds to file"
fs_write "$_ws/log.txt" "line1"
fs_append "$_ws/log.txt" "line2"
result=$(fs_read "$_ws/log.txt")
assert_eq "line1line2" "$result"

test_that "read of missing file returns empty"
result=$(fs_read "$_ws/nonexistent" 2>/dev/null)
assert_null "$result"

# ── File properties ──────────────────────────────────────────────────────────

test_that "is_empty: new file is empty"
fs_ensure_file "$_ws/empty.txt"
fs_is_empty "$_ws/empty.txt"
assert_eq "0" "$?"

test_that "is_empty: written file is not empty"
fs_write "$_ws/content.txt" "data"
fs_is_empty "$_ws/content.txt"
assert_not_eq "0" "$?"

test_that "is_readable for normal file"
fs_ensure_file "$_ws/readable.txt"
fs_is_readable "$_ws/readable.txt"
assert_eq "0" "$?"

test_that "is_writable for normal file"
fs_ensure_file "$_ws/writable.txt"
fs_is_writable "$_ws/writable.txt"
assert_eq "0" "$?"

# ── Path operations ──────────────────────────────────────────────────────────

test_that "ext extracts file extension"
result=$(fs_ext "script.sh")
assert_eq "sh" "$result"

test_that "ext handles no extension"
result=$(fs_ext "Makefile")
assert_null "$result"

test_that "ext handles double extension"
result=$(fs_ext "archive.tar.gz")
assert_eq "gz" "$result"

test_that "basename extracts filename"
result=$(fs_basename "/path/to/file.txt")
assert_eq "file.txt" "$result"

test_that "dirname extracts directory"
result=$(fs_dirname "/path/to/file.txt")
assert_eq "/path/to" "$result"

test_that "dirname of bare filename returns dot"
result=$(fs_dirname "file.txt")
assert_eq "." "$result"

# ── Line count ───────────────────────────────────────────────────────────────

test_that "line_count counts lines in file"
printf 'a\nb\nc\n' > "$_ws/lines.txt"
result=$(fs_line_count "$_ws/lines.txt")
assert_eq "3" "$result"

test_that "line_count with numeric assertions"
printf 'line1\nline2\nline3\nline4\nline5\n' > "$_ws/five.txt"
count=$(fs_line_count "$_ws/five.txt")
assert_gt "$count" 3
assert_lt "$count" 10
assert_ge "$count" 5
assert_le "$count" 5

# ── find_ext ─────────────────────────────────────────────────────────────────

test_that "find_ext discovers matching files"
fs_write "$_ws/a.sh" "#!/bin/bash"
fs_write "$_ws/b.sh" "#!/bin/bash"
fs_write "$_ws/c.txt" "text"
result=$(fs_find_ext "$_ws" "sh")
assert_contains "$result" "a.sh"
assert_contains "$result" "b.sh"
assert_not_contains "$result" "c.txt"

# ── Temp helpers ─────────────────────────────────────────────────────────────

test_that "tmpfile creates a file"
f=$(fs_tmpfile)
assert_file_exists "$f"
rm -f "$f"

test_that "tmpdir creates a directory"
d=$(fs_tmpdir)
fs_is_dir "$d"
assert_eq "0" "$?"
rm -rf "$d"

# ── PWD isolation ─────────────────────────────────────────────────────────────

test_that "PWD isolation: cd to workspace"
cd "$_ws"
assert_eq "$_ws" "$PWD"

test_it "next test has restored PWD"
assert_not_eq "$_ws" "$PWD"

ptyunit_test_summary
