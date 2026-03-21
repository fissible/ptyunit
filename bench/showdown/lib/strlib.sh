#!/usr/bin/env bash
# strlib.sh — String utilities
# Exercises: assert_contains, assert_not_contains, assert_match, assert_line,
#            assert_null, assert_not_null, assert_eq, assert_not_eq

str_upper()     { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
str_lower()     { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
str_trim()      { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
str_len()       { printf '%d' "${#1}"; }
str_repeat()    { local s="" i; for (( i=0; i<$2; i++ )); do s+="$1"; done; printf '%s' "$s"; }
str_reverse()   { local s="$1" r="" i; for (( i=${#s}-1; i>=0; i-- )); do r+="${s:$i:1}"; done; printf '%s' "$r"; }
str_contains()  { [[ "$1" == *"$2"* ]]; }
str_starts_with() { [[ "$1" == "$2"* ]]; }
str_ends_with() { [[ "$1" == *"$2" ]]; }
str_is_empty()  { [[ -z "$1" ]]; }
str_replace()   { printf '%s' "${1//$2/$3}"; }
str_count_lines() { local n=0; while IFS= read -r _; do (( n++ )); done <<< "$1"; printf '%d' "$n"; }
str_get_line()  {
    local text="$1" n="$2" i=0
    while IFS= read -r line; do
        (( i++ ))
        (( i == n )) && { printf '%s' "$line"; return 0; }
    done <<< "$text"
    return 1
}
str_join()      {
    local sep="$1"; shift
    local result=""
    local first=1
    for item in "$@"; do
        (( first )) && { result="$item"; first=0; continue; }
        result+="${sep}${item}"
    done
    printf '%s' "$result"
}
str_split_first() { printf '%s' "${1%%"$2"*}"; }
str_split_last()  { printf '%s' "${1##*"$2"}"; }
# Returns a multi-line word list (one word per line)
str_words() { printf '%s\n' $1; }
