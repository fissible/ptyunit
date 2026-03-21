#!/usr/bin/env bash
set -u
SHOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$SHOW_DIR/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$SHOW_DIR/lib/strlib.sh"

# ── Case conversion (assert_eq, assert_output) ──────────────────────────────

test_that "upper converts to uppercase"
assert_output "HELLO WORLD" str_upper "hello world"

test_that "lower converts to lowercase"
assert_output "hello world" str_lower "HELLO WORLD"

test_that "upper is idempotent"
assert_eq "ABC" "$(str_upper "$(str_upper "abc")")"

# ── Trimming (assert_eq) ────────────────────────────────────────────────────

test_that "trim removes leading and trailing whitespace"
assert_output "hello" str_trim "  hello  "

test_that "trim handles tabs"
result=$(str_trim $'\t hello \t')
assert_eq "hello" "$result"

# ── Length and repeat ────────────────────────────────────────────────────────

test_that "len returns string length"
assert_output "5" str_len "hello"

test_that "len of empty string is 0"
assert_output "0" str_len ""

test_that "repeat builds repeated string"
assert_output "abcabcabc" str_repeat "abc" 3

test_that "repeat 0 returns empty"
result=$(str_repeat "abc" 0)
assert_null "$result"

# ── Reverse ──────────────────────────────────────────────────────────────────

test_that "reverse reverses a string"
assert_output "dcba" str_reverse "abcd"

test_that "reverse of palindrome is unchanged"
assert_output "racecar" str_reverse "racecar"

# ── Contains / starts / ends (assert_contains, assert_not_contains, assert_true/false) ─

test_that "contains finds substring"
assert_true str_contains "hello world" "world"

test_that "contains rejects missing substring"
assert_false str_contains "hello world" "xyz"

test_that "starts_with matches prefix"
assert_true str_starts_with "hello world" "hello"

test_that "ends_with matches suffix"
assert_true str_ends_with "hello world" "world"

test_that "starts_with rejects non-prefix"
assert_false str_starts_with "hello world" "world"

# ── Empty check (assert_null, assert_not_null) ──────────────────────────────

test_that "is_empty: empty string returns true"
assert_true str_is_empty ""

test_that "is_empty: non-empty string returns false"
assert_false str_is_empty "x"

test_that "not_null for non-empty result"
result=$(str_upper "hi")
assert_not_null "$result"

test_that "null for empty repeat"
result=$(str_repeat "x" 0)
assert_null "$result"

# ── Replace ──────────────────────────────────────────────────────────────────

test_that "replace substitutes all occurrences"
assert_output "hell- w-rld" str_replace "hello world" "o" "-"

test_that "replace with empty removes occurrences"
assert_output "hell wrld" str_replace "hello world" "o" ""

# ── Line operations (assert_line) ────────────────────────────────────────────

test_that "count_lines counts correctly"
text=$'line1\nline2\nline3'
assert_output "3" str_count_lines "$text"

test_that "get_line returns correct line"
text=$'alpha\nbeta\ngamma'
assert_output "beta" str_get_line "$text" 2

test_that "assert_line checks line content"
text=$'first\nsecond\nthird'
assert_line "first" 1 "$text"
assert_line "second" 2 "$text"
assert_line "third" 3 "$text"

# ── Join / Split ─────────────────────────────────────────────────────────────

test_that "join combines with separator"
assert_output "a,b,c" str_join "," "a" "b" "c"

test_that "join with single item"
assert_output "only" str_join "," "only"

test_that "split_first returns before delimiter"
assert_output "hello" str_split_first "hello:world" ":"

test_that "split_last returns after delimiter"
assert_output "world" str_split_last "hello:world" ":"

# ── Regex match (assert_match) ──────────────────────────────────────────────

test_that "email-like pattern matches"
assert_match "[a-z]+@[a-z]+\\.[a-z]+" "user@example.com"

test_that "version pattern matches semver-like"
version="v1.2.3"
assert_match "^v[0-9]+\\.[0-9]+\\.[0-9]+$" "$version"

test_that "upper result matches all-caps pattern"
result=$(str_upper "hello")
assert_match "^[A-Z]+$" "$result"

# ── Multi-line output (assert_line, assert_contains) ─────────────────────────

test_that "words splits into lines"
result=$(str_words "hello world foo")
assert_line "hello" 1 "$result"
assert_line "world" 2 "$result"
assert_line "foo" 3 "$result"
assert_contains "$result" "world"
assert_not_contains "$result" "bar"

ptyunit_test_summary
