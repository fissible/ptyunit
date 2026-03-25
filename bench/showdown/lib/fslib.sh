#!/usr/bin/env bash
# fslib.sh — File system utilities
# Exercises: assert_file_exists, assert_true/false, setup/teardown, PWD isolation

fs_ensure_dir()  { mkdir -p "$1" 2>/dev/null; }
fs_ensure_file() { local dir; dir="$(dirname "$1")"; mkdir -p "$dir" 2>/dev/null; touch "$1"; }
fs_is_file()     { [[ -f "$1" ]]; }
fs_is_dir()      { [[ -d "$1" ]]; }
fs_is_readable() { [[ -r "$1" ]]; }
fs_is_writable() { [[ -w "$1" ]]; }
fs_is_empty()    { [[ ! -s "$1" ]]; }
fs_ext()         { local name="${1##*/}"; [[ "$name" == *.* ]] && printf '%s' "${name##*.}" || printf ''; }
fs_basename()    { printf '%s' "${1##*/}"; }
fs_dirname()     { local d="${1%/*}"; [[ "$d" == "$1" ]] && printf '.' || printf '%s' "$d"; }
fs_line_count()  { local n=0; while IFS= read -r _; do (( n++ )); done < "$1"; printf '%d' "$n"; }
fs_write()       { printf '%s' "$2" > "$1"; }
fs_append()      { printf '%s' "$2" >> "$1"; }
fs_read()        { cat "$1" 2>/dev/null; }
fs_find_ext()    {
    local dir="$1" ext="$2"
    local f
    for f in "$dir"/*."$ext"; do
        [[ -f "$f" ]] && printf '%s\n' "${f##*/}"
    done
}
fs_tmpfile()     { local _b="${TMPDIR:-/tmp}"; mktemp "${_b%/}/fslib.XXXXXX"; }
fs_tmpdir()      { local _b="${TMPDIR:-/tmp}"; mktemp -d "${_b%/}/fslib.XXXXXX"; }
