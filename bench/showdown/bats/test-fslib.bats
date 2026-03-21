#!/usr/bin/env bats

SHOW_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
load "$SHOW_DIR/bats-libs/bats-support/load"
load "$SHOW_DIR/bats-libs/bats-assert/load"

setup() {
    source "$SHOW_DIR/lib/fslib.sh"
    _ws=$(fs_tmpdir)
}

teardown() {
    [[ -n "${_ws:-}" ]] && rm -rf "$_ws"
}

# ── File creation ────────────────────────────────────────────────────────────

@test "ensure_file creates a file" {
    fs_ensure_file "$_ws/sub/dir/test.txt"
    [ -f "$_ws/sub/dir/test.txt" ]
}

@test "ensure_dir creates directories" {
    fs_ensure_dir "$_ws/a/b/c"
    run fs_is_dir "$_ws/a/b/c"
    assert_success
}

@test "is_file rejects directory" {
    fs_ensure_dir "$_ws/mydir"
    run fs_is_file "$_ws/mydir"
    assert_failure
}

@test "is_file accepts file" {
    fs_ensure_file "$_ws/myfile"
    run fs_is_file "$_ws/myfile"
    assert_success
}

# ── Read/write ───────────────────────────────────────────────────────────────

@test "write then read round-trips" {
    fs_write "$_ws/data.txt" "hello world"
    run fs_read "$_ws/data.txt"
    assert_output "hello world"
}

@test "append adds to file" {
    fs_write "$_ws/log.txt" "line1"
    fs_append "$_ws/log.txt" "line2"
    run fs_read "$_ws/log.txt"
    assert_output "line1line2"
}

@test "read of missing file returns empty" {
    run fs_read "$_ws/nonexistent"
    assert_output ""
}

# ── File properties ──────────────────────────────────────────────────────────

@test "is_empty: new file is empty" {
    fs_ensure_file "$_ws/empty.txt"
    run fs_is_empty "$_ws/empty.txt"
    assert_success
}

@test "is_empty: written file is not empty" {
    fs_write "$_ws/content.txt" "data"
    run fs_is_empty "$_ws/content.txt"
    assert_failure
}

@test "is_readable for normal file" {
    fs_ensure_file "$_ws/readable.txt"
    run fs_is_readable "$_ws/readable.txt"
    assert_success
}

# ── Path operations ──────────────────────────────────────────────────────────

@test "ext extracts file extension" {
    run fs_ext "script.sh"
    assert_output "sh"
}

@test "ext handles no extension" {
    run fs_ext "Makefile"
    assert_output ""
}

@test "ext handles double extension" {
    run fs_ext "archive.tar.gz"
    assert_output "gz"
}

@test "basename extracts filename" {
    run fs_basename "/path/to/file.txt"
    assert_output "file.txt"
}

@test "dirname extracts directory" {
    run fs_dirname "/path/to/file.txt"
    assert_output "/path/to"
}

@test "dirname of bare filename returns dot" {
    run fs_dirname "file.txt"
    assert_output "."
}

# ── Line count ───────────────────────────────────────────────────────────────

@test "line_count counts lines in file" {
    printf 'a\nb\nc\n' > "$_ws/lines.txt"
    run fs_line_count "$_ws/lines.txt"
    assert_output "3"
}

# ── find_ext ─────────────────────────────────────────────────────────────────

@test "find_ext discovers matching files" {
    fs_write "$_ws/a.sh" "#!/bin/bash"
    fs_write "$_ws/b.sh" "#!/bin/bash"
    fs_write "$_ws/c.txt" "text"
    run fs_find_ext "$_ws" "sh"
    assert_output --partial "a.sh"
    assert_output --partial "b.sh"
    refute_output --partial "c.txt"
}

# ── PWD isolation (bats runs each @test in a subshell, so this is automatic) ─

@test "PWD isolation: cd to workspace" {
    cd "$_ws"
    [ "$PWD" = "$_ws" ]
}

@test "next test has restored PWD" {
    [ "$PWD" != "${_ws:-/nonexistent}" ]
}

# ── Numeric assertions on file sizes ─────────────────────────────────────────

@test "line_count with numeric assertions" {
    printf 'line1\nline2\nline3\nline4\nline5\n' > "$_ws/five.txt"
    run fs_line_count "$_ws/five.txt"
    [ "$output" -gt 3 ]
    [ "$output" -lt 10 ]
    [ "$output" -ge 5 ]
    [ "$output" -le 5 ]
}
