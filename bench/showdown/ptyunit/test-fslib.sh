#!/usr/bin/env bash
set -u
SHOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$SHOW_DIR/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$SHOW_DIR/lib/fslib.sh"

# ── Per-test setup/teardown: create and clean a temp workspace ───────────────
_ws=""
ptyunit_setup() {
    _ws=$(fs_tmpdir)
}
ptyunit_teardown() {
    [[ -n "$_ws" ]] && rm -rf "$_ws"
}

# ── File creation (assert_file_exists, assert_true, assert_false) ────────────

test_that "ensure_file creates a file"
fs_ensure_file "$_ws/sub/dir/test.txt"
assert_file_exists "$_ws/sub/dir/test.txt"

test_that "ensure_dir creates directories"
fs_ensure_dir "$_ws/a/b/c"
assert_true fs_is_dir "$_ws/a/b/c"

test_that "is_file rejects directory"
fs_ensure_dir "$_ws/mydir"
assert_false fs_is_file "$_ws/mydir"

test_that "is_file accepts file"
fs_ensure_file "$_ws/myfile"
assert_true fs_is_file "$_ws/myfile"

# ── Read/write (assert_eq, assert_output) ───────────────────────────────────

test_that "write then read round-trips"
fs_write "$_ws/data.txt" "hello world"
assert_output "hello world" fs_read "$_ws/data.txt"

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
assert_true fs_is_empty "$_ws/empty.txt"

test_that "is_empty: written file is not empty"
fs_write "$_ws/content.txt" "data"
assert_false fs_is_empty "$_ws/content.txt"

test_that "is_readable for normal file"
fs_ensure_file "$_ws/readable.txt"
assert_true fs_is_readable "$_ws/readable.txt"

# ── Path operations (assert_eq) ─────────────────────────────────────────────

test_that "ext extracts file extension"
assert_output "sh" fs_ext "script.sh"

test_that "ext handles no extension"
result=$(fs_ext "Makefile")
assert_null "$result"

test_that "ext handles double extension"
assert_output "gz" fs_ext "archive.tar.gz"

test_that "basename extracts filename"
assert_output "file.txt" fs_basename "/path/to/file.txt"

test_that "dirname extracts directory"
assert_output "/path/to" fs_dirname "/path/to/file.txt"

test_that "dirname of bare filename returns dot"
assert_output "." fs_dirname "file.txt"

# ── Line count ───────────────────────────────────────────────────────────────

test_that "line_count counts lines in file"
printf 'a\nb\nc\n' > "$_ws/lines.txt"
assert_output "3" fs_line_count "$_ws/lines.txt"

# ── find_ext (assert_contains, assert_line) ──────────────────────────────────

test_that "find_ext discovers matching files"
fs_write "$_ws/a.sh" "#!/bin/bash"
fs_write "$_ws/b.sh" "#!/bin/bash"
fs_write "$_ws/c.txt" "text"
result=$(fs_find_ext "$_ws" "sh")
assert_contains "$result" "a.sh"
assert_contains "$result" "b.sh"
assert_not_contains "$result" "c.txt"

# ── PWD isolation: cd in one test doesn't affect the next ────────────────────

test_that "PWD isolation: cd to workspace"
cd "$_ws"
assert_eq "$_ws" "$PWD"

test_it "next test has restored PWD"
# PWD should be back to original, not _ws
assert_not_eq "$_ws" "$PWD"

# ── Numeric assertions on file sizes ─────────────────────────────────────────

test_that "line_count with numeric assertions"
printf 'line1\nline2\nline3\nline4\nline5\n' > "$_ws/five.txt"
count=$(fs_line_count "$_ws/five.txt")
assert_gt "$count" 3
assert_lt "$count" 10
assert_ge "$count" 5
assert_le "$count" 5

ptyunit_test_summary
